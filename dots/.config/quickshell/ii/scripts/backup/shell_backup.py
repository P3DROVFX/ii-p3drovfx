#!/usr/bin/env python3
"""Back up and restore everything the shell keeps about a user.

Two folders hold every choice a person has made here:

  ~/.config/illogical-impulse   settings, presets, profile pictures, extensions
  ~/.local/state/quickshell     todo, notes, clipboard pins, usage, keybinds…

Neither is reproducible from the repository, and losing them is losing the
desktop rather than the shell. This packs both into one zip and puts them back.

Contract, borrowed from preset_store.py so the QML side needs no parser: every
subcommand prints EXACTLY ONE JSON line on stdout and never raises. Failure is
`{"ok": false, "error": "..."}` with a message meant to be shown to a person.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import platform
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

FORMAT_VERSION = 1
ARCHIVE_PREFIX = "ii-backup"
MANIFEST_NAME = "ii-backup.json"

# Directory names skipped anywhere under a root. Every one of these is either a
# build artifact or something re-fetched from the network on demand:
#   .venv          the Python virtualenv the shell runs its scripts in (~370 MB)
#   preset-store   git clones of installed presets; links.json beside them is
#                  the part that matters and is kept explicitly
#   .git/.cache/__pycache__  the usual
SKIP_DIRS = {".venv", "__pycache__", ".cache", ".git", "node_modules"}
# Archive paths are <root key>/<path relative to that root>, so the root's own
# directory name never appears in them.
SKIP_DIR_PATHS = {("config", "preset-store")}
# Kept even though its parent directory is skipped.
KEEP_FILE_PATHS = {("config", "preset-store", "links.json")}
SKIP_FILE_SUFFIXES = (".pyc", ".tmp", ".swp", ".lock", ".sock")
SKIP_FILE_CONTAINS = (".malformed-",)
# Already-compressed payloads: deflating them costs seconds and saves nothing.
STORE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".mp4", ".mkv",
                  ".webm", ".zip", ".gz", ".xz", ".zst", ".woff2", ".ttf", ".otf"}


def _xdg(var: str, default: str) -> Path:
    value = os.environ.get(var, "").strip()
    return Path(value) if value else Path.home() / default


def roots() -> list[tuple[str, Path]]:
    """The (key, path) pairs that make up a backup, in archive order."""
    return [
        ("config", _xdg("XDG_CONFIG_HOME", ".config") / "illogical-impulse"),
        ("state", _xdg("XDG_STATE_HOME", ".local/state") / "quickshell"),
    ]


def _skipped_dir(parts: tuple[str, ...]) -> bool:
    if parts and parts[-1] in SKIP_DIRS:
        return True
    return parts in SKIP_DIR_PATHS


def _skipped_file(parts: tuple[str, ...]) -> bool:
    if parts in KEEP_FILE_PATHS:
        return False
    name = parts[-1]
    if name.endswith(SKIP_FILE_SUFFIXES):
        return True
    return any(fragment in name for fragment in SKIP_FILE_CONTAINS)


def _walk(key: str, base: Path):
    """Yield (absolute path, archive path) for every file worth keeping."""
    if not base.is_dir():
        return
    for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
        here = Path(dirpath)
        rel_dir = (key,) + here.relative_to(base).parts if here != base else (key,)
        # Prune in place so os.walk never descends into what we skip.
        dirnames[:] = [d for d in sorted(dirnames)
                       if not _skipped_dir(rel_dir + (d,))]
        # A file kept out of an otherwise skipped directory still has to be
        # reachable, so those parents are visited explicitly below.
        for name in sorted(filenames):
            parts = rel_dir + (name,)
            if _skipped_file(parts):
                continue
            path = here / name
            if path.is_symlink() or not path.is_file():
                continue
            yield path, "/".join(parts)


def _kept_orphans(key: str, base: Path):
    """Files under a skipped directory that are kept anyway (links.json)."""
    for parts in KEEP_FILE_PATHS:
        if not parts or parts[0] != key:
            continue
        path = base.joinpath(*parts[1:])
        if path.is_file():
            yield path, "/".join(parts)


def _compression_for(name: str) -> int:
    return (zipfile.ZIP_STORED if Path(name).suffix.lower() in STORE_SUFFIXES
            else zipfile.ZIP_DEFLATED)


def _timestamp() -> str:
    return _dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def _archive_entries():
    """Every (source, arcname) pair the current machine would back up."""
    for key, base in roots():
        yield from _walk(key, base)
        yield from _kept_orphans(key, base)


def create(dest: Path, keep: int, label: str = "") -> dict:
    dest = dest.expanduser()
    dest.mkdir(parents=True, exist_ok=True)
    if not os.access(dest, os.W_OK):
        return {"ok": False, "error": f"Cannot write to {dest}."}

    suffix = f"-{label}" if label else ""
    target = dest / f"{ARCHIVE_PREFIX}-{_timestamp()}{suffix}.zip"
    entries = list(_archive_entries())
    if not entries:
        return {"ok": False,
                "error": "Nothing to back up: neither settings folder exists yet."}

    manifest = {
        "format": FORMAT_VERSION,
        "createdAt": _dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "host": platform.node(),
        "user": os.environ.get("USER", ""),
        "roots": [{"key": key, "path": str(base)} for key, base in roots()],
        "fileCount": len(entries),
        "totalBytes": sum(p.stat().st_size for p, _ in entries if p.exists()),
    }

    # Written beside the target and moved into place, so an interrupted run
    # never leaves a half archive that `list` would offer to restore.
    tmp_fd, tmp_name = tempfile.mkstemp(prefix=".ii-backup-", suffix=".part", dir=dest)
    os.close(tmp_fd)
    tmp_path = Path(tmp_name)
    written = 0
    try:
        with zipfile.ZipFile(tmp_path, "w", zipfile.ZIP_DEFLATED,
                             compresslevel=6) as archive:
            archive.writestr(MANIFEST_NAME, json.dumps(manifest, indent=2))
            for source, arcname in entries:
                try:
                    archive.write(source, arcname,
                                  compress_type=_compression_for(arcname))
                    written += 1
                except (OSError, ValueError):
                    # A file that vanished or cannot be read mid-run is not a
                    # reason to lose the rest of the backup.
                    continue
        tmp_path.replace(target)
    except Exception as error:  # noqa: BLE001 - reported, never raised
        tmp_path.unlink(missing_ok=True)
        return {"ok": False, "error": f"Could not write the backup: {error}"}

    pruned = _prune(dest, keep)
    return {
        "ok": True,
        "path": str(target),
        "name": target.name,
        "sizeBytes": target.stat().st_size,
        "fileCount": written,
        "createdAt": manifest["createdAt"],
        "pruned": pruned,
    }


def _prune(dest: Path, keep: int) -> list[str]:
    if keep is None or keep <= 0:
        return []
    found = sorted(dest.glob(f"{ARCHIVE_PREFIX}-*.zip"),
                   key=lambda p: p.stat().st_mtime, reverse=True)
    removed = []
    for stale in found[keep:]:
        try:
            stale.unlink()
            removed.append(stale.name)
        except OSError:
            continue
    return removed


def _read_manifest(archive_path: Path) -> dict | None:
    try:
        with zipfile.ZipFile(archive_path) as archive:
            with archive.open(MANIFEST_NAME) as handle:
                return json.loads(handle.read().decode("utf-8"))
    except (OSError, KeyError, ValueError, zipfile.BadZipFile):
        return None


def listing(dest: Path) -> dict:
    dest = dest.expanduser()
    if not dest.is_dir():
        return {"ok": True, "backups": []}
    rows = []
    for path in sorted(dest.glob(f"{ARCHIVE_PREFIX}-*.zip"),
                       key=lambda p: p.stat().st_mtime, reverse=True):
        manifest = _read_manifest(path)
        rows.append({
            "path": str(path),
            "name": path.name,
            "sizeBytes": path.stat().st_size,
            "mtime": int(path.stat().st_mtime),
            "valid": manifest is not None,
            "createdAt": (manifest or {}).get("createdAt", ""),
            "fileCount": (manifest or {}).get("fileCount", 0),
            "host": (manifest or {}).get("host", ""),
        })
    return {"ok": True, "backups": rows}


def inspect(archive_path: Path) -> dict:
    archive_path = archive_path.expanduser()
    if not archive_path.is_file():
        return {"ok": False, "error": "That file does not exist."}
    manifest = _read_manifest(archive_path)
    if manifest is None:
        return {"ok": False,
                "error": "This zip was not made by the shell's backup, or it is damaged."}
    if int(manifest.get("format", 0)) > FORMAT_VERSION:
        return {"ok": False,
                "error": "This backup was made by a newer version of the shell."}
    return {"ok": True, "manifest": manifest,
            "sizeBytes": archive_path.stat().st_size}


def restore(archive_path: Path, safety_dest: Path | None) -> dict:
    archive_path = archive_path.expanduser()
    checked = inspect(archive_path)
    if not checked.get("ok"):
        return checked

    # Everything about to be overwritten, kept first. A restore is the one
    # action here that cannot be undone by hand.
    safety = ""
    if safety_dest is not None:
        made = create(safety_dest.expanduser(), 0, label="before-restore")
        if not made.get("ok"):
            return {"ok": False,
                    "error": f"Could not save the current settings first: {made.get('error')}"}
        safety = made["path"]

    bases = {key: base for key, base in roots()}
    restored = 0
    try:
        with zipfile.ZipFile(archive_path) as archive:
            for info in archive.infolist():
                if info.is_dir() or info.filename == MANIFEST_NAME:
                    continue
                parts = Path(info.filename).parts
                base = bases.get(parts[0] if parts else "")
                if base is None or len(parts) < 2:
                    continue
                # Never let an archive name its way out of its own root.
                target = (base / Path(*parts[1:])).resolve()
                if not str(target).startswith(str(base.resolve()) + os.sep):
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(info) as source, open(target, "wb") as sink:
                    shutil.copyfileobj(source, sink)
                restored += 1
    except Exception as error:  # noqa: BLE001 - reported, never raised
        return {"ok": False, "error": f"Could not restore: {error}",
                "safetyBackup": safety}

    return {"ok": True, "restored": restored, "safetyBackup": safety,
            "manifest": checked["manifest"]}


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    sub = parser.add_subparsers(dest="action", required=True)

    make = sub.add_parser("create")
    make.add_argument("--dest", required=True)
    make.add_argument("--keep", type=int, default=0)
    make.add_argument("--label", default="")

    show = sub.add_parser("list")
    show.add_argument("--dest", required=True)

    look = sub.add_parser("inspect")
    look.add_argument("--archive", required=True)

    put = sub.add_parser("restore")
    put.add_argument("--archive", required=True)
    # Without a folder to put it in, the safety copy is skipped: a restore run
    # from the Welcome on a fresh machine has nothing worth keeping anyway.
    put.add_argument("--safety-dest", default="")

    try:
        args = parser.parse_args()
        if args.action == "create":
            result = create(Path(args.dest), args.keep, args.label)
        elif args.action == "list":
            result = listing(Path(args.dest))
        elif args.action == "inspect":
            result = inspect(Path(args.archive))
        else:
            safety = Path(args.safety_dest) if args.safety_dest else None
            result = restore(Path(args.archive), safety)
    except SystemExit:
        raise
    except Exception as error:  # noqa: BLE001 - the contract is one JSON line
        result = {"ok": False, "error": str(error)}

    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
