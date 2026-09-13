#!/usr/bin/env python3
"""Google Keep Takeout Importer for Notes App.

Reads an exported Google Takeout archive (.zip) or unzipped directory,
extracting notes (both text notes and checklist notes), labels, colors,
timestamps, and attachments. Converts them into the native NotesDocument
schema and registers them into the store's index.json.

Idempotency:
  Stores the original Google Keep ID (or filename identifier) in the note's
  metadata (meta.cloud.keepId). Re-running the import updates existing notes
  rather than duplicating them.

Usage:
  python3 keep_import.py --takeout <path_to_zip_or_dir> --store <store_dir>
  python3 keep_import.py --takeout <path> --dry-run
  python3 keep_import.py --export-takeout <store_dir> --output <dest_dir>
"""

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import time
import zipfile
from pathlib import Path

COLOR_MAP = {
    "DEFAULT": "",
    "RED": "error",
    "ORANGE": "warning",
    "YELLOW": "warning",
    "GREEN": "success",
    "TEAL": "info",
    "BLUE": "info",
    "CERULEAN": "info",
    "PURPLE": "primary",
    "PINK": "tertiary",
    "BROWN": "subtext",
    "GRAY": "subtext"
}


def emit(payload: dict) -> int:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
    return 0 if payload.get("ok", True) else 1


def generate_id(prefix: str = "nt") -> str:
    timestamp_base36 = base36_encode(int(time.time() * 1000))
    random_part = base36_encode(int.from_bytes(os.urandom(3), "big"))
    return f"{prefix}_{timestamp_base36}_{random_part}"


def base36_encode(number: int) -> str:
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    if number == 0:
        return "0"
    base36 = []
    while number:
        number, i = divmod(number, 36)
        base36.append(alphabet[i])
    return "".join(reversed(base36))


def clean_tag_name(label: str) -> str:
    clean = re.sub(r"[^\w\-_]", "", str(label).strip())
    if not clean:
        return ""
    return clean if clean.startswith("#") else f"#{clean}"


def parse_keep_note_json(data: dict, filename: str) -> dict:
    """Extract structured data from a single Keep JSON file."""
    title = str(data.get("title") or "").strip()
    text_content = str(data.get("textContent") or "")
    list_content = data.get("listContent") or []
    labels = data.get("labels") or []
    color = str(data.get("color") or "DEFAULT").upper()
    is_archived = bool(data.get("isArchived", False))
    is_pinned = bool(data.get("isPinned", False))
    is_trashed = bool(data.get("isTrashed", False))
    
    # Timestamps in microseconds to milliseconds
    created_usec = data.get("createdTimestampUsec")
    edited_usec = data.get("userEditedTimestampUsec")
    
    now_ms = int(time.time() * 1000)
    created_ms = int(created_usec / 1000) if created_usec else now_ms
    modified_ms = int(edited_usec / 1000) if edited_usec else created_ms

    tags = []
    for lbl in labels:
        if isinstance(lbl, dict) and "name" in lbl:
            tag = clean_tag_name(lbl["name"])
            if tag and tag not in tags:
                tags.append(tag)
        elif isinstance(lbl, str):
            tag = clean_tag_name(lbl)
            if tag and tag not in tags:
                tags.append(tag)

    attachments = []
    for att in data.get("attachments") or []:
        if isinstance(att, dict) and "filePath" in att:
            attachments.append(att["filePath"])

    # Unique keepId derived from filename without extension
    keep_id = Path(filename).stem

    return {
        "keepId": keep_id,
        "title": title,
        "textContent": text_content,
        "listContent": list_content,
        "color": color,
        "tone": COLOR_MAP.get(color, ""),
        "tags": tags,
        "isArchived": is_archived,
        "isPinned": is_pinned,
        "isTrashed": is_trashed,
        "created": created_ms,
        "modified": modified_ms,
        "attachments": attachments
    }


def convert_keep_to_document(parsed: dict, note_id: str) -> dict:
    """Build a native NotesDocument object from parsed Keep note data."""
    blocks = []
    block_counter = 0

    def next_block_id():
        nonlocal block_counter
        block_counter += 1
        return f"bk_kp_{note_id[-6:]}_{block_counter}"

    # Heading if title exists
    if parsed["title"]:
        blocks.append({
            "id": next_block_id(),
            "type": "heading",
            "level": 1,
            "text": parsed["title"]
        })

    # Checklist items
    if parsed["listContent"]:
        for item in parsed["listContent"]:
            item_text = str(item.get("text") or "")
            is_checked = bool(item.get("isChecked", False))
            blocks.append({
                "id": next_block_id(),
                "type": "list",
                "style": "checkbox",
                "checked": is_checked,
                "text": item_text,
                "indent": 0
            })

    # Text content lines
    elif parsed["textContent"]:
        lines = parsed["textContent"].split("\n")
        # Collapse excessive consecutive empty lines
        current_para = []
        for line in lines:
            if line.strip() == "":
                if current_para:
                    blocks.append({
                        "id": next_block_id(),
                        "type": "text",
                        "text": "\n".join(current_para),
                        "indent": 0
                    })
                    current_para = []
            else:
                current_para.append(line)
        if current_para:
            blocks.append({
                "id": next_block_id(),
                "type": "text",
                "text": "\n".join(current_para),
                "indent": 0
            })

    # Attachments placeholders (mapped as image blocks or file links)
    for att_path in parsed["attachments"]:
        ext = Path(att_path).suffix.lower()
        if ext in (".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg"):
            blocks.append({
                "id": next_block_id(),
                "type": "image",
                "asset": Path(att_path).name
            })
        else:
            blocks.append({
                "id": next_block_id(),
                "type": "fileLink",
                "path": att_path
            })

    # Fallback block if empty
    if not blocks:
        blocks.append({
            "id": next_block_id(),
            "type": "text",
            "text": "",
            "indent": 0
        })

    return {
        "id": note_id,
        "schema": 1,
        "blocks": blocks,
        "meta": {
            "cloud": {
                "provider": "google_keep",
                "keepId": parsed["keepId"],
                "keepColor": parsed["color"]
            }
        }
    }


def find_existing_note_by_keep_id(store_dir: Path, keep_id: str) -> tuple:
    """Check index.json for an existing note matching keepId."""
    index_file = store_dir / "index.json"
    if not index_file.exists():
        return None, None

    try:
        data = json.loads(index_file.read_text(encoding="utf-8"))
        for note in data.get("notes", []):
            note_id = note.get("id", "")
            doc_file = store_dir / "docs" / f"{note_id}.json"
            if doc_file.exists():
                try:
                    doc = json.loads(doc_file.read_text(encoding="utf-8"))
                    cloud_meta = doc.get("meta", {}).get("cloud", {})
                    if cloud_meta.get("keepId") == keep_id:
                        return note, doc
                except Exception:
                    pass
    except Exception:
        pass

    return None, None


def load_or_init_store(store_dir: Path) -> dict:
    """Ensure directory structure and return parsed index.json."""
    (store_dir / "docs").mkdir(parents=True, exist_ok=True)
    (store_dir / "assets").mkdir(parents=True, exist_ok=True)
    (store_dir / "revisions").mkdir(parents=True, exist_ok=True)

    index_file = store_dir / "index.json"
    if index_file.exists():
        try:
            return json.loads(index_file.read_text(encoding="utf-8"))
        except Exception:
            pass

    default_nb_id = generate_id("nb")
    default_sec_id = generate_id("sc")
    initial_index = {
        "schema": 1,
        "notebooks": [
            {
                "id": default_nb_id,
                "title": "Notes",
                "icon": "book",
                "color": "",
                "order": 0,
                "sections": [
                    {
                        "id": default_sec_id,
                        "title": "General",
                        "order": 0
                    }
                ]
            }
        ],
        "notes": []
    }
    write_atomic(index_file, json.dumps(initial_index, indent=2))
    return initial_index


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temp_path = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp_path, path)
    except Exception:
        try:
            os.unlink(temp_path)
        except OSError:
            pass
        raise


def import_from_directory_or_zip(takeout_path: Path, store_dir: Path, dry_run: bool = False, target_notebook_id: str = "") -> dict:
    temp_extract_dir = None
    source_dir = takeout_path

    if zipfile.is_zipfile(str(takeout_path)):
        temp_extract_dir = Path(tempfile.mkdtemp(prefix="keep_takeout_"))
        with zipfile.ZipFile(str(takeout_path), "r") as zf:
            zf.extractall(str(temp_extract_dir))
        source_dir = temp_extract_dir

    try:
        # Find all JSON files in takeout directory
        json_files = sorted(source_dir.glob("**/*.json"))
        if not json_files:
            return {
                "ok": False,
                "error": "no_notes_found",
                "message": f"No Keep notes found in '{takeout_path}'."
            }

        index_data = load_or_init_store(store_dir)
        notes_list = index_data.get("notes", [])
        notebooks = index_data.get("notebooks", [])

        # Choose target notebook and section
        nb_id = target_notebook_id
        sec_id = ""
        if not nb_id and notebooks:
            nb_id = notebooks[0].get("id", "")
            if notebooks[0].get("sections"):
                sec_id = notebooks[0]["sections"][0].get("id", "")

        imported_count = 0
        updated_count = 0
        skipped_count = 0
        results = []

        for json_file in json_files:
            try:
                raw_data = json.loads(json_file.read_text(encoding="utf-8"))
            except Exception:
                continue

            # Validate that it is a Keep note JSON (must have createdTimestampUsec or listContent or textContent)
            if not isinstance(raw_data, dict):
                continue
            if "createdTimestampUsec" not in raw_data and "textContent" not in raw_data and "listContent" not in raw_data:
                continue

            parsed = parse_keep_note_json(raw_data, json_file.name)
            keep_id = parsed["keepId"]

            existing_record, existing_doc = find_existing_note_by_keep_id(store_dir, keep_id)

            if existing_record:
                note_id = existing_record["id"]
                updated_count += 1
            else:
                note_id = generate_id("nt")
                imported_count += 1

            doc = convert_keep_to_document(parsed, note_id)

            display_title = parsed["title"]
            if not display_title:
                # Extract first block text as fallback title
                for b in doc["blocks"]:
                    t = (b.get("text") or "").strip()
                    if t:
                        display_title = t.split("\n")[0][:60]
                        break
            if not display_title:
                display_title = "Untitled note"

            # Compute preview snippet
            preview_snippet = ""
            for b in doc["blocks"]:
                if b.get("type") in ("text", "list"):
                    preview_snippet = (b.get("text") or "").strip()[:120]
                    if preview_snippet:
                        break

            note_record = {
                "id": note_id,
                "title": display_title,
                "icon": "checklist" if parsed["listContent"] else "article",
                "notebookId": existing_record.get("notebookId", nb_id) if existing_record else nb_id,
                "sectionId": existing_record.get("sectionId", sec_id) if existing_record else sec_id,
                "tags": parsed["tags"],
                "pinned": parsed["isPinned"],
                "favorite": False,
                "color": parsed["tone"],
                "paper": "",
                "created": parsed["created"],
                "modified": parsed["modified"],
                "preview": preview_snippet,
                "blockCount": len(doc["blocks"]),
                "hasImage": any(b.get("type") == "image" for b in doc["blocks"]),
                "hasInk": False,
                "hasAudio": False,
                "trash": parsed["isTrashed"],
                "archived": parsed["isArchived"]
            }

            results.append({
                "noteId": note_id,
                "title": display_title,
                "keepId": keep_id,
                "status": "updated" if existing_record else "imported"
            })

            if not dry_run:
                # Copy attachments if present
                for att_name in parsed["attachments"]:
                    att_src = json_file.parent / att_name
                    if att_src.exists():
                        dest_asset_dir = store_dir / "assets" / note_id
                        dest_asset_dir.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(str(att_src), str(dest_asset_dir / att_src.name))

                # Write doc file
                doc_path = store_dir / "docs" / f"{note_id}.json"
                write_atomic(doc_path, json.dumps(doc, ensure_ascii=False, indent=2))

                # Update index list
                if existing_record:
                    idx = next((i for i, n in enumerate(notes_list) if n.get("id") == note_id), -1)
                    if idx >= 0:
                        notes_list[idx] = note_record
                    else:
                        notes_list.append(note_record)
                else:
                    notes_list.append(note_record)

        if not dry_run:
            index_data["notes"] = notes_list
            write_atomic(store_dir / "index.json", json.dumps(index_data, ensure_ascii=False, indent=2))

        return {
            "ok": True,
            "imported": imported_count,
            "updated": updated_count,
            "total": len(results),
            "dryRun": dry_run,
            "notes": results
        }

    finally:
        if temp_extract_dir and temp_extract_dir.exists():
            shutil.rmtree(str(temp_extract_dir), ignore_errors=True)


def export_to_takeout_directory(store_dir: Path, output_dir: Path) -> dict:
    """Generate a Google Keep Takeout format directory from the Notes store."""
    output_dir.mkdir(parents=True, exist_ok=True)
    index_file = store_dir / "index.json"
    if not index_file.exists():
        return {"ok": False, "error": "store_not_found"}

    index_data = json.loads(index_file.read_text(encoding="utf-8"))
    notes = index_data.get("notes", [])
    count = 0

    for note in notes:
        note_id = note.get("id", "")
        doc_file = store_dir / "docs" / f"{note_id}.json"
        if not doc_file.exists():
            continue

        doc = json.loads(doc_file.read_text(encoding="utf-8"))
        blocks = doc.get("blocks", [])

        # Construct Keep JSON
        is_list = note.get("icon") == "checklist" or any(b.get("type") == "list" and b.get("style") == "checkbox" for b in blocks)
        text_lines = []
        list_content = []
        attachments = []

        for b in blocks:
            b_type = b.get("type")
            if b_type == "heading":
                pass # Title is already in title field
            elif b_type == "list" and b.get("style") == "checkbox":
                list_content.append({
                    "text": b.get("text", ""),
                    "isChecked": bool(b.get("checked", False))
                })
            elif b_type == "text":
                text_lines.append(b.get("text", ""))
            elif b_type == "image":
                asset_name = b.get("asset", "")
                if asset_name:
                    attachments.append({"filePath": asset_name, "mimetype": "image/png"})
                    # Copy asset to output
                    asset_src = store_dir / "assets" / note_id / asset_name
                    if asset_src.exists():
                        shutil.copy2(str(asset_src), str(output_dir / asset_name))

        safe_title = re.sub(r'[\\/*?:"<>|]', "_", note.get("title") or "Untitled")[:50]
        base_name = f"{safe_title}_{note_id[-6:]}"

        keep_dict = {
            "title": note.get("title", ""),
            "color": "DEFAULT",
            "isArchived": bool(note.get("archived", False)),
            "isPinned": bool(note.get("pinned", False)),
            "isTrashed": bool(note.get("trash", False)),
            "textContent": "\n".join(text_lines) if not is_list else "",
            "listContent": list_content if is_list else [],
            "labels": [{"name": t.lstrip("#")} for t in note.get("tags", [])],
            "createdTimestampUsec": int(note.get("created", time.time() * 1000) * 1000),
            "userEditedTimestampUsec": int(note.get("modified", time.time() * 1000) * 1000),
            "attachments": attachments
        }

        json_out = output_dir / f"{base_name}.json"
        json_out.write_text(json.dumps(keep_dict, ensure_ascii=False, indent=2), encoding="utf-8")
        count += 1

    return {"ok": True, "exported": count, "output": str(output_dir)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Google Keep Takeout Importer for Notes App")
    parser.add_argument("--takeout", type=str, help="Path to Google Takeout archive (.zip) or folder")
    parser.add_argument("--store", type=str, default=os.path.expanduser("~/.local/state/quickshell/user/notes"),
                        help="Path to notes store directory")
    parser.add_argument("--dry-run", action="store_true", help="Preview import actions without writing to disk")
    parser.add_argument("--export-takeout", type=str, help="Export store back to Takeout format directory")
    parser.add_argument("--notebook", type=str, default="", help="Target notebook ID")
    parser.add_argument("--json", action="store_true", help="Output machine-readable JSON on stdout")

    args = parser.parse_args()

    if args.export_takeout:
        store_path = Path(args.store).resolve()
        out_path = Path(args.export_takeout).resolve()
        res = export_to_takeout_directory(store_path, out_path)
        return emit(res)

    if not args.takeout:
        return emit({"ok": False, "error": "missing_argument", "message": "--takeout <path> is required."})

    takeout_path = Path(args.takeout).resolve()
    store_path = Path(args.store).resolve()

    if not takeout_path.exists():
        return emit({"ok": False, "error": "path_not_found", "message": f"There is nothing at '{takeout_path}'."})

    result = import_from_directory_or_zip(takeout_path, store_path, dry_run=args.dry_run, target_notebook_id=args.notebook)
    return emit(result)


if __name__ == "__main__":
    sys.exit(main())
