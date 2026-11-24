#!/usr/bin/env python3
"""Render a QR matrix from the Dev tools QR Code tool as a crisp PNG.

Usage: qr_png.py ROWS OUTPUT [MODULE_PX]
  ROWS       module rows joined by commas, "1" = dark ("1010,0101,...")
  OUTPUT     a .png path, or "-" for stdout (piped into wl-copy)
  MODULE_PX  pixels per module (default 12); a 4-module quiet zone is added
"""
import io
import sys

from PIL import Image

QUIET = 4


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    rows = [row for row in sys.argv[1].split(",") if row]
    size = len(rows)
    if size == 0 or any(len(row) != size or set(row) - {"0", "1"} for row in rows):
        print("rows must form a square of 0/1", file=sys.stderr)
        return 2
    scale = max(1, int(sys.argv[3])) if len(sys.argv) > 3 else 12

    side = size + 2 * QUIET
    image = Image.new("1", (side, side), 1)
    pixels = image.load()
    for y, row in enumerate(rows):
        for x, value in enumerate(row):
            if value == "1":
                pixels[x + QUIET, y + QUIET] = 0
    image = image.resize((side * scale, side * scale), Image.NEAREST)

    if sys.argv[2] == "-":
        buffer = io.BytesIO()
        image.save(buffer, "PNG")
        sys.stdout.buffer.write(buffer.getvalue())
    else:
        image.save(sys.argv[2], "PNG")
    return 0


if __name__ == "__main__":
    sys.exit(main())
