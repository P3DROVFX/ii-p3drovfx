#!/usr/bin/env python3
"""Copy an image file to the Wayland clipboard as image/png.

Many desktop programs (Chromium, Electron apps, Discord, GIMP, XWayland apps)
ignore or reject image/jpeg or image/webp clipboard offers and only accept
image/png. Passing a JPEG file directly with ``wl-copy --type image/png`` also
breaks decoding because the bytes stay JPEG.

If the file is already a PNG (checked by magic bytes), it is streamed straight
to ``wl-copy --type image/png``. Otherwise it is decoded (applying EXIF
orientation), re-encoded as PNG, and passed to ``wl-copy --type image/png``.

Usage: copy_image_to_clipboard.py [--delete] /path/to/image
"""

import argparse
import io
import os
import shutil
import subprocess
import sys

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def is_png(path):
    with open(path, "rb") as f:
        return f.read(len(PNG_MAGIC)) == PNG_MAGIC


def encode_png_with_pillow(path):
    from PIL import Image, ImageOps

    with Image.open(path) as img:
        img = ImageOps.exif_transpose(img)
        has_alpha = img.mode in ("RGBA", "LA", "PA") or (
            img.mode == "P" and "transparency" in img.info
        )
        target_mode = "RGBA" if has_alpha else "RGB"
        if img.mode != target_mode:
            img = img.convert(target_mode)
        buf = io.BytesIO()
        img.save(buf, format="PNG", compress_level=1)
        return buf.getvalue()


def encode_png_with_magick(path):
    magick = shutil.which("magick") or shutil.which("convert")
    if not magick:
        raise RuntimeError("neither Pillow nor ImageMagick could decode the image")
    res = subprocess.run(
        [magick, f"{path}[0]", "-auto-orient", "png:-"],
        capture_output=True,
        check=True,
    )
    return res.stdout


def to_png_bytes(path):
    try:
        return encode_png_with_pillow(path)
    except Exception as pillow_err:
        try:
            return encode_png_with_magick(path)
        except Exception as magick_err:
            raise RuntimeError(f"pillow={pillow_err}; magick={magick_err}") from magick_err


def copy_image(path):
    if is_png(path):
        with open(path, "rb") as f:
            subprocess.run(["wl-copy", "--type", "image/png"], stdin=f, check=True)
        return
    png_bytes = to_png_bytes(path)
    subprocess.run(["wl-copy", "--type", "image/png"], input=png_bytes, check=True)


def main():
    parser = argparse.ArgumentParser(description="Copy an image to the Wayland clipboard as PNG.")
    parser.add_argument("--delete", action="store_true", help="Delete the source file afterwards")
    parser.add_argument("path", help="Path to the image file")
    args = parser.parse_args()

    path = os.path.abspath(args.path)
    try:
        if not os.path.isfile(path):
            print(f"not a file: {path}", file=sys.stderr)
            return 1
        copy_image(path)
        return 0
    except Exception as error:
        print(f"copy_image_to_clipboard failed: {error}", file=sys.stderr)
        return 1
    finally:
        if args.delete:
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    sys.exit(main())
