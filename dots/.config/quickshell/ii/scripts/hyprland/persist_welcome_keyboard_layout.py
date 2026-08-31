#!/usr/bin/env python3
"""Persist the Welcome XKB choice without rewriting user-owned input settings."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import stat
import sys
import tempfile


BLOCK_START = "-- quickshell:welcome-keyboard:start"
BLOCK_END = "-- quickshell:welcome-keyboard:end"
BLOCK_PATTERN = re.compile(
    rf"^{re.escape(BLOCK_START)}\r?\n.*?^{re.escape(BLOCK_END)}(?:\r?\n|$)",
    re.MULTILINE | re.DOTALL,
)
# `hyprconfigurator.py` emitted exactly this compact, single-key shape for old
# Welcome saves. Keeping the match this narrow avoids touching an input block
# that the user owns, including a one-line block with other input settings.
LEGACY_OVERRIDE_PATTERN = re.compile(
    r'^hl\.config\(\{input=\{kb_(?:layout|variant)="[A-Za-z0-9_,-]*"\}\}\)'
    r'(?:[ \t]*--[^\r\n]*)?(?:\r?\n|$)',
    re.MULTILINE,
)
VALUE_PART_PATTERN = re.compile(r"^[A-Za-z0-9_-]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--custom-input", type=Path, required=True)
    parser.add_argument("--shell-overrides", type=Path, required=True)
    parser.add_argument("--layout", required=True)
    parser.add_argument("--variant", required=True)
    args = parser.parse_args()

    if not valid_xkb_value(args.layout, allow_empty=False):
        parser.error("--layout must be a comma-separated list of XKB codes")
    if not valid_xkb_value(args.variant, allow_empty=True):
        parser.error("--variant must contain only XKB variant codes and commas")
    return args


def valid_xkb_value(value: str, *, allow_empty: bool) -> bool:
    parts = value.split(",")
    if not allow_empty and any(not part for part in parts):
        return False
    return all(VALUE_PART_PATTERN.fullmatch(part) for part in parts)


def read_text(path: Path) -> tuple[bool, str]:
    if not path.exists():
        return False, ""
    return True, path.read_text(encoding="utf-8")


def atomic_write(path: Path, content: str, *, mode: int | None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    file_mode = mode if mode is not None else 0o644
    descriptor, temporary_path = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as file:
            file.write(content)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary_path, file_mode)
        os.replace(temporary_path, path)
    except BaseException:
        try:
            os.unlink(temporary_path)
        except FileNotFoundError:
            pass
        raise


def managed_block(layout: str, variant: str) -> str:
    return (
        f"{BLOCK_START}\n"
        f'hl.config({{ input = {{ kb_layout = "{layout}" }} }})\n'
        f'hl.config({{ input = {{ kb_variant = "{variant}" }} }})\n'
        f"{BLOCK_END}\n"
    )


def replace_managed_block(content: str, block: str) -> str:
    matches = list(BLOCK_PATTERN.finditer(content))
    if len(matches) > 1:
        raise ValueError("multiple Welcome keyboard blocks found; refusing to rewrite input.lua")
    if matches:
        return content[:matches[0].start()] + block + content[matches[0].end():]
    if not content:
        return block
    separator = "" if content.endswith(("\n", "\r")) else "\n"
    return f"{content}{separator}\n{block}"


def persist_layout(custom_input: Path, shell_overrides: Path, layout: str, variant: str) -> None:
    custom_existed, custom_content = read_text(custom_input)
    overrides_existed, overrides_content = read_text(shell_overrides)
    new_custom_content = replace_managed_block(custom_content, managed_block(layout, variant))
    new_overrides_content = LEGACY_OVERRIDE_PATTERN.sub("", overrides_content)
    custom_mode = stat.S_IMODE(custom_input.stat().st_mode) if custom_existed else None
    overrides_mode = stat.S_IMODE(shell_overrides.stat().st_mode) if overrides_existed else None

    # The custom layer is written first, so the desired value is durable before
    # its old, higher-priority override is removed. Both mutations are owned by
    # this one process, which prevents the detached-command race of the old flow.
    custom_changed = new_custom_content != custom_content
    if custom_changed:
        atomic_write(custom_input, new_custom_content, mode=custom_mode)
    try:
        if new_overrides_content != overrides_content:
            atomic_write(shell_overrides, new_overrides_content, mode=overrides_mode)
    except BaseException:
        if custom_changed:
            # Best effort rollback keeps a failed migration from silently
            # changing the effective configuration. Existing files are the
            # normal case; an absent file is left in place rather than deleting
            # a path that another process may have created concurrently.
            if custom_existed:
                atomic_write(custom_input, custom_content, mode=custom_mode)
        raise


def main() -> int:
    args = parse_args()
    try:
        persist_layout(args.custom_input, args.shell_overrides, args.layout, args.variant)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Welcome keyboard layout was not persisted: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
