#!/usr/bin/env python3
"""Ensure a local-only khal calendar exists when the user has khal installed
but has not configured any calendar or cloud sync yet.

Never overwrites an existing khal config.
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path


def main() -> int:
    if shutil.which("khal") is None:
        return 1

    xdg_config = Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser()
    xdg_data = Path(os.environ.get("XDG_DATA_HOME", "~/.local/share")).expanduser()
    config_file = xdg_config / "khal" / "config"

    if config_file.exists():
        # User already has a khal config; do not touch it.
        return 0

    local_cal_dir = xdg_data / "khal" / "calendars" / "local"
    local_cal_dir.mkdir(parents=True, exist_ok=True)
    config_file.parent.mkdir(parents=True, exist_ok=True)

    config_text = f"""[calendars]

[[local]]
path = {local_cal_dir}
type = calendar

[default]
default_calendar = local
"""
    config_file.write_text(config_text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
