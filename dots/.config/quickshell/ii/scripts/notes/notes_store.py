#!/usr/bin/env python3
"""File operations for the notes store.

The shell owns the *meaning* of a note — the block model, the markdown, the migration
transform all live in `services/notes/*.js` and are checked without a shell running. This
script owns the parts of the store that are awkward or unsafe from QML: creating the
directory tree, committing a batch of files and binary copies as one step, and removing
everything belonging to a note.

Same contract as the other helpers in this project: **one JSON line on stdout, and never
an exception**. The QML side has no parser and no error handling of its own.

  notes_store.py init         <dir>
  notes_store.py commit       <dir>            # batch on stdin
  notes_store.py purge        <dir> <noteId>
  notes_store.py import-asset <dir> <noteId> <src>
"""

import json
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

SUBDIRECTORIES = ("docs", "assets", "revisions")


def emit(payload) -> int:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    return 0


def ensure_tree(root: Path) -> None:
    for name in SUBDIRECTORIES:
        (root / name).mkdir(parents=True, exist_ok=True)


def write_atomic(path: Path, text: str) -> None:
    """Write through a temporary file in the same directory, then rename.

    The index is watched by the shell. A partial read of a file being overwritten in place
    is a store that looks corrupt for as long as the write takes, and the watcher is
    precisely what would read it at that moment.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=str(path.parent), prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as file:
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def inside(root: Path, candidate: Path) -> bool:
    """Whether `candidate` is under `root`.

    Every destination in a batch comes from the shell, but a relative path with `..` in it
    would write outside the store, and this script runs with the user's full rights. The
    check is cheap and the failure it prevents is not recoverable.
    """
    try:
        candidate.resolve().relative_to(root.resolve())
        return True
    except (ValueError, OSError):
        return False


def cmd_init(args) -> int:
    root = Path(args[0]).expanduser()
    existed = (root / "index.json").exists()
    ensure_tree(root)
    return emit({"ok": True, "dir": str(root), "hasIndex": existed})


def cmd_commit(args) -> int:
    """Apply a batch of writes, copies and renames.

    One command rather than several because a migration is all of them at once: the index,
    every document, every sketch copied in, and the legacy file renamed only after the
    rest succeeded. Half a migration is worse than none — it would look complete to the
    next launch, which skips migrating when an index is already there.
    """
    root = Path(args[0]).expanduser()
    ensure_tree(root)

    raw = sys.stdin.read()
    if not raw.strip():
        return emit({"error": "empty batch"})
    batch = json.loads(raw)

    written = []
    for entry in batch.get("files", []):
        target = root / str(entry.get("path", ""))
        if not inside(root, target):
            return emit({"error": f"refusing to write outside the store: {entry.get('path')}"})
        write_atomic(target, json.dumps(entry.get("contents", {}), indent=2, ensure_ascii=False))
        written.append(str(target.relative_to(root)))

    copied = []
    missing = []
    for entry in batch.get("copies", []):
        source = Path(str(entry.get("from", ""))).expanduser()
        target = root / str(entry.get("to", ""))
        if not inside(root, target):
            return emit({"error": f"refusing to copy outside the store: {entry.get('to')}"})
        if not source.is_file():
            # A sketch the old file pointed at that is not on disk. The note still
            # migrates: the block naming a missing picture is recoverable, and dropping
            # the note because its picture went missing is not.
            missing.append(str(source))
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        copied.append(str(target.relative_to(root)))

    renamed = []
    for entry in batch.get("renames", []):
        source = Path(str(entry.get("from", ""))).expanduser()
        target = Path(str(entry.get("to", ""))).expanduser()
        if not source.exists():
            continue
        # Never over an existing file: the destination of a legacy rename is a backup, and
        # a second migration must not overwrite the first one's copy.
        final = target
        suffix = 1
        while final.exists():
            final = target.with_name(f"{target.name}-{suffix}")
            suffix += 1
        target.parent.mkdir(parents=True, exist_ok=True)
        os.replace(source, final)
        renamed.append(str(final))

    return emit({
        "ok": True,
        "written": written,
        "copied": copied,
        "missing": missing,
        "renamed": renamed,
    })


def cmd_purge(args) -> int:
    """Everything belonging to one note, gone.

    The reason assets are filed per note: today a sketch outlives the note that showed it
    forever, because nothing on disk records whose it was.
    """
    root = Path(args[0]).expanduser()
    note_id = str(args[1])
    if "/" in note_id or note_id in ("", ".", ".."):
        return emit({"error": "bad note id"})

    removed = []
    document = root / "docs" / f"{note_id}.json"
    if document.exists():
        document.unlink()
        removed.append(str(document.relative_to(root)))
    for name in ("assets", "revisions"):
        folder = root / name / note_id
        if folder.is_dir():
            shutil.rmtree(folder)
            removed.append(str(folder.relative_to(root)))
    return emit({"ok": True, "removed": removed})


def cmd_import_asset(args) -> int:
    root = Path(args[0]).expanduser()
    note_id = str(args[1])
    source = Path(str(args[2])).expanduser()
    if "/" in note_id or note_id in ("", ".", ".."):
        return emit({"error": "bad note id"})
    if not source.is_file():
        return emit({"error": f"no such file: {source}"})

    folder = root / "assets" / note_id
    folder.mkdir(parents=True, exist_ok=True)
    # A name already taken belongs to another block; overwriting it would silently change
    # a picture somewhere else in the same note.
    name = source.name
    stem, dot, extension = name.partition(".")
    suffix = 1
    while (folder / name).exists():
        name = f"{stem}-{suffix}{dot}{extension}"
        suffix += 1
    shutil.copy2(source, folder / name)
    return emit({"ok": True, "name": name, "path": str(folder / name)})


def cmd_prepare_assets(args) -> int:
    """Create a note's asset folder, and report the absolute path.

    Saving a drawing writes an image straight to a path, so the folder has to exist
    first — and a `mkdir` the caller fired and forgot is a race whose loser is the
    drawing.
    """
    root = Path(args[0]).expanduser()
    note_id = str(args[1])
    if "/" in note_id or note_id in ("", ".", ".."):
        return emit({"error": "bad note id"})
    folder = root / "assets" / note_id
    folder.mkdir(parents=True, exist_ok=True)
    return emit({"ok": True, "path": str(folder)})


def cmd_read_asset(args) -> int:
    """Read one JSON sidecar from a note's asset folder.

    The vector strokes of a drawing live beside the picture rather than inside the note:
    a full page of ink is thousands of points, and the document is read and rewritten
    every time somebody types a character in the same note.
    """
    root = Path(args[0]).expanduser()
    note_id = str(args[1])
    name = str(args[2])
    if "/" in note_id or note_id in ("", ".", "..") or "/" in name or ".." in name:
        return emit({"error": "bad asset name"})
    target = root / "assets" / note_id / name
    if not target.is_file():
        return emit({"ok": True, "missing": True})
    return emit({"ok": True, "contents": json.loads(target.read_text(encoding="utf-8"))})


def cmd_save_revision(args) -> int:
    root = Path(args[0]).expanduser()
    note_id = str(args[1])
    if "/" in note_id or note_id in ("", ".", ".."):
        return emit({"error": "bad note id"})
    try:
        payload = json.loads(sys.stdin.read())
    except Exception as err:
        return emit({"error": f"invalid json: {err}"})
    folder = root / "revisions" / note_id
    folder.mkdir(parents=True, exist_ok=True)
    stamp = int(payload.get("timestamp") or int(time.time() * 1000))
    payload["timestamp"] = stamp
    dest = folder / f"{stamp}.json"
    write_atomic(dest, json.dumps(payload, separators=(",", ":")))
    existing = sorted(folder.glob("*.json"), key=lambda p: p.stat().st_mtime)
    if len(existing) > 50:
        for old in existing[:-50]:
            try:
                old.unlink()
            except OSError:
                pass
    return emit({"ok": True, "timestamp": stamp, "filename": dest.name})


def cmd_list_revisions(args) -> int:
    root = Path(args[0]).expanduser()
    note_id = str(args[1])
    if "/" in note_id or note_id in ("", ".", ".."):
        return emit({"error": "bad note id"})
    folder = root / "revisions" / note_id
    if not folder.is_dir():
        return emit({"ok": True, "revisions": []})
    results = []
    for file in sorted(folder.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True):
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
            results.append({
                "timestamp": data.get("timestamp", int(file.stem) if file.stem.isdigit() else 0),
                "date": data.get("date", ""),
                "title": data.get("title", ""),
                "blockCount": len(data.get("blocks", [])),
                "author": data.get("author", "local")
            })
        except Exception:
            continue
    return emit({"ok": True, "revisions": results})


def cmd_read_revision(args) -> int:
    root = Path(args[0]).expanduser()
    note_id = str(args[1])
    stamp = str(args[2])
    if "/" in note_id or note_id in ("", ".", "..") or "/" in stamp or ".." in stamp:
        return emit({"error": "bad arguments"})
    target = root / "revisions" / note_id / f"{stamp}.json"
    if not target.is_file():
        return emit({"ok": False, "error": "revision not found"})
    try:
        return emit({"ok": True, "revision": json.loads(target.read_text(encoding="utf-8"))})
    except Exception as err:
        return emit({"ok": False, "error": str(err)})


COMMANDS = {
    "prepare-assets": (2, cmd_prepare_assets),
    "read-asset": (3, cmd_read_asset),
    "init": (1, cmd_init),
    "commit": (1, cmd_commit),
    "purge": (2, cmd_purge),
    "import-asset": (3, cmd_import_asset),
    "save-revision": (2, cmd_save_revision),
    "list-revisions": (2, cmd_list_revisions),
    "read-revision": (3, cmd_read_revision),
}


def main() -> int:
    argv = sys.argv[1:]
    if not argv or argv[0] not in COMMANDS:
        return emit({"error": "Unknown notes store command"})
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
