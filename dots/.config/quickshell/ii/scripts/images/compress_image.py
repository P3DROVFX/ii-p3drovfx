#!/usr/bin/env python3
"""Photo compressor backend for the cheatsheet Dev tools page.

  compress_image.py info <src>
      {"ok", "width", "height", "format", "size", "alpha", "frames"}
  compress_image.py encode <src> <dst> --format F [--quality Q] [--scale S] [--keep-metadata]
      {"progress", "stage"} lines (read, prepare, encode), then
      {"ok", "size", "width", "height", "format", "lossless"}

Every result is one JSON line on stdout; failures are {"ok": false, "error"}.
The page encodes into a cache file to show the real size before saving, and
saving copies that file, so the estimate is exactly what lands on disk.

Pillow does the formats it can write; JPEG XL goes through ImageMagick and
AVIF through ffmpeg (libaom / SVT-AV1), both from a lossless PNG
intermediate.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageOps

Image.MAX_IMAGE_PIXELS = 200_000_000

def emit(payload: dict) -> None:
    print(json.dumps(payload), flush=True)


def fail(message: str) -> None:
    emit({"ok": False, "error": message})
    sys.exit(1)


def load(src: str) -> Image.Image:
    try:
        image = Image.open(src)
        image.load()
    except Exception:
        # Formats Pillow cannot read here (AVIF, HEIC, JXL...): decode with magick.
        if not shutil.which("magick"):
            raise RuntimeError("Unsupported or damaged image")
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            png = tmp.name
        try:
            if subprocess.run(["magick", src + "[0]", png], capture_output=True).returncode != 0:
                raise RuntimeError("Unsupported or damaged image")
            image = Image.open(png)
            image.load()
        finally:
            os.unlink(png)
    return image


def has_alpha(image: Image.Image) -> bool:
    return image.mode in ("RGBA", "LA", "PA") or (image.mode == "P" and "transparency" in image.info)


def cmd_info(args) -> None:
    size = os.path.getsize(args.src)
    try:
        image = Image.open(args.src)
        fmt = image.format or ""
        width, height = image.size
        # Report the size as displayed: EXIF rotations 5-8 swap the sides.
        if image.getexif().get(0x0112, 1) in (5, 6, 7, 8):
            width, height = height, width
        frames = getattr(image, "n_frames", 1)
        alpha = has_alpha(image)
    except Exception:
        image = load(args.src)
        fmt = os.path.splitext(args.src)[1].lstrip(".").upper()
        width, height = image.size
        frames = 1
        alpha = has_alpha(image)
    emit({"ok": True, "width": width, "height": height, "format": fmt,
          "size": size, "alpha": alpha, "frames": frames})


def flatten(image: Image.Image, background=(255, 255, 255)) -> Image.Image:
    """RGB for formats without alpha: composite transparency over white."""
    if has_alpha(image):
        rgba = image.convert("RGBA")
        base = Image.new("RGB", rgba.size, background)
        base.paste(rgba, mask=rgba.getchannel("A"))
        return base
    return image.convert("RGB")


def quantized(image: Image.Image, quality: int) -> Image.Image:
    """Palette reduction for PNG/GIF: the slider picks the colour count."""
    colors = max(2, min(256, round(256 * (quality / 100) ** 2)))
    rgba = image.convert("RGBA")
    return rgba.quantize(colors=colors, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)


def via_png(image: Image.Image, dst: str, command) -> None:
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
        png = tmp.name
    try:
        image.save(png, "PNG", compress_level=1)
        result = subprocess.run(command(png), capture_output=True, text=True)
        if result.returncode != 0 or not os.path.exists(dst) or os.path.getsize(dst) == 0:
            tail = (result.stderr or "").strip().splitlines()[-1:] or ["encoder failed"]
            raise RuntimeError(tail[0])
    finally:
        os.unlink(png)


def encode_avif(image: Image.Image, dst: str, quality: int) -> None:
    if not shutil.which("ffmpeg"):
        raise RuntimeError("AVIF needs ffmpeg")
    # Even dimensions: 4:2:0 chroma needs them.
    w, h = image.size
    if w % 2 or h % 2:
        image = image.crop((0, 0, w - w % 2, h - h % 2)) if w > 1 and h > 1 else image
    crf = round(63 - quality * 0.55)
    alpha = has_alpha(image)
    image = image.convert("RGBA" if alpha else "RGB")
    pix = "yuva420p" if alpha else "yuv420p"
    via_png(image, dst, lambda png: [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", png,
        "-c:v", "libaom-av1", "-still-picture", "1", "-crf", str(crf), "-b:v", "0",
        "-cpu-used", "6", "-row-mt", "1", "-pix_fmt", pix, dst])


def encode_jxl(image: Image.Image, dst: str, quality: int) -> None:
    if not shutil.which("magick"):
        raise RuntimeError("JPEG XL needs ImageMagick")
    image = image.convert("RGBA" if has_alpha(image) else "RGB")
    via_png(image, dst, lambda png: [
        "magick", png, "-quality", str(min(99, quality)), "-define", "jxl:effort=5", "jxl:" + dst])


def stage(progress: float, name: str) -> None:
    """Progress line for the page's bar; the result line is the one with "ok"."""
    emit({"progress": progress, "stage": name})


def cmd_encode(args) -> None:
    stage(0.05, "read")
    image = load(args.src)
    stage(0.25, "prepare")
    icc = image.info.get("icc_profile")
    # Bake the camera rotation in (stripped EXIF would otherwise turn photos);
    # the transposed copy's EXIF no longer carries the orientation tag.
    image = ImageOps.exif_transpose(image)
    exif = image.info.get("exif") if args.keep_metadata else None
    if args.scale < 100:
        w = max(1, round(image.width * args.scale / 100))
        h = max(1, round(image.height * args.scale / 100))
        image = image.resize((w, h), Image.Resampling.LANCZOS)
    stage(0.4, "encode")

    fmt = args.format
    q = max(1, min(100, args.quality))
    extra = {}
    if icc:
        extra["icc_profile"] = icc
    if exif:
        extra["exif"] = exif

    if fmt == "jpeg":
        flatten(image).save(args.dst, "JPEG", quality=q, optimize=True, progressive=True,
                            subsampling=0 if q >= 90 else 2, **extra)
    elif fmt == "webp":
        image = image.convert("RGBA" if has_alpha(image) else "RGB")
        image.save(args.dst, "WEBP", quality=q, method=5, lossless=False, **extra)
    elif fmt == "png":
        out = image if q >= 100 else quantized(image, q)
        out.save(args.dst, "PNG", optimize=True, **({"icc_profile": icc} if icc and q >= 100 else {}))
    elif fmt == "gif":
        quantized(image, q).save(args.dst, "GIF", optimize=True)
    elif fmt == "jp2":
        # Compression ratio over raw RGB, in JPEG's range: ~21:1 at 80, ~63:1 at 50.
        ratio = 10 * 40 ** ((100 - q) / 100)
        flatten(image).save(args.dst, "JPEG2000", quality_mode="rates",
                            quality_layers=[ratio] if q < 100 else [], irreversible=q < 100)
    elif fmt == "tiff":
        image.convert("RGBA" if has_alpha(image) else "RGB").save(args.dst, "TIFF", compression="tiff_adobe_deflate")
    elif fmt == "bmp":
        flatten(image).save(args.dst, "BMP")
    elif fmt == "qoi":
        # Pillow's QOI writer is pure Python (~20 s on a 30 MP photo).
        image = image.convert("RGBA" if has_alpha(image) else "RGB")
        if shutil.which("magick"):
            via_png(image, args.dst, lambda png: ["magick", png, "qoi:" + args.dst])
        else:
            image.save(args.dst, "QOI")
    elif fmt == "avif":
        encode_avif(image, args.dst, q)
    elif fmt == "jxl":
        encode_jxl(image, args.dst, q)
    else:
        fail(f"Unknown format {fmt}")

    if fmt == "avif":
        width, height = image.width - image.width % 2, image.height - image.height % 2
    else:
        width, height = image.size
    emit({"ok": True, "size": os.path.getsize(args.dst), "width": width, "height": height,
          "format": fmt, "lossless": fmt in ("tiff", "bmp", "qoi") or (fmt == "png" and q >= 100)})


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    info = sub.add_parser("info")
    info.add_argument("src")
    enc = sub.add_parser("encode")
    enc.add_argument("src")
    enc.add_argument("dst")
    enc.add_argument("--format", required=True)
    enc.add_argument("--quality", type=int, default=80)
    enc.add_argument("--scale", type=int, default=100)
    enc.add_argument("--keep-metadata", action="store_true")
    args = parser.parse_args()
    if not os.path.isfile(args.src):
        fail("File not found")
    try:
        if args.command == "info":
            cmd_info(args)
        else:
            os.makedirs(os.path.dirname(os.path.abspath(args.dst)), exist_ok=True)
            cmd_encode(args)
    except SystemExit:
        raise
    except Exception as error:
        fail(str(error) or error.__class__.__name__)


if __name__ == "__main__":
    main()
