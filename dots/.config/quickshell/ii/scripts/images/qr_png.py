#!/usr/bin/env python3
"""Render a QR matrix or SVG from the Dev tools QR Code tool as a crisp PNG.

Usage:
  qr_png.py ROWS OUTPUT [MODULE_PX]
  qr_png.py --svg PATH_OR_- OUTPUT [--size 800] [--rows ROWS]

  ROWS       module rows joined by commas, "1" = dark ("1010,0101,...")
  OUTPUT     a .png path, or "-" for stdout (piped into wl-copy)
  MODULE_PX  pixels per module (default 12); a 4-module quiet zone is added
"""
import argparse
import io
import shutil
import subprocess
import sys

QUIET = 4


def render_pillow(rows_text: str, output: str, scale: int) -> int:
    from PIL import Image

    rows = [row for row in rows_text.split(",") if row]
    size = len(rows)
    if size == 0 or any(len(row) != size or set(row) - {"0", "1"} for row in rows):
        print("rows must form a square of 0/1", file=sys.stderr)
        return 2

    side = size + 2 * QUIET
    image = Image.new("1", (side, side), 1)
    pixels = image.load()
    for y, row in enumerate(rows):
        for x, value in enumerate(row):
            if value == "1":
                pixels[x + QUIET, y + QUIET] = 0
    image = image.resize((side * scale, side * scale), Image.NEAREST)

    if output == "-":
        buffer = io.BytesIO()
        image.save(buffer, "PNG")
        sys.stdout.buffer.write(buffer.getvalue())
    else:
        image.save(output, "PNG")
    return 0


def render_svg(svg_source: str, output: str, size_px: int, fallback_rows: str) -> int:
    rsvg = shutil.which("rsvg-convert")
    if rsvg:
        svg_bytes = sys.stdin.buffer.read() if svg_source == "-" else open(svg_source, "rb").read()
        if not svg_bytes.strip():
            print("empty SVG input", file=sys.stderr)
            return 2
        cmd = [rsvg, "-w", str(size_px), "-h", str(size_px)]
        if output != "-":
            cmd.extend(["-o", output])
        proc = subprocess.run(cmd, input=svg_bytes, stdout=subprocess.PIPE if output == "-" else None, check=False)
        if proc.returncode != 0:
            return proc.returncode
        if output == "-":
            sys.stdout.buffer.write(proc.stdout)
        return 0

    if fallback_rows:
        rows = [row for row in fallback_rows.split(",") if row]
        side = len(rows) + 2 * QUIET
        scale = max(1, round(size_px / side)) if side > 0 else 12
        return render_pillow(fallback_rows, output, scale)

    print("rsvg-convert is needed to rasterize SVG when --rows fallback is absent", file=sys.stderr)
    return 1


def main() -> int:
    if len(sys.argv) >= 2 and "--svg" not in sys.argv:
        if len(sys.argv) < 3:
            print(__doc__, file=sys.stderr)
            return 2
        scale = max(1, int(sys.argv[3])) if len(sys.argv) > 3 else 12
        return render_pillow(sys.argv[1], sys.argv[2], scale)

    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--svg", required=True, help="SVG file path or - for stdin")
    parser.add_argument("--size", type=int, default=800, help="Output width/height in pixels")
    parser.add_argument("--rows", default="", help="Fallback 0/1 comma-joined rows if rsvg-convert is missing")
    parser.add_argument("output", help="Output PNG path or - for stdout")
    args = parser.parse_args()
    return render_svg(args.svg, args.output, max(16, args.size), args.rows)


if __name__ == "__main__":
    sys.exit(main())
