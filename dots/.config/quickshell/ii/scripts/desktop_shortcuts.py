#!/usr/bin/env python3
"""Manage and resolve desktop files, folders and application entries in ~/Desktop."""
import json
import os
from pathlib import Path
import shutil
import sys
from urllib.parse import unquote, urlsplit

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GioUnix", "2.0")
from gi.repository import Gio, GioUnix


def icon_string(icon, fallback):
    if icon is None:
        return fallback
    names = getattr(icon, "get_names", None)
    if callable(names):
        try:
            first = names()[0]
        except (IndexError, TypeError):
            first = None
        if first:
            return first
    text = str(icon)
    return text.split(":")[0] if text else fallback


def resolve_path(path: Path):
    path = path.resolve()
    if path.is_dir():
        return {
            "id": "directory:" + str(path),
            "type": "directory",
            "path": str(path),
            "name": path.name or str(path),
            "fileName": path.name,
            "icon": "folder",
            "modified": int(path.stat().st_mtime * 1000) if path.exists() else 0
        }
    if not path.is_file():
        raise ValueError("Not a local file or directory: " + str(path))
    if path.suffix == ".desktop":
        entry = GioUnix.DesktopAppInfo.new_from_filename(str(path))
        display_name = (entry.get_display_name() if entry else None) or (entry.get_name() if entry else None) or path.stem
        icon = icon_string(entry.get_icon() if entry else None, "application-x-executable")
        return {
            "id": "desktop:" + str(path),
            "type": "app",
            "path": str(path),
            "name": display_name,
            "fileName": path.name,
            "icon": icon,
            "modified": int(path.stat().st_mtime * 1000) if path.exists() else 0
        }
    content_type = Gio.content_type_guess(str(path), None)[0]
    return {
        "id": "file:" + str(path),
        "type": "file",
        "path": str(path),
        "name": path.name or str(path),
        "fileName": path.name,
        "icon": icon_string(Gio.content_type_get_icon(content_type), "text-x-generic"),
        "modified": int(path.stat().st_mtime * 1000) if path.exists() else 0
    }


def resolve_uri_or_path(value):
    uri = urlsplit(value)
    if uri.scheme:
        if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
            raise ValueError("Only local files and folders are supported")
        path = Path(unquote(uri.path))
    else:
        path = Path(value)
    if not path.is_absolute():
        raise ValueError("An absolute path is required")
    return resolve_path(path)


def cmd_scan(desktop_dir: str):
    p = Path(desktop_dir).expanduser().resolve()
    p.mkdir(parents=True, exist_ok=True)
    items = []
    errors = []
    try:
        entries = sorted(p.iterdir(), key=lambda x: x.name.lower())
    except Exception as e:
        return {"items": [], "errors": [str(e)]}

    for entry in entries:
        if entry.name.startswith(".") or entry.name.endswith("~") or entry.name.endswith(".part") or entry.name.endswith(".crdownload"):
            continue
        try:
            items.append(resolve_path(entry))
        except Exception as e:
            errors.append(f"{entry.name}: {e}")
    return {"items": items, "errors": errors}


def cmd_create_folder(desktop_dir: str, name: str = ""):
    p = Path(desktop_dir).expanduser().resolve()
    p.mkdir(parents=True, exist_ok=True)
    base_name = name.strip() or "New Folder"
    target = p / base_name
    counter = 2
    while target.exists():
        target = p / f"{base_name} ({counter})"
        counter += 1
    target.mkdir(parents=True, exist_ok=True)
    return {"success": True, "item": resolve_path(target)}


def cmd_create_file(desktop_dir: str, name: str = ""):
    p = Path(desktop_dir).expanduser().resolve()
    p.mkdir(parents=True, exist_ok=True)
    base_name = name.strip() or "New Document.txt"
    stem = Path(base_name).stem
    suffix = Path(base_name).suffix or ".txt"
    target = p / f"{stem}{suffix}"
    counter = 2
    while target.exists():
        target = p / f"{stem} ({counter}){suffix}"
        counter += 1
    target.touch()
    return {"success": True, "item": resolve_path(target)}


def cmd_create_app(desktop_dir: str, app_id_or_path: str):
    p = Path(desktop_dir).expanduser().resolve()
    p.mkdir(parents=True, exist_ok=True)
    src_path = Path(app_id_or_path).expanduser()

    if src_path.exists() and src_path.is_file() and src_path.suffix == ".desktop":
        target = p / src_path.name
        counter = 2
        while target.exists():
            target = p / f"{src_path.stem} ({counter}).desktop"
            counter += 1
        shutil.copy2(src_path, target)
        try:
            target.chmod(0o755)
        except Exception:
            pass
        return {"success": True, "item": resolve_path(target)}

    app_id = app_id_or_path.strip()
    app_id_with_ext = app_id if app_id.endswith(".desktop") else (app_id + ".desktop")

    found_file = None
    try:
        entry = GioUnix.DesktopAppInfo.new(app_id_with_ext) or GioUnix.DesktopAppInfo.new(app_id)
        if entry and entry.get_filename():
            cand = Path(entry.get_filename())
            if cand.exists():
                found_file = cand
    except Exception:
        pass

    if not found_file:
        for search_dir in [
            Path.home() / ".local/share/applications",
            Path("/usr/local/share/applications"),
            Path("/usr/share/applications"),
            Path("/var/lib/flatpak/exports/share/applications"),
            Path.home() / ".local/share/flatpak/exports/share/applications"
        ]:
            cand = search_dir / app_id_with_ext
            if cand.exists():
                found_file = cand
                break

    if found_file and found_file.exists():
        target = p / found_file.name
        counter = 2
        while target.exists():
            target = p / f"{found_file.stem} ({counter}).desktop"
            counter += 1
        shutil.copy2(found_file, target)
        try:
            target.chmod(0o755)
        except Exception:
            pass
        return {"success": True, "item": resolve_path(target)}

    # Fallback: synthesize a .desktop launcher
    clean_name = app_id.replace(".desktop", "").replace("-", " ").title()
    target = p / app_id_with_ext
    counter = 2
    while target.exists():
        target = p / f"{app_id.replace('.desktop', '')} ({counter}).desktop"
        counter += 1
    content = f"""[Desktop Entry]
Type=Application
Name={clean_name}
Exec={app_id.replace('.desktop', '')}
Icon=application-x-executable
Terminal=false
"""
    target.write_text(content, encoding="utf-8")
    try:
        target.chmod(0o755)
    except Exception:
        pass
    return {"success": True, "item": resolve_path(target)}


def cmd_rename(desktop_dir: str, item_id_or_path: str, new_name: str):
    p = Path(desktop_dir).expanduser().resolve()
    raw = item_id_or_path
    for prefix in ("directory:", "file:", "desktop:"):
        if raw.startswith(prefix):
            raw = raw[len(prefix):]
            break

    src = Path(raw)
    if not src.is_absolute():
        src = p / src
    if not src.exists():
        src = p / Path(raw).name

    if not src.exists():
        return {"success": False, "error": f"Path not found: {raw}"}

    new_name_clean = new_name.strip()
    if not new_name_clean:
        return {"success": False, "error": "New name cannot be empty"}

    if src.suffix == ".desktop":
        target_name = new_name_clean if new_name_clean.endswith(".desktop") else (new_name_clean + ".desktop")
        dst = src.parent / target_name
        if dst != src:
            os.rename(src, dst)
        try:
            display_name = new_name_clean[:-8] if new_name_clean.endswith(".desktop") else new_name_clean
            lines = dst.read_text(encoding="utf-8").splitlines()
            updated = False
            new_lines = []
            for line in lines:
                if line.startswith("Name=") and not updated:
                    new_lines.append(f"Name={display_name}")
                    updated = True
                else:
                    new_lines.append(line)
            if updated:
                dst.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
        except Exception:
            pass
        return {"success": True, "oldPath": str(src), "newPath": str(dst), "item": resolve_path(dst)}
    else:
        dst = src.parent / new_name_clean
        os.rename(src, dst)
        return {"success": True, "oldPath": str(src), "newPath": str(dst), "item": resolve_path(dst)}


def cmd_trash(item_id_or_path: str):
    raw = item_id_or_path
    for prefix in ("directory:", "file:", "desktop:"):
        if raw.startswith(prefix):
            raw = raw[len(prefix):]
            break

    src = Path(raw)
    if not src.exists():
        return {"success": True, "path": str(src), "note": "Path already gone"}

    try:
        gfile = Gio.File.new_for_path(str(src))
        gfile.trash(None)
        return {"success": True, "path": str(src), "trashed": True}
    except Exception as e:
        try:
            if src.is_dir():
                shutil.rmtree(src)
            else:
                src.unlink()
            return {"success": True, "path": str(src), "trashed": False}
        except Exception as del_err:
            return {"success": False, "error": f"{e}; delete fallback: {del_err}"}


def cmd_copy_to_desktop(desktop_dir: str, json_urls: str):
    p = Path(desktop_dir).expanduser().resolve()
    p.mkdir(parents=True, exist_ok=True)
    try:
        urls = json.loads(json_urls)
    except Exception as e:
        return {"items": [], "errors": [f"Invalid JSON: {e}"]}

    items = []
    errors = []
    for value in urls:
        try:
            uri = urlsplit(value)
            if uri.scheme:
                if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
                    errors.append(f"{value}: Only local files supported")
                    continue
                src = Path(unquote(uri.path))
            else:
                src = Path(value)

            src = src.resolve()
            if not src.exists():
                errors.append(f"{value}: File does not exist")
                continue

            # If source is already in desktop directory, just resolve it
            if src.parent == p:
                items.append(resolve_path(src))
                continue

            dst = p / src.name
            counter = 2
            while dst.exists():
                stem = src.stem if src.is_file() else src.name
                suffix = src.suffix if src.is_file() else ""
                dst = p / f"{stem} ({counter}){suffix}"
                counter += 1

            if src.is_dir():
                shutil.copytree(src, dst)
            else:
                shutil.copy2(src, dst)
                if dst.suffix == ".desktop":
                    try:
                        dst.chmod(0o755)
                    except Exception:
                        pass
            items.append(resolve_path(dst))
        except Exception as e:
            errors.append(f"{value}: {e}")

    return {"items": items, "errors": errors}


def cmd_resolve(json_urls: str):
    items, errors, seen = [], [], set()
    try:
        urls = json.loads(json_urls)
    except Exception as e:
        return {"items": [], "errors": [f"Invalid JSON: {e}"]}

    for value in urls:
        try:
            item = resolve_uri_or_path(value)
            if item["id"] not in seen:
                seen.add(item["id"])
                items.append(item)
        except (ValueError, OSError) as error:
            errors.append(f"{value}: {error}")
    return {"items": items, "errors": errors}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No arguments provided"}))
        sys.exit(1)

    cmd = sys.argv[1]
    if cmd == "scan":
        desktop_dir = sys.argv[2] if len(sys.argv) > 2 else "~/Desktop"
        print(json.dumps(cmd_scan(desktop_dir), ensure_ascii=False))
    elif cmd == "create-folder":
        desktop_dir = sys.argv[2] if len(sys.argv) > 2 else "~/Desktop"
        name = sys.argv[3] if len(sys.argv) > 3 else ""
        print(json.dumps(cmd_create_folder(desktop_dir, name), ensure_ascii=False))
    elif cmd == "create-file":
        desktop_dir = sys.argv[2] if len(sys.argv) > 2 else "~/Desktop"
        name = sys.argv[3] if len(sys.argv) > 3 else ""
        print(json.dumps(cmd_create_file(desktop_dir, name), ensure_ascii=False))
    elif cmd == "create-app":
        desktop_dir = sys.argv[2] if len(sys.argv) > 2 else "~/Desktop"
        app = sys.argv[3] if len(sys.argv) > 3 else ""
        print(json.dumps(cmd_create_app(desktop_dir, app), ensure_ascii=False))
    elif cmd == "rename":
        desktop_dir = sys.argv[2] if len(sys.argv) > 2 else "~/Desktop"
        item = sys.argv[3] if len(sys.argv) > 3 else ""
        new_name = sys.argv[4] if len(sys.argv) > 4 else ""
        print(json.dumps(cmd_rename(desktop_dir, item, new_name), ensure_ascii=False))
    elif cmd == "trash":
        item = sys.argv[2] if len(sys.argv) > 2 else ""
        print(json.dumps(cmd_trash(item), ensure_ascii=False))
    elif cmd == "copy-to-desktop":
        desktop_dir = sys.argv[2] if len(sys.argv) > 2 else "~/Desktop"
        urls = sys.argv[3] if len(sys.argv) > 3 else "[]"
        print(json.dumps(cmd_copy_to_desktop(desktop_dir, urls), ensure_ascii=False))
    elif cmd == "resolve":
        urls = sys.argv[2] if len(sys.argv) > 2 else "[]"
        print(json.dumps(cmd_resolve(urls), ensure_ascii=False))
    else:
        # Fallback to legacy array resolution if first argument is a JSON array
        print(json.dumps(cmd_resolve(cmd), ensure_ascii=False))


if __name__ == "__main__":
    main()
