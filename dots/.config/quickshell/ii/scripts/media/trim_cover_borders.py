#!/usr/bin/env python3
"""Trim uniform dark bars from cover art.

YouTube Music often serves a 16:9 video thumbnail with the square album art
pillarboxed in black, sometimes with a dark scan frame around it. Media Mode
crops covers to a square or to the screen, so those bars show up as a black
frame. This removes them and prints the path of the trimmed copy, or the
original path when there is nothing safe to remove.

A side is only trimmed when every line removed is uniformly dark, and opposite
sides are trimmed together by similar amounts. Album art is square, so a trim is
kept only when it brings the image closer to 1:1 (a pillarboxed thumbnail), or
when it removes a thin frame from all four sides. Genuinely dark artwork, whose
black background would otherwise read as bars, is left alone.

Usage: trim_cover_borders.py <image> <output-dir>
"""

import hashlib
import math
import os
import sys

from PIL import Image, ImageStat

DARK_MEAN = 26  # luminance a bar line may average
FLAT_SPREAD = 22  # max - min luminance allowed across a bar line
MAX_TRIM = 0.4  # never remove more than this fraction per side
SYMMETRY = 0.06  # opposite margins may differ by this fraction of the size
FRAME_MAX = 0.08  # a four-sided frame may take at most this fraction per side


def _is_bar(line: Image.Image) -> bool:
    stat = ImageStat.Stat(line)
    low, high = stat.extrema[0]
    return stat.mean[0] <= DARK_MEAN and (high - low) <= FLAT_SPREAD


def _margin(gray: Image.Image, side: str) -> int:
    width, height = gray.size
    limit = int((width if side in ("left", "right") else height) * MAX_TRIM)
    for i in range(limit):
        if side == "left":
            box = (i, 0, i + 1, height)
        elif side == "right":
            box = (width - 1 - i, 0, width - i, height)
        elif side == "top":
            box = (0, i, width, i + 1)
        else:
            box = (0, height - 1 - i, width, height - i)
        if not _is_bar(gray.crop(box)):
            return i
    return limit


def _pair(first: int, second: int, size: int) -> tuple[int, int]:
    if first == 0 and second == 0:
        return 0, 0
    if abs(first - second) > size * SYMMETRY:
        return 0, 0
    return first, second


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    path = sys.argv[1].removeprefix("file://")
    out_dir = sys.argv[2].removeprefix("file://")
    try:
        image = Image.open(path)
        image.load()
    except (OSError, ValueError):
        print(path)
        return 0

    # Measure on a small copy: bars are large, and this keeps the scan cheap.
    scale = max(1, max(image.size) // 400)
    gray = image.convert("L").reduce(scale)
    width, height = gray.size

    left, right = _pair(_margin(gray, "left"), _margin(gray, "right"), width)
    top, bottom = _pair(_margin(gray, "top"), _margin(gray, "bottom"), height)
    if not (left or right or top or bottom):
        print(path)
        return 0

    box = (left * scale, top * scale, image.width - right * scale, image.height - bottom * scale)
    new_w, new_h = box[2] - box[0], box[3] - box[1]
    if new_w < image.width * 0.2 or new_h < image.height * 0.2:
        print(path)
        return 0

    old_skew = abs(math.log(image.width / image.height))
    new_skew = abs(math.log(new_w / new_h))
    squarer = new_skew < old_skew - 0.02
    thin_frame = (
        all((left, right, top, bottom))
        and max(left, right) <= width * FRAME_MAX
        and max(top, bottom) <= height * FRAME_MAX
        and new_skew <= old_skew + 0.02
    )
    if not (squarer or thin_frame):
        print(path)
        return 0

    os.makedirs(out_dir, exist_ok=True)
    digest = hashlib.md5(f"{path}:{os.path.getmtime(path)}:{box}".encode()).hexdigest()
    target = os.path.join(out_dir, f"{digest}.png")
    if not os.path.exists(target):
        image.crop(box).convert("RGB").save(target)
    print(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
