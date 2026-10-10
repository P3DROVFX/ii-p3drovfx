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


APPIMAGE_ICON_CACHE = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "ii" / "desktop-icons"
APPIMAGE_ICON_MAX_BYTES = 4 * 1024 * 1024


def appimage_squashfs_offset(path: Path):
    # A type 2 AppImage is an ELF runtime with the squashfs image appended
    # right after the section header table, the offset `--appimage-offset`
    # prints. Read from the headers so the file is never run.
    with path.open("rb") as f:
        head = f.read(64)
        if len(head) < 64 or head[:4] != b"\x7fELF" or head[8:11] != b"AI\x02":
            return None
        endian = "little" if head[5] == 1 else "big"
        field = lambda start, end: int.from_bytes(head[start:end], endian)
        if head[4] == 2:  # ELF64
            offset = field(0x28, 0x30) + field(0x3A, 0x3C) * field(0x3C, 0x3E)
        else:
            offset = field(0x20, 0x24) + field(0x2E, 0x30) * field(0x30, 0x32)
        f.seek(offset)
        return offset if f.read(4) == b"hsqs" else None


def appimage_icon(path: Path):
    """The icon an AppImage carries (its `.DirIcon`), extracted once into the
    cache. None when it cannot be read: the mime icon stands in."""
    unsquashfs = shutil.which("unsquashfs")
    if not unsquashfs:
        return None
    import hashlib
    import subprocess
    stat = path.stat()
    key = hashlib.sha1(str(path).encode()).hexdigest()
    stamp = f"{key}-{stat.st_mtime_ns}-{stat.st_size}"
    for ext in (".png", ".svg"):
        cached = APPIMAGE_ICON_CACHE / (stamp + ext)
        if cached.is_file():
            return str(cached)
    try:
        offset = appimage_squashfs_offset(path)
        if offset is None:
            return None
        # `-cat` follows .DirIcon's usual symlink to the real icon.
        data = subprocess.run([unsquashfs, "-o", str(offset), "-cat", str(path), ".DirIcon"],
                              capture_output=True, timeout=5, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    if not data or len(data) > APPIMAGE_ICON_MAX_BYTES:
        return None
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        ext = ".png"
    elif b"<svg" in data[:1024]:
        ext = ".svg"
    else:
        return None
    APPIMAGE_ICON_CACHE.mkdir(parents=True, exist_ok=True)
    # The AppImage changed (or moved back): its older extractions go.
    for stale in APPIMAGE_ICON_CACHE.glob(key + "-*"):
        stale.unlink(missing_ok=True)
    target = APPIMAGE_ICON_CACHE / (stamp + ext)
    partial = target.with_name(target.name + ".part")
    partial.write_bytes(data)
    partial.replace(target)
    return str(target)


THUMBNAIL_ROOT = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "thumbnails"
PREVIEW_IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".svg"}
PREVIEW_IMAGE_MAX_BYTES = 16 * 1024 * 1024
PREVIEW_MAX = 4
PREVIEW_SCAN_LIMIT = 2000


def cached_thumbnail(path: Path):
    """The freedesktop thumbnail a file manager already made for `path`
    (Dolphin, Nautilus...), when it is at least as new as the file."""
    import hashlib
    uri = Gio.File.new_for_path(str(path)).get_uri()
    name = hashlib.md5(uri.encode()).hexdigest() + ".png"
    mtime = path.stat().st_mtime
    for size in ("x-large", "large", "normal"):
        thumb = THUMBNAIL_ROOT / size / name
        try:
            if thumb.stat().st_mtime >= mtime:
                return str(thumb)
        except OSError:
            continue
    return None


def folder_previews(path: Path):
    """Up to four images for a folder's icon, like Dolphin's folder
    thumbnails: from its top level, in name order, the files that have a
    picture - a cached thumbnail, a small image, an AppImage's own icon."""
    import itertools
    previews = []
    try:
        with os.scandir(path) as it:
            names = sorted((e.name for e in itertools.islice(it, PREVIEW_SCAN_LIMIT)
                            if not e.name.startswith(".")), key=str.lower)
    except OSError:
        return previews
    for name in names:
        child = path / name
        try:
            if not child.is_file():
                continue
            real = child.resolve()
            picture = cached_thumbnail(real)
            if not picture and real.suffix.lower() in PREVIEW_IMAGE_SUFFIXES \
                    and real.stat().st_size <= PREVIEW_IMAGE_MAX_BYTES:
                picture = str(real)
            if not picture and real.suffix.lower() == ".appimage":
                picture = appimage_icon(real)
        except OSError:
            continue
        if picture:
            previews.append(picture)
            if len(previews) == PREVIEW_MAX:
                break
    return previews


def resolve_path(path: Path):
    # Everything up to the last component is resolved, the last is not: a
    # link on the desktop stays the link, so rename and trash act on it and
    # never on the folder it points to. Type and icon still follow it.
    path = Path(os.path.normpath(path))
    path = path.parent.resolve() / path.name
    if path.is_dir():
        return {
            "id": "directory:" + str(path),
            "type": "directory",
            "path": str(path),
            "name": path.name or str(path),
            "fileName": path.name,
            "icon": "folder",
            "previews": folder_previews(path),
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
    icon = appimage_icon(path) if content_type == "application/vnd.appimage" else None
    return {
        "id": "file:" + str(path),
        "type": "file",
        "path": str(path),
        "name": path.name or str(path),
        "fileName": path.name,
        "icon": icon or icon_string(Gio.content_type_get_icon(content_type), "text-x-generic"),
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
            # A linked launcher keeps its target's Name=: the rename is the link's.
            if dst.is_symlink():
                raise OSError("linked launcher")
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
    if not src.exists() and not src.is_symlink():
        return {"success": True, "path": str(src), "note": "Path already gone"}

    try:
        gfile = Gio.File.new_for_path(str(src))
        gfile.trash(None)
        return {"success": True, "path": str(src), "trashed": True}
    except Exception as e:
        try:
            # A link goes alone: is_dir() follows it, and rmtree must never
            # reach the folder it points to.
            if src.is_symlink():
                src.unlink()
            elif src.is_dir():
                shutil.rmtree(src)
            else:
                src.unlink()
            return {"success": True, "path": str(src), "trashed": False}
        except Exception as del_err:
            return {"success": False, "error": f"{e}; delete fallback: {del_err}"}


def notify(summary: str, body: str = ""):
    notifier = shutil.which("notify-send")
    if notifier:
        import subprocess
        subprocess.run([notifier, "-a", "Desktop", "-i", "folder", summary, body],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5, check=False)


def cmd_copy_to_desktop(desktop_dir: str, json_urls: str, mode: str = "link"):
    """Bring files and folders onto the desktop: "link" (a symlink, what a
    drop and Paste do), "copy" or "move"."""
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

            # Already in the desktop directory (a link there included): only
            # placed. Checked before following links, or dragging a desktop
            # link back onto the desktop would link it a second time.
            lexical = Path(os.path.normpath(src))
            if lexical.parent.resolve() == p and (lexical.exists() or lexical.is_symlink()):
                items.append(resolve_path(lexical))
                continue

            src = src.resolve()
            if not src.exists():
                errors.append(f"{value}: File does not exist")
                continue

            if src.parent == p:
                items.append(resolve_path(src))
                continue

            # A folder that holds the desktop would copy into itself forever.
            if mode != "link" and src.is_dir() and p.is_relative_to(src):
                errors.append(f"{value}: Cannot {mode} a folder into itself")
                continue

            dst = p / src.name
            counter = 2
            while dst.exists() or dst.is_symlink():
                stem = src.stem if src.is_file() else src.name
                suffix = src.suffix if src.is_file() else ""
                dst = p / f"{stem} ({counter}){suffix}"
                counter += 1

            if mode == "link":
                dst.symlink_to(src)
            elif mode == "move":
                # A rename on the same filesystem; a copy and delete across.
                shutil.move(str(src), str(dst))
            elif src.is_dir():
                # Runs in the background with nothing on the desktop until it
                # ends, so a folder copy says when it starts and when it ends.
                notify(f"Copying “{src.name}” to the desktop", str(src))
                try:
                    shutil.copytree(src, dst, symlinks=True)
                except Exception:
                    notify(f"Could not copy “{src.name}” to the desktop", "The partial copy was left in place.")
                    raise
                notify(f"Copied “{src.name}” to the desktop", str(dst))
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
        mode = sys.argv[4] if len(sys.argv) > 4 else "link"
        if mode not in ("copy", "link", "move"):
            print(json.dumps({"items": [], "errors": [f"Unknown mode: {mode}"]}))
            return
        print(json.dumps(cmd_copy_to_desktop(desktop_dir, urls, mode), ensure_ascii=False))
    elif cmd == "resolve":
        urls = sys.argv[2] if len(sys.argv) > 2 else "[]"
        print(json.dumps(cmd_resolve(urls), ensure_ascii=False))
    else:
        # Fallback to legacy array resolution if first argument is a JSON array
        print(json.dumps(cmd_resolve(cmd), ensure_ascii=False))


if __name__ == "__main__":
    main()
