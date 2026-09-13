#!/usr/bin/env python3
"""Session store for the AI sidebar.

One JSON file per conversation under SESSIONS_DIR, plus an `index.json` that
lists them so the sidebar never has to open every file to draw the list. The
files are the source of truth; the index is a cache that can always be rebuilt
from them.

Envelope (schema 3):
    {"schema": 1, "id", "title", "createdAt", "updatedAt", "pinned",
     "modelId", "thinking", "temperature", "promptFile", "personaId",
     "promptOverride", "messages": [...], "searchQueries": [...],
     "sources": [...], "toolCheckpoints": [...]}

Index entry: id, title, createdAt, updatedAt, pinned, modelId, messageCount,
preview.

Subcommands, each printing one JSON object on stdout:

    bootstrap DIR [LEGACY_DIR] [RETENTION_DAYS]
                                 make the dir, prune expired trash, import old
                                 chats once, and return the index
    save      DIR ID             read the session from stdin, write it, return the index
    open      DIR ID             return the whole session
    delete    DIR ID             move it to the trash, return the index
    restore   DIR ID             take it back out of the trash, return the index
    purge     DIR ID             permanently remove one trashed chat
    purge-expired DIR DAYS       permanently remove expired trashed chats
    duplicate DIR ID NEW_ID      copy it under a new id, return the index
    patch     DIR ID [--title T] [--pinned 0|1]
    export    DIR ID OUT_PATH    write Markdown, return the path
    search    DIR QUERY          ids whose title or messages contain the query

Errors are reported as {"error": "..."} with exit code 0: a failed session
operation is something the sidebar should say, not something that should look
like a crashed helper.
"""

import json
import os
import shutil
import sys
import time
import tempfile
import uuid
from typing import Any

SCHEMA = 3
INDEX_NAME = "index.json"
TRASH_NAME = ".trash"
STAGING_NAME = ".staging"
IMPORT_MARKER = ".imported"
PREVIEW_LENGTH = 120


def now_ms() -> int:
    return int(time.time() * 1000)


def read_json(path: str) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def write_json(path: str, payload: Any) -> bool:
    # Written beside the target and renamed, so a session file is never left
    # half-written if the shell dies mid-save.
    directory = os.path.dirname(path) or "."
    tmp = ""
    try:
        os.makedirs(directory, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=directory,
            prefix=f".{os.path.basename(path)}.", suffix=".tmp", delete=False
        ) as handle:
            tmp = handle.name
            json.dump(payload, handle, ensure_ascii=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
        return True
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        return False


def session_path(directory: str, session_id: str) -> str:
    return os.path.join(directory, f"{session_id}.json")


def trash_path(directory: str, session_id: str) -> str:
    return os.path.join(directory, TRASH_NAME, f"{session_id}.json")


def staging_path(directory: str, operation_id: str) -> str:
    return os.path.join(directory, STAGING_NAME, f"{operation_id}.json")


def valid_operation_id(operation_id: str) -> bool:
    return bool(operation_id) and all(character.isalnum() or character in "-_" for character in operation_id)


def plain_text(message: dict) -> str:
    text = message.get("rawContent") or message.get("content") or ""
    if not isinstance(text, str):
        return ""
    return text


def preview_of(messages: list) -> str:
    for message in messages:
        if not isinstance(message, dict):
            continue
        if message.get("role") != "user":
            continue
        text = " ".join(plain_text(message).split())
        if text:
            return text[:PREVIEW_LENGTH]
    for message in messages:
        if isinstance(message, dict):
            text = " ".join(plain_text(message).split())
            if text:
                return text[:PREVIEW_LENGTH]
    return ""


def normalize(session: Any, fallback_id: str = "") -> dict | None:
    if not isinstance(session, dict):
        return None
    messages = session.get("messages")
    if not isinstance(messages, list):
        messages = []
    stamp = now_ms()
    created = session.get("createdAt")
    updated = session.get("updatedAt")
    normalized = dict(session)
    normalized.update({
        "schema": SCHEMA,
        "id": str(session.get("id") or fallback_id or uuid.uuid4()),
        "title": str(session.get("title") or ""),
        "createdAt": int(created) if isinstance(created, (int, float)) else stamp,
        "updatedAt": int(updated) if isinstance(updated, (int, float)) else stamp,
        "pinned": bool(session.get("pinned", False)),
        "modelId": str(session.get("modelId") or ""),
        "thinking": str(session.get("thinking") or ""),
        "temperature": session.get("temperature", None),
        "promptFile": str(session.get("promptFile") or ""),
        "personaId": str(session.get("personaId") or ""),
        "promptOverride": str(session.get("promptOverride") or ""),
        "messages": messages,
        "searchQueries": [str(value) for value in session.get("searchQueries", []) if str(value)],
        "sources": [value for value in session.get("sources", []) if isinstance(value, dict)],
        "toolCheckpoints": [value for value in session.get("toolCheckpoints", []) if isinstance(value, dict)],
        "activityEvents": [value for value in session.get("activityEvents", []) if isinstance(value, dict)],
        # Where the chat came from, and how it is filed.
        "parentId": str(session.get("parentId") or ""),
        "branchMessageId": str(session.get("branchMessageId") or ""),
        "tags": [str(tag) for tag in session.get("tags", []) if str(tag).strip()],
        "projectId": str(session.get("projectId") or ""),
        "contextSummary": str(session.get("contextSummary") or ""),
        "contextSummaryKey": str(session.get("contextSummaryKey") or ""),
    })
    return normalized


def entry_of(session: dict) -> dict:
    messages = session.get("messages") or []
    run = session.get("run") if isinstance(session.get("run"), dict) else {}
    return {
        "id": session["id"],
        "title": session["title"],
        "createdAt": session["createdAt"],
        "updatedAt": session["updatedAt"],
        "pinned": session["pinned"],
        "modelId": session["modelId"],
        "messageCount": len(messages),
        "preview": preview_of(messages),
        "runId": str(run.get("runId") or ""),
        "runState": str(run.get("state") or ""),
        "needsInspection": run.get("state") == "needsInspection",
        "isSeen": bool(run.get("isSeen", True)),
        "parentId": session.get("parentId", ""),
        "branchMessageId": session.get("branchMessageId", ""),
        "tags": session.get("tags", []),
        "projectId": session.get("projectId", ""),
    }


def sort_entries(entries: list) -> list:
    return sorted(
        entries,
        key=lambda entry: (0 if entry.get("pinned") else 1, -int(entry.get("updatedAt") or 0)),
    )


def rebuild_index(directory: str) -> list:
    entries = []
    try:
        names = sorted(os.listdir(directory))
    except OSError:
        names = []
    for name in names:
        if not name.endswith(".json") or name == INDEX_NAME:
            continue
        session = normalize(read_json(os.path.join(directory, name)), name[: -len(".json")])
        if session is None:
            continue
        entries.append(entry_of(session))
    return sort_entries(entries)


def load_index(directory: str, rebuild_if_missing: bool = True) -> list:
    raw = read_json(os.path.join(directory, INDEX_NAME))
    if isinstance(raw, dict) and isinstance(raw.get("sessions"), list):
        return sort_entries([entry for entry in raw["sessions"] if isinstance(entry, dict)])
    if not rebuild_if_missing:
        return []
    return rebuild_index(directory)


def save_index(directory: str, entries: list) -> list | None:
    entries = sort_entries(entries)
    if not write_json(os.path.join(directory, INDEX_NAME), {"schema": SCHEMA, "sessions": entries}):
        return None
    return entries


def emit_index(directory: str, entries: list, **extra: Any) -> int:
    """Never report a successful mutation when the index write failed."""
    saved = save_index(directory, entries)
    if saved is None:
        return emit({"error": "Could not write the session index"})
    return emit({"sessions": saved, **extra})


def upsert(entries: list, entry: dict) -> list:
    kept = [existing for existing in entries if existing.get("id") != entry["id"]]
    kept.append(entry)
    return sort_entries(kept)


def import_legacy(directory: str, legacy_dir: str) -> int:
    """Brings the old flat chats in once. The originals are left alone."""
    marker = os.path.join(directory, IMPORT_MARKER)
    if os.path.exists(marker) or not legacy_dir or not os.path.isdir(legacy_dir):
        return 0
    imported = 0
    try:
        names = sorted(os.listdir(legacy_dir))
    except OSError:
        names = []
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(legacy_dir, name)
        raw = read_json(path)
        if not isinstance(raw, list) or not raw:
            continue
        stem = name[: -len(".json")]
        title = "Last session" if stem == "lastSession" else stem
        try:
            stamp = int(os.path.getmtime(path) * 1000)
        except OSError:
            stamp = now_ms()
        session = normalize(
            {
                "id": str(uuid.uuid4()),
                "title": title,
                "createdAt": stamp,
                "updatedAt": stamp,
                "messages": raw,
            }
        )
        if session is None:
            continue
        if write_json(session_path(directory, session["id"]), session):
            imported += 1
    try:
        with open(marker, "w", encoding="utf-8") as handle:
            handle.write(str(now_ms()))
    except OSError:
        pass
    return imported


def prune_staging(directory: str) -> int:
    """Discard uncommitted first-turn snapshots left by a crashed shell.

    A staged submission is deliberately not canonical until commit-staged has
    updated the session and index. Bootstrap is the only safe owner of these
    files, so an interrupted process cannot resurrect a ghost turn later.
    """
    staging = os.path.join(directory, STAGING_NAME)
    removed = 0
    try:
        names = os.listdir(staging)
    except OSError:
        return 0
    for name in names:
        path = os.path.join(staging, name)
        if not os.path.isfile(path):
            continue
        try:
            os.unlink(path)
            removed += 1
        except OSError:
            continue
    try:
        if not os.listdir(staging):
            os.rmdir(staging)
    except OSError:
        pass
    return removed


def retention_days(value: Any) -> int:
    """Keep the destructive retention window bounded even for manual calls."""
    try:
        return max(1, min(3650, int(value)))
    except (TypeError, ValueError):
        return 30


def prune_expired_trash(directory: str, days: Any) -> int:
    """Remove only aged, valid session files from this store's trash folder.

    Moving a chat into `.trash` refreshes its mtime, so retention measures the
    time since deletion rather than the date the conversation was last edited.
    Unknown files are deliberately left untouched.
    """
    cutoff = time.time() - (retention_days(days) * 24 * 60 * 60)
    trash = os.path.join(directory, TRASH_NAME)
    removed = 0
    try:
        names = os.listdir(trash)
    except OSError:
        return 0
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(trash, name)
        session_id = name[: -len(".json")]
        raw = read_json(path)
        # Do not turn this maintenance task into a broad delete: it owns only
        # well-formed session files whose id agrees with their filename.
        if not isinstance(raw, dict) or str(raw.get("id") or "") != session_id:
            continue
        try:
            if os.path.getmtime(path) > cutoff:
                continue
            os.unlink(path)
            removed += 1
        except OSError:
            continue
    return removed


def markdown_of(session: dict) -> str:
    lines = [f"# {session['title'] or 'Untitled chat'}", ""]
    stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(session["updatedAt"] / 1000))
    meta = [stamp]
    if session.get("modelId"):
        meta.append(session["modelId"])
    lines.append("*" + " · ".join(meta) + "*")
    lines.append("")
    for message in session.get("messages") or []:
        if not isinstance(message, dict):
            continue
        if message.get("visibleToUser") is False:
            continue
        role = message.get("role") or "assistant"
        heading = {"user": "You", "assistant": "Assistant", "interface": "Interface"}.get(role, role)
        lines.append(f"## {heading}")
        lines.append("")
        lines.append(plain_text(message).strip())
        lines.append("")
    return "\n".join(lines)


def emit(payload: dict) -> int:
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def cmd_bootstrap(argv: list) -> int:
    directory = argv[0]
    legacy = argv[1] if len(argv) > 1 else ""
    os.makedirs(directory, exist_ok=True)
    pruned = prune_staging(directory)
    trash_pruned = prune_expired_trash(directory, argv[2] if len(argv) > 2 else 30)
    imported = import_legacy(directory, legacy)
    entries = rebuild_index(directory) if imported else load_index(directory)
    return emit_index(directory, entries, imported=imported, stagingPruned=pruned, trashPurged=trash_pruned)


def cmd_save(argv: list) -> int:
    directory, session_id = argv[0], argv[1]
    session = normalize(read_json_stdin(), session_id)
    if session is None:
        return emit({"error": "Malformed session"})
    session["id"] = session_id
    if not write_json(session_path(directory, session_id), session):
        return emit({"error": "Could not write the session file"})
    entries = upsert(load_index(directory), entry_of(session))
    return emit_index(directory, entries)


def cmd_stage(argv: list) -> int:
    directory, session_id, operation_id = argv[0], argv[1], argv[2]
    if not valid_operation_id(operation_id):
        return emit({"error": "Invalid staging operation id"})
    session = normalize(read_json_stdin(), session_id)
    if session is None:
        return emit({"error": "Malformed session"})
    session["id"] = session_id
    if not write_json(staging_path(directory, operation_id), session):
        return emit({"error": "Could not stage the session"})
    return emit({"staged": True, "operationId": operation_id, "id": session_id})


def cmd_commit_staged(argv: list) -> int:
    directory, session_id, operation_id = argv[0], argv[1], argv[2]
    if not valid_operation_id(operation_id):
        return emit({"error": "Invalid staging operation id"})
    staged = normalize(read_json(staging_path(directory, operation_id)), session_id)
    if staged is None or staged.get("id") != session_id:
        return emit({"error": "Staged session is missing or invalid"})
    if not write_json(session_path(directory, session_id), staged):
        return emit({"error": "Could not commit the staged session"})
    entries = upsert(load_index(directory), entry_of(staged))
    saved = save_index(directory, entries)
    if saved is None:
        return emit({"error": "Could not write the session index"})
    result = emit({"sessions": saved, "committed": True, "operationId": operation_id})
    # Keep the staging record until the index ACK succeeds. If the index write
    # failed, a retry can safely repeat the canonical write and rebuild the
    # cache instead of losing the only transaction marker.
    if result == 0:
        try:
            os.unlink(staging_path(directory, operation_id))
        except OSError:
            pass
    return result


def cmd_abort_staged(argv: list) -> int:
    directory, session_id, operation_id = argv[0], argv[1], argv[2]
    if not valid_operation_id(operation_id):
        return emit({"error": "Invalid staging operation id"})
    try:
        os.unlink(staging_path(directory, operation_id))
    except FileNotFoundError:
        pass
    except OSError:
        return emit({"error": "Could not abort the staged session"})
    return emit({"aborted": True, "operationId": operation_id, "id": session_id})


def read_json_stdin() -> Any:
    try:
        return json.loads(sys.stdin.read())
    except ValueError:
        return None


def cmd_open(argv: list) -> int:
    directory, session_id = argv[0], argv[1]
    session = normalize(read_json(session_path(directory, session_id)), session_id)
    if session is None:
        return emit({"error": "That chat is gone from disk"})
    return emit({"session": session})


def cmd_delete(argv: list) -> int:
    directory, session_id = argv[0], argv[1]
    source = session_path(directory, session_id)
    if not os.path.exists(source):
        return emit_index(directory, load_index(directory))
    os.makedirs(os.path.join(directory, TRASH_NAME), exist_ok=True)
    try:
        destination = trash_path(directory, session_id)
        # Both paths live in the same store. `replace` is atomic and touching
        # the destination records the moment it entered the trash.
        os.replace(source, destination)
        os.utime(destination, None)
    except OSError:
        return emit({"error": "Could not delete that chat"})
    entries = [entry for entry in load_index(directory) if entry.get("id") != session_id]
    return emit_index(directory, entries)


def cmd_restore(argv: list) -> int:
    directory, session_id = argv[0], argv[1]
    source = trash_path(directory, session_id)
    if not os.path.exists(source):
        return emit({"error": "Nothing left to bring back"})
    try:
        shutil.move(source, session_path(directory, session_id))
    except OSError:
        return emit({"error": "Could not bring that chat back"})
    session = normalize(read_json(session_path(directory, session_id)), session_id)
    if session is None:
        return emit({"error": "That chat came back unreadable"})
    entries = upsert(load_index(directory), entry_of(session))
    return emit_index(directory, entries, session=session)


def cmd_purge(argv: list) -> int:
    """Permanently remove a chat, but only after it is already in the trash."""
    directory, session_id = argv[0], argv[1]
    target = trash_path(directory, session_id)
    if not os.path.exists(target):
        return emit({"error": "That chat is not in the trash"})
    try:
        os.unlink(target)
    except OSError:
        return emit({"error": "Could not permanently remove that chat"})
    return emit_index(directory, load_index(directory), purged=session_id)


def cmd_purge_expired(argv: list) -> int:
    directory, days = argv[0], argv[1]
    os.makedirs(directory, exist_ok=True)
    removed = prune_expired_trash(directory, days)
    return emit_index(directory, load_index(directory), trashPurged=removed)


def cmd_duplicate(argv: list) -> int:
    directory, session_id, new_id = argv[0], argv[1], argv[2]
    session = normalize(read_json(session_path(directory, session_id)), session_id)
    if session is None:
        return emit({"error": "That chat is gone from disk"})
    stamp = now_ms()
    session["id"] = new_id
    session["title"] = (session["title"] or "Untitled chat") + " (copy)"
    session["createdAt"] = stamp
    session["updatedAt"] = stamp
    session["pinned"] = False
    if not write_json(session_path(directory, new_id), session):
        return emit({"error": "Could not write the copy"})
    entries = upsert(load_index(directory), entry_of(session))
    return emit_index(directory, entries, id=new_id)


def cmd_patch(argv: list) -> int:
    directory, session_id = argv[0], argv[1]
    session = normalize(read_json(session_path(directory, session_id)), session_id)
    if session is None:
        return emit({"error": "That chat is gone from disk"})
    rest = argv[2:]
    while rest:
        flag = rest.pop(0)
        if flag == "--title" and rest:
            session["title"] = rest.pop(0)
        elif flag == "--pinned" and rest:
            session["pinned"] = rest.pop(0) not in ("0", "false", "False")
        elif flag == "--tags" and rest:
            # One comma-separated argument, so a chat with no tags is still a
            # single well-formed call.
            raw = rest.pop(0)
            session["tags"] = [tag.strip() for tag in raw.split(",") if tag.strip()]
        elif flag == "--project" and rest:
            session["projectId"] = rest.pop(0)
    if not write_json(session_path(directory, session_id), session):
        return emit({"error": "Could not write the session file"})
    entries = upsert(load_index(directory), entry_of(session))
    return emit_index(directory, entries)


def cmd_export(argv: list) -> int:
    directory, session_id, out_path = argv[0], argv[1], argv[2]
    session = normalize(read_json(session_path(directory, session_id)), session_id)
    if session is None:
        return emit({"error": "That chat is gone from disk"})
    try:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        with open(out_path, "w", encoding="utf-8") as handle:
            handle.write(markdown_of(session))
    except OSError:
        return emit({"error": "Could not write the Markdown file"})
    return emit({"path": out_path})


def cmd_search(argv: list) -> int:
    directory = argv[0]
    needle = (argv[1] if len(argv) > 1 else "").strip().lower()
    if not needle:
        return emit({"ids": [], "query": ""})
    ids = []
    for entry in load_index(directory):
        session_id = entry.get("id")
        if not session_id:
            continue
        if needle in str(entry.get("title", "")).lower():
            ids.append(session_id)
            continue
        session = read_json(session_path(directory, session_id))
        if not isinstance(session, dict):
            continue
        for message in session.get("messages") or []:
            if isinstance(message, dict) and needle in plain_text(message).lower():
                ids.append(session_id)
                break
    return emit({"ids": ids, "query": needle})


COMMANDS = {
    "bootstrap": (1, cmd_bootstrap),
    "save": (2, cmd_save),
    "stage": (3, cmd_stage),
    "commit-staged": (3, cmd_commit_staged),
    "abort-staged": (3, cmd_abort_staged),
    "open": (2, cmd_open),
    "delete": (2, cmd_delete),
    "restore": (2, cmd_restore),
    "purge": (2, cmd_purge),
    "purge-expired": (2, cmd_purge_expired),
    "duplicate": (3, cmd_duplicate),
    "patch": (2, cmd_patch),
    "export": (3, cmd_export),
    "search": (1, cmd_search),
}


def main() -> int:
    argv = sys.argv[1:]
    if not argv or argv[0] not in COMMANDS:
        return emit({"error": "Unknown session command"})
    arity, handler = COMMANDS[argv[0]]
    rest = argv[1:]
    if len(rest) < arity:
        return emit({"error": "Missing arguments"})
    try:
        return handler(rest)
    except Exception as error:  # noqa: BLE001 - the shell wants a message, not a traceback
        return emit({"error": str(error)})


if __name__ == "__main__":
    sys.exit(main())
