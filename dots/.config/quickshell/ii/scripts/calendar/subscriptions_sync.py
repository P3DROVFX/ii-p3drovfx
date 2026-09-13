#!/usr/bin/env python3
"""Discover and synchronize only the II-managed timetable subscription pairs.

Two vdirsyncer behaviours make a bare ``vdirsyncer sync`` unusable here: a pair
that has never been discovered is refused outright, and a missing binary makes
the QML ``Process`` fail before it can report an exit code, which would leave
the UI spinning forever.  Both steps therefore run from this bridge so that
every outcome comes back as one readable JSON reply.

Only the pair names II itself generated are ever touched, so a user-owned
CalDAV pair is never discovered, prompted for or synchronized as a side effect.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from typing import Any


PAIR_NAME = re.compile(r"^[A-Za-z0-9_.-]+$")
DISCOVER_TIMEOUT_SECONDS = 60
SYNC_TIMEOUT_SECONDS = 180
MISSING_BINARY_ERROR = "vdirsyncer is not installed. Install it to synchronize subscribed calendars."


def _pair_names(request: dict[str, Any]) -> list[str]:
    raw = request.get("pairs") or []
    if not isinstance(raw, list):
        raise ValueError("Sync request must carry a list of pairs.")
    names: list[str] = []
    for item in raw:
        name = str(item or "").strip()
        if not name:
            continue
        if not PAIR_NAME.match(name):
            raise ValueError(f"Unsupported calendar pair name: {name}")
        if name not in names:
            names.append(name)
    return names


def _run(command: list[str], timeout: int) -> tuple[bool, str]:
    """Run one vdirsyncer step, answering its collection prompts with yes."""
    try:
        completed = subprocess.run(
            command,
            input="y\n" * 32,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False, f"{command[1]} timed out after {timeout} s."
    except OSError as error:
        return False, str(error)
    if completed.returncode == 0:
        return True, ""
    return False, (completed.stderr.strip() or completed.stdout.strip())[-2000:]


def sync_request(request: dict[str, Any]) -> dict[str, Any]:
    pairs = _pair_names(request)
    if not pairs:
        return {"ok": True, "pairs": []}
    if shutil.which("vdirsyncer") is None:
        return {"ok": False, "pairs": pairs, "error": MISSING_BINARY_ERROR}

    synced: list[str] = []
    errors: list[str] = []
    for pair in pairs:
        ok, error = _run(["vdirsyncer", "discover", pair], DISCOVER_TIMEOUT_SECONDS)
        if ok:
            ok, error = _run(["vdirsyncer", "sync", pair], SYNC_TIMEOUT_SECONDS)
        if ok:
            synced.append(pair)
        else:
            errors.append(error or f"vdirsyncer could not synchronize {pair}.")
    return {
        "ok": not errors,
        "pairs": synced,
        "error": "\n".join(errors),
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
