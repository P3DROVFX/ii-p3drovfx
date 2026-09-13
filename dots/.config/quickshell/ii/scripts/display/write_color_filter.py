#!/usr/bin/env python3
"""Atomically publish one generated display-color shader to multiple paths."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import tempfile


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
        text=True,
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", action="append", required=True)
    args = parser.parse_args()

    shader_source = sys.stdin.read()
    if not shader_source.strip():
        print("display color shader source is empty", file=sys.stderr)
        return 2

    for output in args.output:
        atomic_write(Path(output).expanduser(), shader_source)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
