#!/usr/bin/env python3
"""Depth effect for the desktop: model downloads and wallpaper subject cutouts.

The shell runs this through depth.sh (the shell's venv: numpy, opencv, pillow).
The ONNX runtime is not part of that venv: it is installed on demand into
<root>/runtime with the first model and removed with the last one, so a user
who never turns the effect on carries none of it.

Every command prints one JSON object per line on stdout - the shell reads them
as events:
    {"event": "progress", "phase": "runtime"|"model", "received": n, "total": n}
    {"event": "status", ...} / {"event": "result", ...} / {"event": "error", "message": ...}

Layout of <root>:
    models/<file>.onnx      downloaded models (written as .part, renamed when verified)
    runtime/                onnxruntime, pip --target, no pip cache kept
    cutouts/<key>.png|json  one cutout per (wallpaper file, model); pruned to the
                            wallpapers actually on screen
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
CATALOG = json.loads((HERE / "models.json").read_text())
# Bump when the cutout pipeline changes, so stale cutouts are recomputed.
CUTOUT_VERSION = 3


def emit(**fields):
    print(json.dumps(fields), flush=True)


def fail(message, **fields):
    emit(event="error", message=message, **fields)
    sys.exit(1)


def model_entry(model_id):
    for entry in CATALOG["models"]:
        if entry["id"] == model_id:
            return entry
    fail(f"unknown model: {model_id}")


class Root:
    def __init__(self, path):
        self.path = Path(path).expanduser()
        self.models = self.path / "models"
        self.runtime = self.path / "runtime"
        self.cutouts = self.path / "cutouts"

    def model_file(self, entry):
        return self.models / entry["file"]

    def runtime_ready(self):
        return (self.runtime / "onnxruntime" / "__init__.py").exists()

    def installed_models(self):
        return [m["id"] for m in CATALOG["models"] if self.model_file(m).exists()]


# ── status / remove / prune ─────────────────────────────────────────────────

def cmd_status(root, _args):
    emit(event="status", runtime=root.runtime_ready(), models=root.installed_models())


def cmd_remove(root, args):
    entry = model_entry(args.model)
    for path in (root.model_file(entry), root.model_file(entry).with_suffix(".part")):
        path.unlink(missing_ok=True)
    # Cutouts made by this model go with it.
    if root.cutouts.exists():
        for meta in root.cutouts.glob("*.json"):
            try:
                if json.loads(meta.read_text()).get("model") == entry["id"]:
                    meta.with_suffix(".png").unlink(missing_ok=True)
                    meta.unlink(missing_ok=True)
            except (OSError, ValueError):
                pass
    # The last model takes the runtime and every cutout along: nothing of the
    # feature stays on disk once it cannot run.
    if not root.installed_models():
        shutil.rmtree(root.runtime, ignore_errors=True)
        shutil.rmtree(root.path / "runtime.part", ignore_errors=True)
        shutil.rmtree(root.cutouts, ignore_errors=True)
    cmd_status(root, args)


def cmd_prune(root, args):
    keep = set(args.keep or [])
    removed = 0
    if root.cutouts.exists():
        for path in root.cutouts.iterdir():
            if path.stem not in keep:
                path.unlink(missing_ok=True)
                removed += 1
    emit(event="pruned", removed=removed)


# ── downloads ───────────────────────────────────────────────────────────────

def install_runtime(root, report):
    """pip --target into runtime.part, then swap it in. No cache, no deps: the
    shell's venv already has numpy, and the inference path imports nothing else."""
    staging = root.path / "runtime.part"
    shutil.rmtree(staging, ignore_errors=True)
    cmd = [sys.executable, "-m", "pip", "install", "--no-cache-dir", "--no-deps",
           "--disable-pip-version-check", "--progress-bar", "raw",
           "--target", str(staging), CATALOG["runtime"]["package"]]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    tail = []
    for line in proc.stdout:
        match = re.match(r"Progress (\d+) of (\d+)", line.strip())
        if match:
            report(int(match.group(1)), int(match.group(2)))
        else:
            tail = (tail + [line.strip()])[-6:]
    if proc.wait() != 0:
        shutil.rmtree(staging, ignore_errors=True)
        fail("Could not install the ONNX runtime", detail="\n".join(tail))
    shutil.rmtree(root.runtime, ignore_errors=True)
    staging.rename(root.runtime)


def download_model(root, entry, report):
    target = root.model_file(entry)
    part = target.with_suffix(".part")
    root.models.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(entry["url"], headers={"User-Agent": "quickshell-ii-depth"})
    digest = hashlib.sha256()
    received = 0
    try:
        with urllib.request.urlopen(request, timeout=30) as response, open(part, "wb") as out:
            total = int(response.headers.get("Content-Length") or entry["bytes"])
            last = 0.0
            while True:
                chunk = response.read(1 << 20)
                if not chunk:
                    break
                out.write(chunk)
                digest.update(chunk)
                received += len(chunk)
                now = time.monotonic()
                if now - last > 0.2:
                    report(received, total)
                    last = now
            report(received, total)
    except OSError as error:
        part.unlink(missing_ok=True)
        fail(f"Download failed: {error}")
    if received != entry["bytes"]:
        part.unlink(missing_ok=True)
        fail(f"Download incomplete ({received} of {entry['bytes']} bytes)")
    if entry.get("sha256") and digest.hexdigest() != entry["sha256"]:
        part.unlink(missing_ok=True)
        fail("Downloaded model failed its checksum")
    part.rename(target)


def cmd_download(root, args):
    entry = model_entry(args.model)
    root.path.mkdir(parents=True, exist_ok=True)
    need_runtime = not root.runtime_ready()
    runtime_bytes = CATALOG["runtime"]["approxBytes"] if need_runtime else 0
    grand_total = runtime_bytes + entry["bytes"]

    if need_runtime:
        def runtime_report(done, total):
            # pip reports the wheel's own size; scale it onto the estimate so
            # the bar never runs backwards when the model phase begins.
            share = done / total if total else 0
            emit(event="progress", phase="runtime", received=int(share * runtime_bytes), total=grand_total)
        runtime_report(0, 1)
        install_runtime(root, runtime_report)

    def model_report(done, _total):
        emit(event="progress", phase="model", received=runtime_bytes + done, total=grand_total)
    if not root.model_file(entry).exists():
        download_model(root, entry, model_report)
    model_report(entry["bytes"], entry["bytes"])
    cmd_status(root, args)


# ── segmentation ────────────────────────────────────────────────────────────

def cutout_key(image, model_id):
    stat = os.stat(image)
    raw = f"{os.path.realpath(image)}|{stat.st_size}|{stat.st_mtime_ns}|{model_id}|{CUTOUT_VERSION}"
    return hashlib.sha1(raw.encode()).hexdigest()[:24]


def run_model(root, entry, rgb):
    """Returns the subject's alpha at the image's full resolution, float32 0..1."""
    import numpy as np
    import cv2

    sys.path.insert(0, str(root.runtime))
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    options.intra_op_num_threads = max(2, (os.cpu_count() or 4) // 2)
    options.log_severity_level = 3
    # The arena and the memory pattern keep every intermediate tensor of the
    # whole graph alive at once: BiRefNet peaked at 7.7 GB with them on.
    options.enable_cpu_mem_arena = False
    options.enable_mem_pattern = False
    session = ort.InferenceSession(str(root.model_file(entry)), options, providers=["CPUExecutionProvider"])

    h0, w0 = rgb.shape[:2]
    size = entry["input"]
    pad = (0, 0, h0, w0)
    if entry["kind"] == "depth":
        # Short side at the model's size, both sides multiples of the ViT patch (14).
        scale = size / min(h0, w0)
        th = max(14, round(h0 * scale / 14) * 14)
        tw = max(14, round(w0 * scale / 14) * 14)
        resized = cv2.resize(rgb, (tw, th), interpolation=cv2.INTER_AREA)
        canvas = resized
    elif entry.get("letterbox"):
        scale = size / max(h0, w0)
        th, tw = round(h0 * scale), round(w0 * scale)
        canvas = np.zeros((size, size, 3), np.uint8)
        top, left = (size - th) // 2, (size - tw) // 2
        canvas[top:top + th, left:left + tw] = cv2.resize(rgb, (tw, th), interpolation=cv2.INTER_AREA)
        pad = (top, left, th, tw)
    else:
        canvas = cv2.resize(rgb, (size, size), interpolation=cv2.INTER_AREA)

    x = canvas.astype(np.float32) / 255.0
    x = (x - np.array(entry["mean"], np.float32)) / np.array(entry["std"], np.float32)
    x = np.ascontiguousarray(x.transpose(2, 0, 1)[None])
    out = session.run(None, {session.get_inputs()[0].name: x})[0]
    del session
    pred = np.squeeze(out).astype(np.float32)
    if pred.ndim == 3:
        pred = pred[0]

    if entry["output"] == "sigmoid":
        pred = 1.0 / (1.0 + np.exp(-pred))
    elif entry["output"] == "minmax":
        pred = (pred - pred.min()) / max(1e-6, float(pred.max() - pred.min()))
    elif entry["output"] == "depth":
        return depth_to_alpha(pred, rgb)
    pred = np.clip(pred, 0.0, 1.0)

    top, left, th, tw = pad
    if entry.get("letterbox"):
        pred = pred[top:top + th, left:left + tw]
    return cv2.resize(pred, (w0, h0), interpolation=cv2.INTER_LINEAR)


def depth_to_alpha(depth, rgb):
    """Relative inverse depth (bigger = nearer) to the near plane's alpha: an Otsu
    split of the depth histogram, soft around the cut, snapped to the picture's
    own edges with a guided filter at full resolution."""
    import numpy as np
    import cv2

    h0, w0 = rgb.shape[:2]
    lo, hi = np.percentile(depth, 2), np.percentile(depth, 98)
    norm = np.clip((depth - lo) / max(1e-6, hi - lo), 0, 1)
    threshold, _ = cv2.threshold((norm * 255).astype(np.uint8), 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    t = threshold / 255.0
    band = 0.06
    alpha = np.clip((norm - (t - band)) / (2 * band), 0, 1)
    alpha = alpha * alpha * (3 - 2 * alpha)
    alpha = cv2.resize(alpha.astype(np.float32), (w0, h0), interpolation=cv2.INTER_LINEAR)
    radius = max(4, round(min(h0, w0) / 160))
    guide = rgb.astype(np.float32) / 255.0
    alpha = cv2.ximgproc.guidedFilter(guide, alpha, radius, 1e-3)
    return np.clip(alpha, 0, 1)


def drop_specks(alpha):
    """Keeps the subject's own regions: components smaller than 2% of the
    largest one (stray specks, a glint the model half-picked) are cleared, with
    a small margin kept around the survivors for their soft edges."""
    import numpy as np
    import cv2

    solid = (alpha > 0.5).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(solid, connectivity=8)
    if count <= 1:
        return alpha
    areas = stats[1:, cv2.CC_STAT_AREA]
    keep = np.zeros(count, bool)
    keep[1:] = areas >= max(64, 0.02 * areas.max())
    mask = keep[labels].astype(np.uint8)
    margin = max(3, round(min(alpha.shape) / 120))
    mask = cv2.dilate(mask, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * margin + 1, 2 * margin + 1)))
    return alpha * mask


def cmd_segment(root, args):
    entry = model_entry(args.model)
    if not root.runtime_ready() or not root.model_file(entry).exists():
        fail("Model is not installed", model=entry["id"])
    image = os.path.realpath(args.image)
    if not os.path.isfile(image):
        fail("Wallpaper not found", image=image)
    key = cutout_key(image, entry["id"])
    meta_path = root.cutouts / f"{key}.json"
    if meta_path.exists() and meta_path.with_suffix(".png").exists():
        meta = json.loads(meta_path.read_text())
        emit(event="result", cached=True, **meta)
        return

    import numpy as np
    import cv2
    from PIL import Image

    started = time.monotonic()
    emit(event="working", key=key, model=entry["id"])
    with Image.open(image) as img:
        # Qt draws the file without EXIF rotation (Image.autoTransform defaults to
        # false), so the cutout keeps the raw orientation too.
        rgb = np.asarray(img.convert("RGB"))
    h0, w0 = rgb.shape[:2]
    alpha = run_model(root, entry, rgb)
    # A slight pull-in of the edge: the model's outer fringe is mostly background.
    alpha = np.clip((alpha - 0.06) / 0.94, 0, 1).astype(np.float32)
    alpha = drop_specks(alpha)
    # The subject's body is solid: a model's 0.97-0.99 inside it let ~1% of a
    # widget behind show through, a faint ghost of the clock's glyphs.
    alpha[alpha > 0.96] = 1.0

    coverage = float(alpha.mean())
    meta = {
        "version": CUTOUT_VERSION, "key": key, "model": entry["id"], "source": image,
        "sourceWidth": int(w0), "sourceHeight": int(h0), "coverage": round(coverage, 4),
    }
    # No subject (an abstract picture) or everything is "subject" (a model that
    # gave up): either way a cutout would only cover the widgets.
    if coverage < 0.004 or coverage > 0.85:
        meta.update(empty=True, x=0, y=0, width=0, height=0, png="")
        write_meta(root, meta_path, meta)
        emit(event="result", cached=False, ms=int((time.monotonic() - started) * 1000), **meta)
        return

    ys, xs = np.nonzero(alpha > (1.0 / 255.0))
    x0, x1 = max(0, xs.min() - 2), min(w0, xs.max() + 3)
    y0, y1 = max(0, ys.min() - 2), min(h0, ys.max() + 3)
    # The picture's own colours, edges included. Drawn over the wallpaper it
    # was cut from, a*I + (1-a)*I is I again: wherever no widget sits behind
    # the subject the screen is exactly the wallpaper. Any recoloured edge (a
    # foreground estimate, a defringe) would show as an outline there.
    crop_alpha = alpha[y0:y1, x0:x1]
    rgba = np.dstack([rgb[y0:y1, x0:x1], (crop_alpha * 255 + 0.5).astype(np.uint8)])

    root.cutouts.mkdir(parents=True, exist_ok=True)
    png_path = meta_path.with_suffix(".png")
    tmp_png = png_path.with_suffix(".tmp.png")
    cv2.imwrite(str(tmp_png), cv2.cvtColor(rgba, cv2.COLOR_RGBA2BGRA), [cv2.IMWRITE_PNG_COMPRESSION, 3])
    os.replace(tmp_png, png_path)
    meta.update(empty=False, x=int(x0), y=int(y0), width=int(x1 - x0), height=int(y1 - y0), png=str(png_path))
    write_meta(root, meta_path, meta)
    emit(event="result", cached=False, ms=int((time.monotonic() - started) * 1000), **meta)


def write_meta(root, meta_path, meta):
    root.cutouts.mkdir(parents=True, exist_ok=True)
    tmp = meta_path.with_suffix(".tmp")
    tmp.write_text(json.dumps(meta))
    os.replace(tmp, meta_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--root", required=True)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    p = sub.add_parser("download")
    p.add_argument("model")
    p = sub.add_parser("remove")
    p.add_argument("model")
    p = sub.add_parser("prune")
    p.add_argument("--keep", nargs="*")
    p = sub.add_parser("segment")
    p.add_argument("--model", required=True)
    p.add_argument("--image", required=True)
    args = parser.parse_args()
    root = Root(args.root)
    {"status": cmd_status, "download": cmd_download, "remove": cmd_remove,
     "prune": cmd_prune, "segment": cmd_segment}[args.command](root, args)


if __name__ == "__main__":
    main()
