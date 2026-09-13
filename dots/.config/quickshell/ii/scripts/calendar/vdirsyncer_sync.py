#!/usr/bin/env python3
"""Run the vdirsyncer pair that owns one writable khal calendar.

The timetable must not let an unrelated, read-only Google collection abort a
write to the calendar where the user actually created an event.  This bridge
maps khal's local calendar directory to the matching filesystem storage in
vdirsyncer's config, then synchronizes that collection only.  If no mapping is
available it deliberately falls back to vdirsyncer's normal all-pairs sync.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from khal.settings import get_config


def _path_prefix(value: object) -> Path:
    """Expand a filesystem pattern and keep its non-glob directory prefix."""
    raw = os.path.expanduser(str(value or ""))
    for marker in ("*", "?", "["):
        if marker in raw:
            raw = raw.split(marker, 1)[0]
    return Path(raw).resolve()


def default_vdirsyncer_config() -> Path | None:
    configured = os.environ.get("VDIRSYNCER_CONFIG", "").strip()
    candidates = [
        Path(configured).expanduser() if configured else None,
        Path(os.environ.get("XDG_CONFIG_HOME", "~/.config")).expanduser() / "vdirsyncer" / "config",
        Path("~/.vdirsyncer/config").expanduser(),
    ]
    return next((candidate for candidate in candidates if candidate is not None and candidate.is_file()), None)


def calendar_path(calendar: str, khal_config_path: str | None = None) -> Path | None:
    config = get_config(khal_config_path)
    source = config.get("calendars", {}).get(calendar, {})
    path = source.get("path") if isinstance(source, dict) else ""
    return _path_prefix(path) if path else None


def vdirsyncer_sections(path: Path) -> dict[str, dict[str, str]]:
    """Read the small INI subset required for pair/storage discovery.

    vdirsyncer accepts values such as ``["from a", "from b"]`` that ConfigObj
    rightfully rejects, but this bridge only needs scalar ``a``, ``b``, ``type``
    and ``path`` fields.  Keeping the parser narrow also avoids interpreting any
    credential setting.
    """
    sections: dict[str, dict[str, str]] = {}
    current: dict[str, str] | None = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = sections.setdefault(line[1:-1].strip(), {})
            continue
        if current is None or "=" not in line:
            continue
        key, value = line.split("=", 1)
        current[key.strip()] = value.strip().strip('"').strip("'")
    return sections


def resolve_target(calendar: str, calendar_root: Path | None, vdirsyncer_config_path: Path | None) -> str:
    """Return ``pair/collection`` when its filesystem storage owns the path."""
    if not calendar or calendar_root is None or vdirsyncer_config_path is None:
        return ""
    config = vdirsyncer_sections(vdirsyncer_config_path)
    for section, pair in config.items():
        if not section.startswith("pair "):
            continue
        pair_name = section.removeprefix("pair ").strip()
        for side in ("a", "b"):
            storage_name = str(pair.get(side, "")).strip()
            storage = config.get("storage " + storage_name, {})
            if str(storage.get("type", "")).strip() != "filesystem":
                continue
            storage_path = storage.get("path", "")
            if not storage_path:
                continue
            local_root = _path_prefix(storage_path)
            try:
                calendar_root.relative_to(local_root)
            except ValueError:
                continue
            return pair_name + "/" + calendar
    return ""


def sync_request(request: dict[str, Any]) -> dict[str, Any]:
    calendar = str(request.get("calendar") or "").strip()
    khal_config_path = str(request.get("khalConfig") or "").strip() or None
    vdirsyncer_config_path = str(request.get("vdirsyncerConfig") or "").strip()
    config_path = Path(vdirsyncer_config_path).expanduser() if vdirsyncer_config_path else default_vdirsyncer_config()
    target = resolve_target(calendar, calendar_path(calendar, khal_config_path) if calendar else None, config_path)
    command = ["vdirsyncer", "sync"] + ([target] if target else [])
    completed = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    output = (completed.stderr.strip() or completed.stdout.strip())[-4000:]
    return {
        "ok": completed.returncode == 0,
        "calendar": calendar,
        "target": target,
        "error": output,
    }


def main() -> int:
    try:
        request = json.loads(sys.stdin.readline())
        if not isinstance(request, dict):
            raise ValueError("Sync request must be an object.")
        reply = sync_request(request)
    except Exception as error:
        reply = {"ok": False, "error": str(error)}
    print(json.dumps(reply, separators=(",", ":")))
    return 0 if reply.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
