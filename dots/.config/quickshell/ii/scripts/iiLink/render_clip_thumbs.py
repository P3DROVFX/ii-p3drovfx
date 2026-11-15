#!/usr/bin/env python3
"""Render cliphist image thumbnails (<=160px PNG) in one batch and prune stale ones.

Modes:
  render <cache_dir> <cliphist_bin> <id>...
      Renders up to 24 numeric cliphist ids into <cache_dir>/<id>.png via
      `cliphist decode | magick -thumbnail` and prints NDJSON lines:
      {"id": "<id>", "png": "<base64>"}.

  prune <cache_dir>
      Reads active numeric ids (one per line) from stdin and deletes any
      <cache_dir>/<id>.png whose id is no longer in history. Prints "empty" or
      "nonempty".
"""

import base64
import json
import os
import re
import shutil
import subprocess
import sys

MAX_BATCH = 24
THUMB_GEOM = "160x160>"
ID_RE = re.compile(r"^\d+$")


def render_one(entry_id: str, dest: str, cliphist_bin: str, magick_bin: str | None) -> bool:
    if not magick_bin:
        return False
    tmp = f"{dest}.tmp.{os.getpid()}"
    p1 = None
    try:
        p1 = subprocess.Popen(
            [cliphist_bin, "decode", entry_id],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        p2 = subprocess.run(
            [magick_bin, "-[0]", "-auto-orient", "-thumbnail", THUMB_GEOM, f"png:{tmp}"],
            stdin=p1.stdout,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if p1.stdout is not None:
            p1.stdout.close()
        rc1 = p1.wait()
        if rc1 == 0 and p2.returncode == 0 and os.path.isfile(tmp) and os.path.getsize(tmp) > 0:
            os.chmod(tmp, 0o600)
            os.replace(tmp, dest)
            return True
        return False
    except OSError:
        return False
    finally:
        if p1 is not None and p1.poll() is None:
            p1.kill()
            p1.wait()
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def cmd_render(args: list[str]) -> int:
    if len(args) < 3:
        return 0
    cache_dir = args[0]
    cliphist_bin = args[1]
    ids = args[2 : 2 + MAX_BATCH]

    os.makedirs(cache_dir, mode=0o700, exist_ok=True)
    magick_bin = shutil.which("magick")

    seen: set[str] = set()
    for entry_id in ids:
        if not ID_RE.match(entry_id) or entry_id in seen:
            continue
        seen.add(entry_id)
        dest = os.path.join(cache_dir, f"{entry_id}.png")
        if not (os.path.isfile(dest) and os.path.getsize(dest) > 0):
            if not render_one(entry_id, dest, cliphist_bin, magick_bin):
                continue
        try:
            with open(dest, "rb") as f:
                data = f.read()
        except OSError:
            continue
        if not data:
            continue
        b64 = base64.b64encode(data).decode("ascii")
        print(json.dumps({"id": entry_id, "png": b64}), flush=True)
    return 0


def cmd_prune(args: list[str]) -> int:
    if len(args) < 1:
        print("empty", flush=True)
        return 0
    cache_dir = args[0]
    keep = {line.strip() for line in sys.stdin if ID_RE.match(line.strip())}
    if not os.path.isdir(cache_dir):
        print("empty", flush=True)
        return 0

    remaining = 0
    try:
        with os.scandir(cache_dir) as it:
            for entry in it:
                name = entry.name
                if name.endswith(".png"):
                    stem = name[:-4]
                    if stem in keep:
                        remaining += 1
                    else:
                        try:
                            os.unlink(entry.path)
                        except OSError:
                            remaining += 1
                elif ".tmp." in name:
                    try:
                        os.unlink(entry.path)
                    except OSError:
                        pass
    except OSError:
        print("empty", flush=True)
        return 0

    print("nonempty" if remaining > 0 else "empty", flush=True)
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        return 0
    mode = sys.argv[1]
    if mode == "render":
        return cmd_render(sys.argv[2:])
    if mode == "prune":
        return cmd_prune(sys.argv[2:])
    return 1


if __name__ == "__main__":
    sys.exit(main())
