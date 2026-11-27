#!/usr/bin/env python3
"""Writes the ii Vitals store for VitalsService (scripts/iiLink/PROTOCOL.md, "Vitals").

One JSON request on stdin's first line:
  {"dir": "<store>", "wipe": bool, "write": [["<rel>", "<text>"], ...],
   "delete": ["<rel>", ...], "pruneBefore": "YYYY-MM-DD" | ""}
applied in that order. Directories are 0700 and files 0600 from the moment they exist
(health data), and every file is replaced atomically, so a reader never sees half a day.
Exit 0 when everything was applied, 1 with the reason on stderr otherwise.
"""

import json
import os
import re
import shutil
import sys

REL = re.compile(r"^(?:(?:meta|index|sync)\.json|days/\d{4}-\d{2}-\d{2}\.json|routes/[0-9a-f]{16}\.json)$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def ensure_dir(path):
    os.makedirs(path, mode=0o700, exist_ok=True)
    # makedirs leaves an existing directory's mode alone.
    os.chmod(path, 0o700)


def write_atomic(root, rel, text):
    dst = os.path.join(root, rel)
    ensure_dir(os.path.dirname(dst))
    tmp = os.path.join(os.path.dirname(dst), "." + os.path.basename(dst) + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    try:
        # A temp file left by a killed run keeps its old mode through O_CREAT.
        os.fchmod(fd, 0o600)
        data = text.encode("utf-8")
        while data:
            data = data[os.write(fd, data):]
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, dst)


def unlink(path):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


def main():
    req = json.loads(sys.stdin.readline())
    root = req["dir"]
    if not os.path.isabs(root) or os.path.basename(os.path.normpath(root)) != "vitals":
        raise ValueError("store dir must be an absolute .../vitals path")
    writes = req.get("write", [])
    deletes = req.get("delete", [])
    for rel in [w[0] for w in writes] + deletes:
        if not REL.match(rel):
            raise ValueError(f"refusing path {rel!r}")
    cut = req.get("pruneBefore", "")
    if cut and not DATE.match(cut):
        raise ValueError("pruneBefore is not a date")

    if req.get("wipe"):
        shutil.rmtree(root, ignore_errors=True)
    if writes or deletes or cut:
        ensure_dir(root)
    for rel, text in writes:
        write_atomic(root, rel, text)
    for rel in deletes:
        unlink(os.path.join(root, rel))
    if cut:
        days = os.path.join(root, "days")
        for name in os.listdir(days) if os.path.isdir(days) else []:
            if name.endswith(".json") and DATE.match(name[:-5]) and name[:-5] < cut:
                unlink(os.path.join(days, name))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # noqa: BLE001 - the service only needs the reason
        print(f"vitals_store: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
