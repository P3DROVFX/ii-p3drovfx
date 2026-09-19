#!/usr/bin/env python3
"""Resolve explicitly dropped local files, folders and desktop entries; never execute them."""
import json
import os
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GioUnix", "2.0")
from gi.repository import Gio, GioUnix


def icon_string(icon, fallback):
    # ThemedIcon.to_string() joins every alias with ":" ("image-x-generic:unknown"),
    # which no icon lookup understands: take the first name. File/URIs pass
    # through whole, and the caller's fallback covers a null icon.
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


def resolve(value):
    uri = urlsplit(value)
    if uri.scheme:
        if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
            raise ValueError("Only local files and folders are supported")
        path = Path(unquote(uri.path))
    else:
        path = Path(value)
    if not path.is_absolute():
        raise ValueError("An absolute path is required")
    path = Path(os.path.normpath(path))
    if path.is_dir():
        return {"id": "directory:" + str(path), "type": "directory", "path": str(path),
                "name": path.name or str(path), "icon": "folder"}
    if not path.is_file():
        raise ValueError("Not a local file or folder")
    if path.suffix != ".desktop":
        # Any other file becomes a plain desktop file icon: the mimetype's own
        # themed icon, the same name a file manager would look up. Opening is
        # xdg-open's job (the default handler), never this resolver's.
        content_type = Gio.content_type_guess(str(path), None)[0]
        return {"id": "file:" + str(path), "type": "file", "path": str(path),
                "name": path.name or str(path),
                "icon": icon_string(Gio.content_type_get_icon(content_type), "text-x-generic")}
    entry = GioUnix.DesktopAppInfo.new_from_filename(str(path))
    if entry is None:
        raise ValueError("Invalid desktop application entry")
    return {"id": "desktop:" + str(path), "type": "app", "path": str(path),
            "name": entry.get_display_name(),
            "icon": icon_string(entry.get_icon(), "application-x-executable")}


def main():
    items, errors, seen = [], [], set()
    for value in json.loads(sys.argv[1]):
        try:
            item = resolve(value)
            if item["id"] not in seen:
                seen.add(item["id"])
                items.append(item)
        except (ValueError, OSError) as error:
            errors.append(f"{value}: {error}")
    print(json.dumps({"items": items, "errors": errors}, ensure_ascii=False))


if __name__ == "__main__":
    main()
