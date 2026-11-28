#!/usr/bin/env python3
"""
Fast, zero-daemon media scanner & thumbnail helper for the standalone ii Gallery app.

Commands:
  scan --folders-json '<json>' [--include-sub 1] [--show-videos 1]
  thumb --path <video_path> [--out-dir <dir>]
  trash --path <file_path>
  pick-folder [--title <title>]
"""

import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
from pathlib import Path

IMAGE_EXTS = {
    ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif", ".heic", ".heif", ".jfif"
}
VIDEO_EXTS = {
    ".mp4", ".mkv", ".webm", ".mov", ".avi", ".m4v", ".3gp", ".ogv", ".ts", ".flv", ".wmv"
}
SKIP_DIRS = {
    ".git", ".cache", "node_modules", "__pycache__", ".Trash", ".local", ".thumbnails",
    ".venv", "venv", "target", "dist", "build", ".next", ".nuxt", "site-packages",
    ".gradle", "android", "ios", "vendor"
}
REPO_OR_THEME_MARKERS = {
    ".git", ".nomedia", "index.theme", "package.json", "Cargo.toml",
    "go.mod", "pyproject.toml", "CMakeLists.txt", "meson.build"
}


def expand_path(p: str) -> str:
    return os.path.abspath(os.path.expanduser(p))


def quick_image_size(path: str, ext: str):
    """Fast header-only dimension reader for JPEG, PNG, GIF, WEBP (avoids PIL/ffprobe overhead)."""
    try:
        with open(path, "rb") as f:
            head = f.read(32)
            if len(head) < 16:
                return 0, 0
            # PNG
            if head[:8] == b"\x89PNG\r\n\x1a\n" and len(head) >= 24:
                w, h = struct.unpack(">II", head[16:24])
                return int(w), int(h)
            # GIF
            if head[:6] in (b"GIF87a", b"GIF89a"):
                w, h = struct.unpack("<HH", head[6:10])
                return int(w), int(h)
            # WEBP
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                chunk = head[12:16]
                if chunk == b"VP8X" and len(head) >= 30:
                    w = 1 + int.from_bytes(head[24:27], "little")
                    h = 1 + int.from_bytes(head[27:30], "little")
                    return w, h
                if chunk == b"VP8 " and len(head) >= 30:
                    w, h = struct.unpack("<HH", head[26:30])
                    return w & 0x3FFF, h & 0x3FFF
                if chunk == b"VP8L" and len(head) >= 25:
                    b0, b1, b2, b3 = head[21:25]
                    w = 1 + (((b1 & 0x3F) << 8) | b0)
                    h = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6))
                    return w, h
            # JPEG
            if head[:2] == b"\xff\xd8":
                f.seek(2)
                while True:
                    marker_prefix = f.read(1)
                    if not marker_prefix:
                        break
                    if marker_prefix != b"\xff":
                        continue
                    marker = f.read(1)
                    while marker == b"\xff":
                        marker = f.read(1)
                    if not marker:
                        break
                    m = marker[0]
                    if m in (0xD8, 0xD9, 0x01) or (0xD0 <= m <= 0xD7):
                        continue
                    length_bytes = f.read(2)
                    if len(length_bytes) < 2:
                        break
                    length = struct.unpack(">H", length_bytes)[0]
                    if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                        data = f.read(5)
                        if len(data) == 5:
                            h, w = struct.unpack(">HH", data[1:5])
                            return int(w), int(h)
                        break
                    if length < 2:
                        break
                    f.seek(length - 2, os.SEEK_CUR)
    except OSError:
        pass
    return 0, 0


def video_thumb_path(path: str, mtime: float, cache_dir: str) -> str:
    key = hashlib.sha1(f"{path}:{int(mtime)}".encode("utf-8", "ignore")).hexdigest()
    return os.path.join(cache_dir, f"{key}.jpg")


def cmd_scan(args):
    try:
        folders = json.loads(args.folders_json)
    except Exception as e:
        print(json.dumps({"error": f"invalid folders json: {e}", "items": [], "albums": []}))
        return 1

    cache_dir = os.path.join(
        os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
        "quickshell", "gallery_thumbs"
    )
    os.makedirs(cache_dir, exist_ok=True)

    show_videos = bool(args.show_videos)
    items = []
    seen_paths = set()
    folder_stats = {}

    for fobj in folders:
        raw_path = str(fobj.get("path", "")).strip()
        if not raw_path:
            continue
        root_name = str(fobj.get("name", "")).strip() or os.path.basename(raw_path.rstrip("/")) or raw_path
        abs_root = expand_path(raw_path)
        folder_stats[root_name] = {
            "name": root_name,
            "path": raw_path,
            "absPath": abs_root,
            "exists": os.path.isdir(abs_root),
            "count": 0,
        }
        if not os.path.isdir(abs_root):
            continue

        # Fast os.scandir traversal (avoids opening thousands of files for image headers)
        stack = [abs_root]
        while stack:
            dirpath = stack.pop()
            if dirpath != abs_root:
                marker_hit = any(
                    os.path.exists(os.path.join(dirpath, m))
                    for m in REPO_OR_THEME_MARKERS
                )
                if marker_hit:
                    continue

            rel_dir = os.path.relpath(dirpath, abs_root)
            rel_folder = root_name if rel_dir == "." else f"{root_name}/{rel_dir.replace(os.sep, '/')}"
            is_sub = rel_dir != "."

            try:
                with os.scandir(dirpath) as it:
                    for entry in it:
                        name = entry.name
                        if name.startswith("."):
                            continue
                        try:
                            if entry.is_dir(follow_symlinks=False):
                                if name not in SKIP_DIRS:
                                    stack.append(entry.path)
                                continue
                            if not entry.is_file(follow_symlinks=False):
                                continue
                        except OSError:
                            continue

                        dot = name.rfind(".")
                        if dot <= 0:
                            continue
                        ext = name[dot:].lower()
                        is_img = ext in IMAGE_EXTS
                        is_vid = ext in VIDEO_EXTS
                        if not is_img and not (is_vid and show_videos):
                            continue

                        full_path = entry.path
                        if full_path in seen_paths:
                            continue
                        try:
                            st = entry.stat(follow_symlinks=False)
                        except OSError:
                            continue
                        if st.st_size <= 0:
                            continue
                        seen_paths.add(full_path)

                        mtime_ms = int(st.st_mtime * 1000)
                        thumb = ""
                        if is_vid:
                            tp = video_thumb_path(full_path, st.st_mtime, cache_dir)
                            if os.path.isfile(tp):
                                thumb = tp

                        stem = name[:dot]
                        title = stem.replace("_", " ").replace("-", " ").strip() or name

                        items.append({
                            "id": full_path,
                            "path": full_path,
                            "file": name,
                            "title": title,
                            "ext": ext.lstrip(".").upper(),
                            "type": "video" if is_vid else "photo",
                            "root": root_name,
                            "folder": rel_folder,
                            "isSub": is_sub,
                            "mtime": mtime_ms,
                            "size": int(st.st_size),
                            "w": 0,
                            "h": 0,
                            "dur": 0,
                            "thumb": thumb,
                        })
                        folder_stats[root_name]["count"] += 1
            except OSError:
                continue

    # Sort newest first and cap to keep QML JS heap lean
    items.sort(key=lambda x: x["mtime"], reverse=True)
    if args.max_items > 0 and len(items) > args.max_items:
        items = items[:args.max_items]

    print(json.dumps({
        "items": items,
        "folderCounts": {k: v["count"] for k, v in folder_stats.items()},
        "cacheDir": cache_dir,
    }, ensure_ascii=False))
    return 0


def cmd_thumb(args):
    path = expand_path(args.path)
    if not os.path.isfile(path):
        print(json.dumps({"ok": False, "error": "not_found"}))
        return 1
    cache_dir = args.out_dir or os.path.join(
        os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
        "quickshell", "gallery_thumbs"
    )
    os.makedirs(cache_dir, exist_ok=True)
    st = os.stat(path)
    out_path = video_thumb_path(path, st.st_mtime, cache_dir)

    dur = 0
    w = 0
    h = 0
    if shutil.which("ffprobe"):
        try:
            probe = subprocess.run(
                [
                    "ffprobe", "-v", "error",
                    "-select_streams", "v:0",
                    "-show_entries", "stream=width,height:format=duration",
                    "-of", "json", path,
                ],
                capture_output=True, text=True, timeout=6
            )
            if probe.returncode == 0 and probe.stdout:
                data = json.loads(probe.stdout)
                streams = data.get("streams") or []
                if streams:
                    w = int(streams[0].get("width") or 0)
                    h = int(streams[0].get("height") or 0)
                fmt = data.get("format") or {}
                if fmt.get("duration"):
                    dur = max(0, int(round(float(fmt["duration"]))))
        except Exception:
            pass

    if not os.path.isfile(out_path) and shutil.which("ffmpeg"):
        seek = "00:00:01" if dur == 0 or dur >= 2 else "00:00:00"
        tmp_path = out_path + ".part.jpg"
        try:
            res = subprocess.run(
                [
                    "ffmpeg", "-y", "-ss", seek, "-i", path,
                    "-vframes", "1", "-vf", "scale=480:-2:force_original_aspect_ratio=decrease",
                    "-q:v", "4", tmp_path,
                ],
                capture_output=True, timeout=10
            )
            if res.returncode == 0 and os.path.isfile(tmp_path) and os.path.getsize(tmp_path) > 0:
                os.replace(tmp_path, out_path)
            elif os.path.isfile(tmp_path):
                os.remove(tmp_path)
        except Exception:
            if os.path.isfile(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass

    print(json.dumps({
        "ok": os.path.isfile(out_path),
        "path": path,
        "thumb": out_path if os.path.isfile(out_path) else "",
        "dur": dur,
        "w": w,
        "h": h,
    }, ensure_ascii=False))
    return 0


def cmd_trash(args):
    path = expand_path(args.path)
    if not os.path.exists(path):
        print(json.dumps({"ok": False, "error": "not_found"}))
        return 1
    if shutil.which("gio"):
        res = subprocess.run(["gio", "trash", path], capture_output=True, text=True)
        if res.returncode == 0:
            print(json.dumps({"ok": True, "path": path}))
            return 0
    if shutil.which("trash-put"):
        res = subprocess.run(["trash-put", path], capture_output=True, text=True)
        if res.returncode == 0:
            print(json.dumps({"ok": True, "path": path}))
            return 0
    print(json.dumps({"ok": False, "error": "trash_failed"}))
    return 1


def cmd_trash_batch(args):
    try:
        paths = [expand_path(p) for p in json.loads(args.paths_json) if p]
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e), "trashed": []}))
        return 1
    existing = [p for p in paths if os.path.exists(p)]
    if not existing:
        print(json.dumps({"ok": False, "error": "none_found", "trashed": []}))
        return 1
    tool = ["gio", "trash"] if shutil.which("gio") else (["trash-put"] if shutil.which("trash-put") else None)
    if not tool:
        print(json.dumps({"ok": False, "error": "no_trash_tool", "trashed": []}))
        return 1
    res = subprocess.run(tool + existing, capture_output=True, text=True)
    trashed = [p for p in existing if not os.path.exists(p)]
    print(json.dumps({"ok": len(trashed) > 0, "trashed": trashed, "code": res.returncode}))
    return 0 if len(trashed) > 0 else 1


def cmd_move_batch(args):
    dest_dir = expand_path(args.dest)
    try:
        paths = [expand_path(p) for p in json.loads(args.paths_json) if p]
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e), "moved": 0}))
        return 1
    os.makedirs(dest_dir, exist_ok=True)
    moved = 0
    for src in paths:
        if not os.path.isfile(src):
            continue
        if os.path.dirname(src) == dest_dir:
            continue
        fname = os.path.basename(src)
        base, ext = os.path.splitext(fname)
        dst = os.path.join(dest_dir, fname)
        n = 1
        while os.path.exists(dst):
            dst = os.path.join(dest_dir, f"{base} ({n}){ext}")
            n += 1
        try:
            shutil.move(src, dst)
            moved += 1
        except OSError:
            pass
    print(json.dumps({"ok": moved > 0, "moved": moved, "dest": dest_dir}))
    return 0 if moved > 0 else 1


def cmd_pick_folder(args):
    title = args.title or "Select folder"
    home = os.path.expanduser("~")
    if shutil.which("kdialog"):
        res = subprocess.run(["kdialog", "--getexistingdirectory", home, "--title", title], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            print(res.stdout.strip())
            return 0
    elif shutil.which("zenity"):
        res = subprocess.run(["zenity", "--file-selection", "--directory", f"--title={title}", f"--filename={home}/"], capture_output=True, text=True)
        if res.returncode == 0 and res.stdout.strip():
            print(res.stdout.strip())
            return 0
    return 1


def main():
    parser = argparse.ArgumentParser(description="ii Gallery helper")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_scan = sub.add_parser("scan")
    p_scan.add_argument("--folders-json", required=True)
    p_scan.add_argument("--show-videos", type=int, default=1)
    p_scan.add_argument("--max-items", type=int, default=3000)

    p_thumb = sub.add_parser("thumb")
    p_thumb.add_argument("--path", required=True)
    p_thumb.add_argument("--out-dir", default="")

    p_trash = sub.add_parser("trash")
    p_trash.add_argument("--path", required=True)

    p_trash_b = sub.add_parser("trash-batch")
    p_trash_b.add_argument("--paths-json", required=True)

    p_move = sub.add_parser("move-batch")
    p_move.add_argument("--paths-json", required=True)
    p_move.add_argument("--dest", required=True)

    p_pick = sub.add_parser("pick-folder")
    p_pick.add_argument("--title", default="Select folder")

    args = parser.parse_args()
    if args.cmd == "scan":
        return cmd_scan(args)
    if args.cmd == "thumb":
        return cmd_thumb(args)
    if args.cmd == "trash":
        return cmd_trash(args)
    if args.cmd == "trash-batch":
        return cmd_trash_batch(args)
    if args.cmd == "move-batch":
        return cmd_move_batch(args)
    if args.cmd == "pick-folder":
        return cmd_pick_folder(args)
    return 1


if __name__ == "__main__":
    sys.exit(main())
