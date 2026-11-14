#!/usr/bin/env python3
"""Resolve desktop app icon names in the active theme and render 96x96 PNGs.

Called once per batch (up to 32 icon names) by IiLinkService.qml. Prints one
NDJSON line per resolved icon: {"name": "<requested>", "png": "<base64>"}.
Unknown or unrenderable names are skipped silently.
"""

import base64
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys

SIZE = 96
MAX_BATCH = 32
_THEME_CACHE = None


def sanitize(name: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]", "_", name).lstrip(".")
    if not s:
        return ""
    if s != name:
        return f"{s[:80]}_{hashlib.sha256(name.encode('utf-8')).hexdigest()[:8]}"
    return s


def _themes(preferred: str):
    global _THEME_CACHE
    if _THEME_CACHE is not None:
        return _THEME_CACHE
    import gi

    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk

    out = []
    if preferred:
        custom = Gtk.IconTheme.new()
        custom.set_custom_theme(preferred)
        out.append(custom)
    default = Gtk.IconTheme.get_default()
    if default is not None:
        out.append(default)
    _THEME_CACHE = out
    return out


def resolve_icon(name: str, preferred_theme: str) -> str | None:
    if not name:
        return None
    if name.startswith("/"):
        return name if os.path.isfile(name) else None

    candidates = [name]
    stem, ext = os.path.splitext(name)
    if ext.lower() in (".png", ".svg", ".svgz", ".xpm"):
        candidates.append(stem)

    for theme in _themes(preferred_theme):
        for cand in candidates:
            info = theme.lookup_icon(cand, SIZE, 0)
            if info is not None:
                path = info.get_filename()
                if path and os.path.isfile(path):
                    return path

    for pix in ("/usr/share/pixmaps", os.path.expanduser("~/.local/share/pixmaps")):
        for suffix in ("", ".svg", ".png", ".xpm"):
            p = os.path.join(pix, name + suffix)
            if os.path.isfile(p):
                return p
    return None


def is_svg(path: str, head: bytes) -> bool:
    low = path.lower()
    if low.endswith(".svg") or low.endswith(".svgz"):
        return True
    if head.startswith(b"\x1f\x8b"):
        return False
    text = head.lstrip(b"\xef\xbb\xbf").lstrip().lower()
    return b"<svg" in text or (text.startswith(b"<?xml") and b"svg" in text)


def png_size(head: bytes) -> tuple[int, int] | None:
    if len(head) >= 24 and head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
        return struct.unpack(">II", head[16:24])
    return None


def render_to_png(src: str, dest: str, rsvg: str | None, magick: str | None) -> bool:
    try:
        with open(src, "rb") as f:
            head = f.read(2048)
    except OSError:
        return False

    tmp = f"{dest}.tmp.{os.getpid()}"
    try:
        if is_svg(src, head):
            if rsvg:
                res = subprocess.run(
                    [rsvg, "-w", str(SIZE), "-h", str(SIZE), "-a", "-f", "png", "-o", tmp, src],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                if res.returncode == 0 and os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
                    os.replace(tmp, dest)
                    return True
            if magick:
                res = subprocess.run(
                    [magick, "-background", "none", src, "-resize", f"{SIZE}x{SIZE}", tmp],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                if res.returncode == 0 and os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
                    os.replace(tmp, dest)
                    return True
            return False

        dims = png_size(head)
        if dims == (SIZE, SIZE):
            shutil.copyfile(src, tmp)
            os.replace(tmp, dest)
            return True

        if magick:
            res = subprocess.run(
                [magick, src, "-resize", f"{SIZE}x{SIZE}", tmp],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if res.returncode == 0 and os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
                os.replace(tmp, dest)
                return True
        return False
    except OSError:
        return False
    finally:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def main() -> int:
    if len(sys.argv) < 4:
        return 0
    cache_dir = sys.argv[1]
    preferred_theme = sys.argv[2]
    names = sys.argv[3 : 3 + MAX_BATCH]

    os.makedirs(cache_dir, mode=0o700, exist_ok=True)
    rsvg = shutil.which("rsvg-convert")
    magick = shutil.which("magick")

    seen = set()
    for name in names:
        if not name or name in seen:
            continue
        seen.add(name)
        clean = sanitize(name)
        if not clean:
            continue
        dest = os.path.join(cache_dir, f"{clean}.png")
        if not (os.path.isfile(dest) and os.path.getsize(dest) > 0):
            src = resolve_icon(name, preferred_theme)
            if not src or not render_to_png(src, dest, rsvg, magick):
                continue
        try:
            with open(dest, "rb") as f:
                data = f.read()
        except OSError:
            continue
        if not data:
            continue
        b64 = base64.b64encode(data).decode("ascii")
        print(json.dumps({"name": name, "png": b64}), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
