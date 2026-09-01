#!/usr/bin/env python3
"""Opt-in local RAG: chunk a folder, embed it with Ollama, search it later.

Every collection is a folder the user named explicitly through Settings —
never a guess, never the whole home directory. Embeddings never leave this
machine: they go to whatever Ollama endpoint the shell already uses for the
active model, over the same loopback connection the chat itself talks to.

Four verbs, one JSON request on stdin each:

    index   — walks `path`, chunks and embeds what changed since last time,
              writes the collection to `<indexDir>/<collectionId>.json`, and
              streams progress as JSON lines rather than one final blob,
              because embedding a few thousand chunks is not instant.
    search  — embeds a query and returns the closest chunks across one or
              more collections, each with its file and line range.
    status  — file/chunk/byte counts per collection, for the Settings page.
    delete  — removes one collection's index file.

`index` is the only verb that reaches outside `indexDir`, and only under
`path`. `is_sensitive_path`/`canonical_root` come from `ai_attach.py`, the
same file `files_search` already trusts for exactly this judgement, so the
two tools can never quietly disagree about what is safe to read.
"""

from __future__ import annotations

import json
import math
import os
import stat
import sys
import time
import urllib.error
import urllib.request

import ai_attach  # noqa: E402  (same directory; sys.path[0] already covers it)


# ── Bounds ──────────────────────────────────────────────────────────────
# Indexing is a background maintenance job, not a tool call with a tight
# deadline, so its ceilings are generous rather than snappy — but they are
# still ceilings. A folder with a million files must not turn into an
# unbounded walk, and a single embedding request must not hang the process
# forever waiting on a model Ollama has not finished loading.
MAX_ENTRIES_SCANNED_INDEX = 50_000
MAX_DEPTH_INDEX = 12
MAX_FILES_HARD_CAP = 20_000
MAX_FILE_BYTES_HARD_CAP = 8_000_000
MAX_CHUNKS_HARD_CAP = 20_000
MAX_CHUNKS_PER_FILE = 80
INDEX_DEADLINE_SECONDS = 300.0
EMBED_TIMEOUT_SECONDS = 60.0
EMBED_BATCH_SIZE = 16
SEARCH_RESULT_HARD_CAP = 10
SNIPPET_CHARS = 600
DEFAULT_OLLAMA_URL = "http://127.0.0.1:11434"

IGNORE_DIR_NAMES = {
    "node_modules", "__pycache__", "dist", "build", "target", "vendor",
    ".venv", "venv", "out",
}

TEXT_EXTENSIONS = {
    ".txt", ".md", ".markdown", ".mdx", ".rst", ".org", ".log", ".csv", ".tsv",
    ".json", ".jsonl", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf",
    ".py", ".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx", ".qml",
    ".sh", ".bash", ".zsh", ".fish",
    ".c", ".h", ".cpp", ".hpp", ".cc", ".java", ".go", ".rs", ".rb", ".lua", ".php",
    ".html", ".htm", ".css", ".scss", ".xml", ".sql", ".svelte", ".vue",
}
EXTENSIONLESS_ALLOWED_NAMES = {
    "readme", "license", "licence", "changelog", "makefile", "dockerfile",
    "notes", "todo", "authors", "contributing",
}


def is_indexable_name(filename: str) -> bool:
    extension = os.path.splitext(filename)[1].lower()
    if extension in TEXT_EXTENSIONS:
        return True
    if extension:
        return False
    return filename.lower() in EXTENSIONLESS_ALLOWED_NAMES


def normalize(vector: list[float]) -> list[float]:
    """Unit-length vectors turn search-time cosine similarity into a plain
    dot product — computed once here, never repeated per query."""
    norm = math.sqrt(sum(component * component for component in vector))
    if norm <= 1e-12:
        return vector
    return [component / norm for component in vector]


def ollama_embed(ollama_url: str, model: str, texts: list[str]) -> list[list[float]]:
    base = ollama_url.rstrip("/")
    try:
        payload = json.dumps({"model": model, "input": texts}).encode("utf-8")
        request = urllib.request.Request(
            f"{base}/api/embed", data=payload,
            headers={"Content-Type": "application/json"}, method="POST",
        )
        with urllib.request.urlopen(request, timeout=EMBED_TIMEOUT_SECONDS) as response:
            data = json.loads(response.read().decode("utf-8"))
        embeddings = data.get("embeddings")
        if isinstance(embeddings, list) and len(embeddings) == len(texts):
            return embeddings
        raise RuntimeError("Ollama returned no embeddings")
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        # Ollama before the batch /api/embed endpoint: one prompt at a time
        # through the older singular /api/embeddings.
        results = []
        for text in texts:
            payload = json.dumps({"model": model, "prompt": text}).encode("utf-8")
            request = urllib.request.Request(
                f"{base}/api/embeddings", data=payload,
                headers={"Content-Type": "application/json"}, method="POST",
            )
            with urllib.request.urlopen(request, timeout=EMBED_TIMEOUT_SECONDS) as response:
                data = json.loads(response.read().decode("utf-8"))
            vector = data.get("embedding")
            if not isinstance(vector, list):
                raise RuntimeError("Ollama returned no embedding")
            results.append(vector)
        return results


def chunk_lines(lines: list[str], chunk_chars: int, overlap_lines: int, max_chunks: int) -> list[dict]:
    """Overlapping windows of lines, so a fact split across a chunk boundary
    is still whole in at least one of the two chunks touching it."""
    chunks: list[dict] = []
    total = len(lines)
    start = 0
    while start < total and len(chunks) < max_chunks:
        end = start
        char_count = 0
        while end < total and (char_count < chunk_chars or end == start):
            char_count += len(lines[end]) + 1
            end += 1
        chunks.append({
            "startLine": start + 1,
            "endLine": end,
            "text": "\n".join(lines[start:end]),
        })
        if end >= total:
            break
        start = max(end - overlap_lines, start + 1)
    return chunks


def index_collection(request: dict) -> None:
    collection_id = str(request.get("collectionId", "")).strip()
    if not collection_id:
        raise ValueError("collectionId is required")
    index_dir = str(request.get("indexDir", "")).strip()
    if not index_dir:
        raise ValueError("indexDir is required")
    os.makedirs(index_dir, exist_ok=True)

    root = ai_attach.canonical_root(str(request.get("path", "")))
    if not root:
        raise ValueError("That path is not a directory")
    home = os.path.realpath(os.path.expanduser("~"))
    if root == home:
        raise ValueError("The entire home directory cannot be indexed. Choose a specific folder.")
    if ai_attach.is_sensitive_path(root):
        raise ValueError("That folder looks like a credential or configuration location and cannot be indexed.")

    embedding_model = str(request.get("embeddingModel", "")).strip()
    if not embedding_model:
        raise ValueError("embeddingModel is required")
    ollama_url = str(request.get("ollamaUrl", "")).strip() or DEFAULT_OLLAMA_URL
    max_files = max(1, min(int(request.get("maxFiles", 3000)), MAX_FILES_HARD_CAP))
    max_file_bytes = max(1024, min(int(request.get("maxFileBytes", 2_000_000)), MAX_FILE_BYTES_HARD_CAP))
    max_chunks_total = max(10, min(int(request.get("maxChunks", MAX_CHUNKS_HARD_CAP)), MAX_CHUNKS_HARD_CAP))
    chunk_chars = max(200, min(int(request.get("chunkChars", 1200)), 4000))
    overlap_lines = max(0, min(int(request.get("chunkOverlapLines", 3)), 20))

    index_path = os.path.join(index_dir, f"{collection_id}.json")
    previous: dict = {}
    if os.path.isfile(index_path):
        try:
            with open(index_path, "r", encoding="utf-8") as handle:
                previous = json.load(handle)
        except (OSError, ValueError):
            previous = {}
    previous_files = previous.get("files", {}) if isinstance(previous, dict) else {}

    files_out: dict = {}
    pending: list[tuple[str, float, int, list[dict]]] = []
    files_indexed = files_reused = files_skipped = chunks_total = scanned = 0
    truncated = False
    seen_real_dirs: set[str] = set()
    root_depth = root.rstrip(os.sep).count(os.sep)
    deadline = time.monotonic() + INDEX_DEADLINE_SECONDS

    for current_dir, subdirs, filenames in os.walk(root, followlinks=False):
        if scanned > MAX_ENTRIES_SCANNED_INDEX or time.monotonic() > deadline:
            truncated = True
            break
        depth = current_dir.rstrip(os.sep).count(os.sep) - root_depth
        if depth >= MAX_DEPTH_INDEX:
            subdirs[:] = []
            continue

        keep = []
        for subdir in subdirs:
            if subdir.startswith(".") or subdir in IGNORE_DIR_NAMES:
                continue
            candidate = os.path.join(current_dir, subdir)
            real = os.path.realpath(candidate)
            if real in seen_real_dirs or ai_attach.is_sensitive_path(candidate):
                continue
            seen_real_dirs.add(real)
            keep.append(subdir)
        subdirs[:] = keep

        for filename in sorted(filenames):
            scanned += 1
            if scanned > MAX_ENTRIES_SCANNED_INDEX or time.monotonic() > deadline:
                truncated = True
                break
            if filename.startswith(".") or not is_indexable_name(filename):
                continue
            full_path = os.path.join(current_dir, filename)
            if ai_attach.is_sensitive_path(full_path):
                continue
            if len(files_out) + len(pending) >= max_files:
                truncated = True
                continue
            try:
                info = os.stat(full_path, follow_symlinks=True)
            except OSError:
                continue
            if not stat.S_ISREG(info.st_mode):
                continue
            if info.st_size > max_file_bytes:
                files_skipped += 1
                continue

            relative_path = os.path.relpath(full_path, root)
            previous_entry = previous_files.get(relative_path)
            if (isinstance(previous_entry, dict)
                    and abs(float(previous_entry.get("mtime", -1)) - info.st_mtime) < 0.001
                    and int(previous_entry.get("size", -1)) == info.st_size):
                files_out[relative_path] = previous_entry
                files_reused += 1
                chunks_total += len(previous_entry.get("chunks", []))
                continue

            try:
                with open(full_path, "r", encoding="utf-8") as handle:
                    text = handle.read()
            except (OSError, UnicodeDecodeError):
                files_skipped += 1
                continue
            if not text.strip():
                files_skipped += 1
                continue

            remaining_budget = max_chunks_total - chunks_total
            if remaining_budget <= 0:
                truncated = True
                continue
            chunks = chunk_lines(text.split("\n"), chunk_chars, overlap_lines,
                                  max_chunks=min(MAX_CHUNKS_PER_FILE, remaining_budget))
            if not chunks:
                files_skipped += 1
                continue
            pending.append((relative_path, info.st_mtime, info.st_size, chunks))
            files_indexed += 1
            chunks_total += len(chunks)
        if truncated:
            break

    batch_texts: list[str] = []
    batch_refs: list[tuple[str, int]] = []
    embedded_so_far = 0

    def flush_batch() -> None:
        nonlocal batch_texts, batch_refs, embedded_so_far
        if not batch_texts:
            return
        vectors = ollama_embed(ollama_url, embedding_model, batch_texts)
        for (relative_path, chunk_index), vector in zip(batch_refs, vectors):
            files_out[relative_path]["chunks"][chunk_index]["vector"] = normalize(vector)
        embedded_so_far += len(batch_texts)
        print(json.dumps({
            "event": "progress",
            "filesDone": files_indexed + files_reused + files_skipped,
            "filesTotal": files_indexed + files_reused + files_skipped,
            "chunksDone": embedded_so_far,
            "chunksTotal": chunks_total,
        }), flush=True)
        batch_texts = []
        batch_refs = []

    for relative_path, mtime, size, chunks in pending:
        files_out[relative_path] = {"mtime": mtime, "size": size, "chunks": chunks}
        for chunk_index, chunk in enumerate(chunks):
            batch_texts.append(chunk["text"])
            batch_refs.append((relative_path, chunk_index))
            if len(batch_texts) >= EMBED_BATCH_SIZE:
                flush_batch()
    flush_batch()

    now = time.time()
    document = {
        "collectionId": collection_id,
        "path": root,
        "embeddingModel": embedding_model,
        "createdAt": previous.get("createdAt", now) if isinstance(previous, dict) else now,
        "updatedAt": now,
        "files": files_out,
    }
    tmp_path = f"{index_path}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False)
    os.replace(tmp_path, index_path)

    print(json.dumps({
        "event": "done",
        "collectionId": collection_id,
        "filesIndexed": files_indexed,
        "filesReused": files_reused,
        "filesSkipped": files_skipped,
        "chunksTotal": chunks_total,
        "sizeBytes": os.path.getsize(index_path),
        "updatedAt": now,
        "truncated": truncated,
    }), flush=True)


def load_collections(index_dir: str, wanted_ids: list[str] | None) -> list[dict]:
    collections = []
    if not os.path.isdir(index_dir):
        return collections
    for name in sorted(os.listdir(index_dir)):
        if not name.endswith(".json") or name.endswith(".json.tmp"):
            continue
        collection_id = name[:-len(".json")]
        if wanted_ids is not None and collection_id not in wanted_ids:
            continue
        try:
            with open(os.path.join(index_dir, name), "r", encoding="utf-8") as handle:
                doc = json.load(handle)
        except (OSError, ValueError):
            continue
        if isinstance(doc, dict):
            doc.setdefault("collectionId", collection_id)
            collections.append(doc)
    return collections


def run_search(request: dict) -> dict:
    index_dir = str(request.get("indexDir", "")).strip()
    if not index_dir:
        raise ValueError("indexDir is required")
    query = str(request.get("query", "")).strip()
    if not query:
        raise ValueError("query is required")
    embedding_model = str(request.get("embeddingModel", "")).strip()
    if not embedding_model:
        raise ValueError("embeddingModel is required")
    ollama_url = str(request.get("ollamaUrl", "")).strip() or DEFAULT_OLLAMA_URL
    limit = max(1, min(int(request.get("limit", 5)), SEARCH_RESULT_HARD_CAP))
    raw_ids = request.get("collectionIds")
    wanted_ids = [str(entry) for entry in raw_ids] if isinstance(raw_ids, list) and raw_ids else None

    collections = load_collections(index_dir, wanted_ids)
    if not collections:
        return {"results": [], "collectionsSearched": 0, "totalChunks": 0, "query": query}

    query_vector = normalize(ollama_embed(ollama_url, embedding_model, [query])[0])

    scored: list[tuple[float, str, str, dict]] = []
    total_chunks = 0
    for doc in collections:
        collection_id = str(doc.get("collectionId", ""))
        for relative_path, entry in (doc.get("files") or {}).items():
            for chunk in entry.get("chunks", []) if isinstance(entry, dict) else []:
                vector = chunk.get("vector")
                if not isinstance(vector, list) or len(vector) != len(query_vector):
                    continue
                total_chunks += 1
                score = sum(a * b for a, b in zip(query_vector, vector))
                scored.append((score, collection_id, relative_path, chunk))

    scored.sort(key=lambda item: item[0], reverse=True)
    results = []
    for score, collection_id, relative_path, chunk in scored[:limit]:
        snippet = str(chunk.get("text", ""))
        if len(snippet) > SNIPPET_CHARS:
            snippet = snippet[:SNIPPET_CHARS] + "…"
        results.append({
            "collectionId": collection_id,
            "file": relative_path,
            "startLine": chunk.get("startLine"),
            "endLine": chunk.get("endLine"),
            "score": round(score, 4),
            "snippet": snippet,
        })
    return {
        "results": results,
        "collectionsSearched": len(collections),
        "totalChunks": total_chunks,
        "query": query,
    }


def run_status(request: dict) -> dict:
    index_dir = str(request.get("indexDir", "")).strip()
    wanted = str(request.get("collectionId") or "").strip()
    collections = []
    for doc in load_collections(index_dir, [wanted] if wanted else None):
        files = doc.get("files") or {}
        chunk_count = sum(len(entry.get("chunks", [])) for entry in files.values() if isinstance(entry, dict))
        full_path = os.path.join(index_dir, f"{doc.get('collectionId')}.json")
        try:
            size_bytes = os.path.getsize(full_path)
        except OSError:
            size_bytes = 0
        collections.append({
            "collectionId": doc.get("collectionId", ""),
            "path": doc.get("path", ""),
            "embeddingModel": doc.get("embeddingModel", ""),
            "fileCount": len(files),
            "chunkCount": chunk_count,
            "sizeBytes": size_bytes,
            "createdAt": doc.get("createdAt", 0),
            "updatedAt": doc.get("updatedAt", 0),
        })
    return {"collections": collections}


def run_delete(request: dict) -> dict:
    index_dir = str(request.get("indexDir", "")).strip()
    collection_id = str(request.get("collectionId", "")).strip()
    if not collection_id:
        raise ValueError("collectionId is required")
    full_path = os.path.join(index_dir, f"{collection_id}.json")
    deleted = os.path.isfile(full_path)
    if deleted:
        os.remove(full_path)
    return {"deleted": deleted, "collectionId": collection_id}


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"ok": False, "error": "missing verb"}))
        return 1
    verb = sys.argv[1]

    try:
        request = json.loads(sys.stdin.read() or "{}")
        if not isinstance(request, dict):
            raise ValueError("request must be an object")
    except (ValueError, TypeError) as error:
        print(json.dumps({"ok": False, "error": f"invalid request: {error}"}))
        return 1

    call_id = request.get("callId", "")

    if verb == "index":
        try:
            index_collection(request)
            return 0
        except (ValueError, urllib.error.URLError, urllib.error.HTTPError, OSError, RuntimeError) as error:
            print(json.dumps({"event": "fatal", "error": str(error)}), flush=True)
            return 1
        except Exception:  # noqa: BLE001 — a stray traceback must not reach the caller's parser
            print(json.dumps({"event": "fatal", "error": "Indexing failed unexpectedly"}), flush=True)
            return 1

    try:
        if verb == "search":
            data = run_search(request)
        elif verb == "status":
            data = run_status(request)
        elif verb == "delete":
            data = run_delete(request)
        else:
            raise ValueError(f"unsupported verb: {verb}")
        print(json.dumps({"ok": True, "callId": call_id, **data}, ensure_ascii=False))
        return 0
    except (ValueError, TypeError, urllib.error.URLError, urllib.error.HTTPError, RuntimeError, OSError) as error:
        print(json.dumps({"ok": False, "callId": call_id, "error": str(error)}, ensure_ascii=False))
        return 1
    except Exception:  # noqa: BLE001
        print(json.dumps({"ok": False, "callId": call_id, "error": "RAG request failed"}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
