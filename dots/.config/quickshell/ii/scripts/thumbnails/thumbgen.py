#!/usr/bin/env python3
"""
Freedesktop thumbnails for one directory, made the way ThumbnailImage.qml looks
them up: $XDG_CACHE_HOME/thumbnails/<size>/<md5 of the file:// URI>.png, with the
URI percent-encoded per path segment like JavaScript's encodeURIComponent.

Cheap by construction, because folders can hold thousands of wallpapers:
- one process; images are decoded in-process with Pillow (JPEG decodes at a
  reduced scale), so nothing is spawned per image;
- a small thread pool, bounded by --workers, running at low CPU/IO priority;
- a thumbnail newer than its source is skipped with a single stat;
- only files that were actually (re)generated are reported, as
  "PROGRESS <done>/<total> FILE <path>", so the shell reloads just those;
- writes go to a temp file and are renamed into place, so a card never loads
  a half-written PNG.
Formats Pillow can't open fall back to ImageMagick; videos and GIFs use ffmpeg.
Helpers die with this process (PR_SET_PDEATHSIG) when the shell cancels a run.
"""

import argparse
import ctypes
import hashlib
import os
import shutil
import signal
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import quote

SIZES = {"normal": 128, "large": 256, "x-large": 512, "xx-large": 1024}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".svg", ".bmp", ".avif", ".jxl", ".heic"}
VIDEO_EXTS = {".gif", ".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".ogv"}
# Characters encodeURIComponent leaves alone.
URI_SAFE = "-_.!~*'()"


class DecodeBudget:
    """Caps the estimated memory of the decodes in flight, whatever --workers is."""

    def __init__(self, limit: int):
        self.limit = limit
        self.used = 0
        self.cond = threading.Condition()

    def acquire(self, cost: int) -> int:
        cost = min(cost, self.limit)  # one oversized image may still run, alone
        with self.cond:
            self.cond.wait_for(lambda: self.used + cost <= self.limit)
            self.used += cost
        return cost

    def release(self, cost: int) -> None:
        with self.cond:
            self.used -= cost
            self.cond.notify_all()


_budget = DecodeBudget(320 * 1024 * 1024)
# Temp files being written, removed if the shell cancels the run mid-write.
_in_flight = set()


def _on_sigterm(signum, frame):
    for tmp in list(_in_flight):
        try:
            os.unlink(tmp)
        except OSError:
            pass
    os._exit(143)
# EXIF orientation -> Image.Transpose value (FLIP_LEFT_RIGHT=0 … TRANSVERSE=6).
EXIF_TRANSPOSE = {2: 0, 3: 3, 4: 1, 5: 5, 6: 4, 7: 6, 8: 2}

_libc = None
try:
    _libc = ctypes.CDLL("libc.so.6", use_errno=True)
except OSError:
    pass


def _die_with_parent():
    if _libc is not None:
        _libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG


def file_uri(path: str) -> str:
    return "file://" + "/".join(quote(part, safe=URI_SAFE) for part in path.split("/"))


def thumbnail_path(cache_dir: str, path: str) -> str:
    return os.path.join(cache_dir, hashlib.md5(file_uri(path).encode()).hexdigest() + ".png")


def run_helper(cmd) -> bool:
    try:
        return subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, preexec_fn=_die_with_parent,
                              timeout=60).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def make_with_pillow(src: str, tmp: str, size: int, uri: str, mtime: int) -> bool:
    try:
        from PIL import Image, PngImagePlugin
    except ImportError:
        return False
    try:
        with Image.open(src) as img:
            img.draft("RGB", (size, size))  # JPEG: decode at 1/2..1/8 scale
            orientation = img.getexif().get(0x0112, 1)
            # A decode peaks at about twice its pixel buffer. Drafted (baseline)
            # JPEGs decode small; PNGs and progressive JPEGs decode at full size
            # (an 8K RGBA PNG is ~140 MB), so those wait for room in the budget.
            # (After draft, a JPEG's size is already the reduced one.)
            cost = img.width * img.height * len(img.getbands()) * 2
            if img.format == "JPEG" and img.info.get("progressive"):
                cost *= img.decoderconfig[0] ** 2 if img.decoderconfig else 1
            cost = _budget.acquire(cost)
            try:
                # In place, then orient the small result: exif_transpose on the
                # full image would copy it even when there is nothing to rotate.
                img.thumbnail((size, size), Image.Resampling.LANCZOS, reducing_gap=2.0)
            finally:
                _budget.release(cost)
            thumb = img
            if orientation in EXIF_TRANSPOSE:
                thumb = thumb.transpose(EXIF_TRANSPOSE[orientation])
            if thumb.mode not in ("RGB", "RGBA"):
                thumb = thumb.convert("RGBA" if "A" in thumb.getbands() or "transparency" in thumb.info else "RGB")
            info = PngImagePlugin.PngInfo()
            info.add_text("Thumb::URI", uri)
            info.add_text("Thumb::MTime", str(mtime))
            info.add_text("Software", "ii thumbgen")
            thumb.save(tmp, "PNG", pnginfo=info, compress_level=1)
        return True
    except Exception:
        return False


def make_with_magick(src: str, tmp: str, size: int) -> bool:
    magick = shutil.which("magick") or shutil.which("convert")
    if not magick:
        return False
    # [0]: first frame/page only; -thumbnail strips metadata and resizes cheaply.
    return run_helper([magick, "-limit", "thread", "1", src + "[0]",
                       "-auto-orient", "-thumbnail", f"{size}x{size}>", f"PNG:{tmp}"])


def make_with_ffmpeg(src: str, tmp: str, size: int) -> bool:
    if not shutil.which("ffmpeg"):
        return False
    return run_helper(["ffmpeg", "-v", "error", "-nostdin", "-y", "-threads", "1",
                       "-i", src, "-an", "-sn", "-frames:v", "1",
                       "-vf", f"scale={size}:{size}:force_original_aspect_ratio=decrease",
                       "-f", "image2", "-c:v", "png", tmp])


def make_thumbnail(src: str, out: str, size: int) -> bool:
    try:
        mtime = int(os.stat(src).st_mtime)
    except OSError:
        return False
    tmp = f"{out}.{os.getpid()}.{threading.get_ident()}.tmp"
    ext = os.path.splitext(src)[1].lower()
    _in_flight.add(tmp)
    try:
        if ext in VIDEO_EXTS:
            ok = make_with_ffmpeg(src, tmp, size)
        else:
            ok = make_with_pillow(src, tmp, size, file_uri(src), mtime) or make_with_magick(src, tmp, size)
        if ok and os.path.getsize(tmp) > 0:
            os.replace(tmp, out)
            return True
        return False
    except OSError:
        return False
    finally:
        _in_flight.discard(tmp)
        try:
            os.unlink(tmp)
        except OSError:
            pass


def needs_thumbnail(src_mtime: float, out: str, force: bool) -> bool:
    if force:
        return True
    try:
        return os.stat(out).st_mtime < src_mtime
    except OSError:
        return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.strip().splitlines()[0])
    parser.add_argument("-d", "--img_dirs", "--directory", dest="directory", required=True)
    parser.add_argument("-s", "--size", default="normal", choices=SIZES.keys())
    parser.add_argument("-w", "--workers", type=int, default=0, help="0 = pick from the CPU count")
    parser.add_argument("--force", action="store_true", help="regenerate even fresh thumbnails")
    parser.add_argument("--machine_progress", action="store_true", help="kept for compatibility; always on")
    args = parser.parse_args()

    try:
        os.nice(10)
    except (OSError, AttributeError):
        pass
    try:  # idle-ish IO class so a big folder doesn't stall the desktop
        subprocess.run(["ionice", "-c", "3", "-p", str(os.getpid())],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)
    except (OSError, subprocess.TimeoutExpired):
        pass

    directory = os.path.abspath(os.path.expanduser(args.directory))
    size = SIZES[args.size]
    cache_root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    cache_dir = os.path.join(cache_root, "thumbnails", args.size)
    os.makedirs(cache_dir, exist_ok=True)

    jobs = []
    try:
        with os.scandir(directory) as entries:
            for entry in entries:
                ext = os.path.splitext(entry.name)[1].lower()
                if ext not in IMAGE_EXTS and ext not in VIDEO_EXTS:
                    continue
                try:
                    if not entry.is_file():
                        continue
                    src_mtime = entry.stat().st_mtime
                except OSError:
                    continue
                out = thumbnail_path(cache_dir, entry.path)
                if needs_thumbnail(src_mtime, out, args.force):
                    jobs.append((entry.path, out))
    except OSError as e:
        print(f"ERROR {e}", file=sys.stderr)
        return 2

    if not jobs:
        return 0
    jobs.sort()

    workers = args.workers if args.workers > 0 else max(1, min(4, (os.cpu_count() or 2) // 4))
    workers = min(workers, len(jobs))
    total = len(jobs)
    print(f"PROGRESS 0/{total}", flush=True)

    done = 0
    try:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            # map keeps at most `workers` decodes in flight, in folder order.
            for (src, _), ok in zip(jobs, pool.map(lambda job: make_thumbnail(job[0], job[1], size), jobs)):
                done += 1
                line = f"PROGRESS {done}/{total}"
                if ok:
                    line += f" FILE {src}"
                print(line, flush=True)
    except BrokenPipeError:
        # The shell went away; stop quietly.
        os._exit(0)
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, _on_sigterm)
    sys.exit(main())
