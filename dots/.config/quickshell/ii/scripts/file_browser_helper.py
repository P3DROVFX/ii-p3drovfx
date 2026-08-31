#!/usr/bin/env python3
"""Small, dependency-free backend for Overview's File Browser panel.

The QML side always invokes this helper with an argv array.  No path is ever
interpolated into a shell command, so spaces, quotes and other filename
characters remain data instead of becoming executable syntax.
"""

from __future__ import annotations

import argparse
import grp
import json
import mimetypes
import os
import pwd
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable


TEXT_EXTENSIONS = {
    ".bash", ".c", ".cc", ".conf", ".cpp", ".css", ".csv", ".fish",
    ".go", ".h", ".hpp", ".html", ".ini", ".java", ".js", ".json",
    ".jsx", ".log", ".lua", ".md", ".qml", ".py", ".rs", ".scss",
    ".sh", ".sql", ".svg", ".toml", ".ts", ".tsx", ".txt", ".xml",
    ".yaml", ".yml", ".zsh",
}


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    raise SystemExit(exit_code)


def normalized_path(value: str) -> str:
    # Paths selected by the browser are filesystem data, not a shell command.
    # Expanding environment variables here silently redirected literal names
    # such as "$HOME" to another file during rename/copy/trash operations.
    # Keep leading-tilde convenience for explicit navigation, but preserve all
    # other characters exactly as they appear on disk.
    return os.path.abspath(os.path.expanduser(value))


def owner_name(uid: int) -> str:
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return str(uid)


def group_name(gid: int) -> str:
    try:
        return grp.getgrgid(gid).gr_name
    except KeyError:
        return str(gid)


def detected_mime(path: str, mode: int) -> str:
    if stat.S_ISDIR(mode):
        return "inode/directory"
    if stat.S_ISLNK(mode):
        return "inode/symlink"
    guessed = mimetypes.guess_type(path, strict=False)[0]
    if guessed:
        return guessed
    if mode & stat.S_IXUSR:
        return "application/x-executable"
    return "application/octet-stream"


def entry_payload(path: str, name: str | None = None) -> dict[str, Any]:
    info = os.lstat(path)
    mode = info.st_mode
    mime = detected_mime(path, mode)
    filename = name if name is not None else os.path.basename(path.rstrip(os.sep)) or os.sep
    # A symlink to a directory remains navigable. Keep the symlink flag for
    # metadata while exposing the target's practical browser capability.
    is_dir = os.path.isdir(path)
    is_link = stat.S_ISLNK(mode)
    suffix = Path(filename).suffix.lower()
    has_birth_time = hasattr(info, "st_birthtime")
    return {
        "name": filename,
        "path": path,
        "parent": os.path.dirname(path.rstrip(os.sep)) or os.sep,
        "isDir": is_dir,
        "isFile": os.path.isfile(path),
        "isSymlink": is_link,
        "target": os.readlink(path) if is_link else "",
        "hidden": filename.startswith(".") and filename not in (".", ".."),
        "extension": suffix[1:] if suffix.startswith(".") else suffix,
        "mime": mime,
        "size": int(info.st_size),
        "modifiedMs": int(info.st_mtime * 1000),
        "createdMs": int(getattr(info, "st_birthtime", info.st_ctime) * 1000),
        "createdIsChangeTime": not has_birth_time,
        "permissions": stat.filemode(mode),
        "mode": format(stat.S_IMODE(mode), "04o"),
        "owner": owner_name(info.st_uid),
        "group": group_name(info.st_gid),
        "readable": os.access(path, os.R_OK),
        "writable": os.access(path, os.W_OK),
        "executable": os.access(path, os.X_OK),
        "isImage": mime.startswith("image/"),
        "isVideo": mime.startswith("video/"),
        "isAudio": mime.startswith("audio/"),
        "isPdf": mime == "application/pdf",
        "isText": mime.startswith("text/") or suffix in TEXT_EXTENSIONS,
    }


def list_directory(args: argparse.Namespace) -> None:
    path = normalized_path(args.path)
    if not os.path.isdir(path):
        emit({"ok": False, "operation": "list", "requestedPath": args.path, "path": path, "error": "Not a readable directory"}, 1)

    entries: list[dict[str, Any]] = []
    skipped = 0
    try:
        with os.scandir(path) as iterator:
            for item in iterator:
                if not args.hidden and item.name.startswith("."):
                    continue
                if len(entries) >= args.limit:
                    skipped = 1
                    break
                try:
                    entries.append(entry_payload(item.path, item.name))
                except OSError:
                    skipped += 1
    except OSError as error:
        emit({"ok": False, "operation": "list", "requestedPath": args.path, "path": path, "error": str(error)}, 1)

    key_functions = {
        "name": lambda item: str(item["name"]).casefold(),
        "size": lambda item: int(item["size"]),
        "modified": lambda item: int(item["modifiedMs"]),
        "type": lambda item: (str(item["mime"]), str(item["name"]).casefold()),
    }
    key = key_functions.get(args.sort, key_functions["name"])
    entries.sort(key=key, reverse=args.descending)
    if args.directories_first:
        entries.sort(key=lambda item: 0 if item["isDir"] else 1)

    emit({
        "ok": True,
        "operation": "list",
        "requestedPath": args.path,
        "path": path,
        "parent": os.path.dirname(path.rstrip(os.sep)) or os.sep,
        "entries": entries,
        "truncated": skipped > 0,
        "skipped": skipped,
    })


def looks_binary(data: bytes) -> bool:
    if not data:
        return False
    if b"\0" in data:
        return True
    sample = data[:4096]
    suspicious = sum(byte < 9 or (13 < byte < 32) for byte in sample)
    return suspicious / len(sample) > 0.08


def inspect_path(args: argparse.Namespace) -> None:
    path = normalized_path(args.path)
    try:
        payload = entry_payload(path)
    except OSError as error:
        emit({"ok": False, "operation": "inspect", "requestedPath": args.path, "path": path, "error": str(error)}, 1)

    if not payload["isDir"]:
        try:
            result = subprocess.run(
                ["file", "--brief", "--mime-type", "--", path],
                capture_output=True,
                text=True,
                check=False,
            )
            inspected_mime = result.stdout.strip()
            if result.returncode == 0 and "/" in inspected_mime:
                payload["mime"] = inspected_mime
                payload["isImage"] = inspected_mime.startswith("image/")
                payload["isVideo"] = inspected_mime.startswith("video/")
                payload["isAudio"] = inspected_mime.startswith("audio/")
                payload["isPdf"] = inspected_mime == "application/pdf"
                payload["isText"] = inspected_mime.startswith("text/") or Path(path).suffix.lower() in TEXT_EXTENSIONS
        except OSError:
            pass

    payload["childCount"] = -1
    payload["childCountTruncated"] = False
    payload["previewText"] = ""
    payload["previewTruncated"] = False
    payload["previewKind"] = "folder" if payload["isDir"] else "icon"

    if payload["isDir"]:
        count = 0
        try:
            with os.scandir(path) as iterator:
                for _ in iterator:
                    count += 1
                    if count >= args.child_limit:
                        payload["childCountTruncated"] = True
                        break
            payload["childCount"] = count
        except OSError:
            pass
    elif payload["isImage"]:
        payload["previewKind"] = "image"
    elif payload["isVideo"]:
        payload["previewKind"] = "video"
    elif payload["isPdf"]:
        payload["previewKind"] = "pdf"
    elif payload["isAudio"]:
        payload["previewKind"] = "audio"
    elif payload["isText"] and payload["readable"]:
        try:
            with open(path, "rb") as handle:
                data = handle.read(args.max_bytes + 1)
            if not looks_binary(data):
                payload["previewKind"] = "text"
                payload["previewTruncated"] = len(data) > args.max_bytes
                payload["previewText"] = data[: args.max_bytes].decode("utf-8", errors="replace")
        except OSError:
            pass

    emit({"ok": True, "operation": "inspect", "requestedPath": args.path, "path": path, "entry": payload})


def validate_name(value: str) -> str:
    name = value.strip()
    if not name or name in (".", "..") or os.sep in name or (os.altsep and os.altsep in name):
        raise ValueError("Enter a single valid file name")
    return name


def available_destination(directory: str, name: str) -> str:
    candidate = os.path.join(directory, name)
    if not os.path.lexists(candidate):
        return candidate
    stem, suffix = os.path.splitext(name)
    index = 2
    while True:
        candidate = os.path.join(directory, f"{stem} copy {index}{suffix}")
        if not os.path.lexists(candidate):
            return candidate
        index += 1


def copy_one(source: str, destination_directory: str) -> str:
    target = available_destination(destination_directory, os.path.basename(source.rstrip(os.sep)))
    if os.path.isdir(source) and not os.path.islink(source):
        shutil.copytree(source, target, symlinks=True)
    else:
        shutil.copy2(source, target, follow_symlinks=False)
    return target


def destination_inside_source(source: str, destination: str) -> bool:
    if not os.path.isdir(source) or os.path.islink(source):
        return False
    source_real = os.path.realpath(source)
    destination_real = os.path.realpath(destination)
    try:
        return os.path.commonpath([source_real, destination_real]) == source_real
    except ValueError:
        return False


def parsed_paths(raw: str) -> list[str]:
    value = json.loads(raw or "[]")
    if not isinstance(value, list):
        raise ValueError("Invalid file selection")
    return [normalized_path(str(path)) for path in value if str(path)]


def operate(args: argparse.Namespace) -> None:
    operation = args.action
    affected: list[str] = []
    try:
        if operation in ("create-file", "create-directory"):
            directory = normalized_path(args.destination)
            name = validate_name(args.name)
            target = os.path.join(directory, name)
            if os.path.lexists(target):
                raise FileExistsError(f"{name} already exists")
            if operation == "create-directory":
                os.mkdir(target)
            else:
                Path(target).touch(exist_ok=False)
            affected.append(target)
        elif operation == "rename":
            source = normalized_path(args.path)
            target = os.path.join(os.path.dirname(source), validate_name(args.name))
            if os.path.lexists(target) and target != source:
                raise FileExistsError(f"{os.path.basename(target)} already exists")
            os.rename(source, target)
            affected.append(target)
        elif operation == "duplicate":
            source = normalized_path(args.path)
            affected.append(copy_one(source, os.path.dirname(source)))
        elif operation in ("copy", "move"):
            destination = normalized_path(args.destination)
            if not os.path.isdir(destination):
                raise NotADirectoryError(destination)
            for source in parsed_paths(args.paths_json):
                if destination_inside_source(source, destination):
                    raise ValueError("A directory cannot be copied or moved inside itself")
                if operation == "copy":
                    affected.append(copy_one(source, destination))
                else:
                    if os.path.dirname(source.rstrip(os.sep)) == destination:
                        affected.append(source)
                        continue
                    target = available_destination(destination, os.path.basename(source.rstrip(os.sep)))
                    affected.append(shutil.move(source, target))
        elif operation == "trash":
            paths = parsed_paths(args.paths_json)
            if not paths:
                raise ValueError("Nothing selected")
            locations = [Path(path).as_uri() for path in paths]
            result = subprocess.run(["gio", "trash", *locations], capture_output=True, text=True, check=False)
            if result.returncode != 0:
                raise OSError(result.stderr.strip() or "Could not move the selection to Trash")
            affected.extend(paths)
        else:
            raise ValueError(f"Unknown operation: {operation}")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        emit({"ok": False, "operation": operation, "error": str(error), "affected": affected}, 1)

    emit({"ok": True, "operation": operation, "affected": affected})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    listing = subparsers.add_parser("list")
    listing.add_argument("path")
    listing.add_argument("--hidden", action="store_true")
    listing.add_argument("--sort", choices=("name", "size", "modified", "type"), default="name")
    listing.add_argument("--descending", action="store_true")
    listing.add_argument("--directories-first", action=argparse.BooleanOptionalAction, default=True)
    listing.add_argument("--limit", type=int, default=5000)
    listing.set_defaults(handler=list_directory)

    inspection = subparsers.add_parser("inspect")
    inspection.add_argument("path")
    inspection.add_argument("--max-bytes", type=int, default=131072)
    inspection.add_argument("--child-limit", type=int, default=10000)
    inspection.set_defaults(handler=inspect_path)

    operation = subparsers.add_parser("operate")
    operation.add_argument("action", choices=("create-file", "create-directory", "rename", "duplicate", "copy", "move", "trash"))
    operation.add_argument("--path", default="")
    operation.add_argument("--destination", default="")
    operation.add_argument("--name", default="")
    operation.add_argument("--paths-json", default="[]")
    operation.set_defaults(handler=operate)
    return parser


def main(argv: Iterable[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    args.handler(args)


if __name__ == "__main__":
    main()
