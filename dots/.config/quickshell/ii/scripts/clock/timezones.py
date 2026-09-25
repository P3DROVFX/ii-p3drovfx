#!/usr/bin/env python3
"""UTC offsets for the clock app and the bar's world clocks.

With zone names as arguments it reports only those; without, the whole IANA
catalog the timezone picker searches. One process answers either question, so
the shell never spawns one `date` per city.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone

try:
    from zoneinfo import ZoneInfo, available_timezones
except ImportError:  # Python < 3.9
    print(json.dumps({"local": "", "zones": []}))
    sys.exit(0)

SKIPPED_PREFIXES = ("Etc/", "SystemV/", "posix/", "right/", "US/", "Canada/", "Brazil/", "Mexico/", "Chile/")


def local_zone() -> str:
    env = os.environ.get("TZ", "").lstrip(":")
    if env and "/" in env:
        return env
    try:
        target = os.path.realpath("/etc/localtime")
    except OSError:
        return ""
    marker = "zoneinfo/"
    index = target.find(marker)
    return target[index + len(marker):] if index >= 0 else ""


def describe(name: str, now: datetime) -> dict | None:
    try:
        local = now.astimezone(ZoneInfo(name))
    except Exception:
        return None
    offset = local.utcoffset()
    return {
        "tz": name,
        "offset": int(offset.total_seconds() // 60) if offset is not None else 0,
        "abbr": local.tzname() or "",
    }


def main() -> None:
    now = datetime.now(timezone.utc)
    names = sys.argv[1:]
    if not names:
        names = sorted(
            zone for zone in available_timezones()
            if "/" in zone and not zone.startswith(SKIPPED_PREFIXES)
        )
    zones = [entry for entry in (describe(name, now) for name in names) if entry]
    print(json.dumps({"local": local_zone(), "zones": zones}))


if __name__ == "__main__":
    main()
