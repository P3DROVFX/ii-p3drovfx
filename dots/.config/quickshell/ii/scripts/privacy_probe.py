#!/usr/bin/env python3
"""Report which applications are currently using the camera, the microphone,
the screen or the location service.

Runs as a long-lived bridge rather than a one-shot: the privacy pill has to
appear the moment an access starts, and spawning a process every second to
find that out would cost more than the polling does. One JSON line is written
to stdout whenever the picture changes, and nothing at all while it doesn't.

Sources, per kind:
  camera      /proc/<pid>/fd symlinks pointing at a V4L2 capture node. Apps
              reach the webcam through V4L2 directly far more often than
              through PipeWire, and this also names the process holding it.
  microphone  PipeWire nodes with media.class Stream/Input/Audio, running.
  screen      PipeWire nodes with media.class Stream/Input/Video carrying the
              Screen media.role, which is what the desktop portal sets.
  location    GeoClue2's Manager.InUse property. GeoClue exposes no readable
              client list, so this one is a yes/no with no app name.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any


SYS_V4L = Path("/sys/class/video4linux")
PROC = Path("/proc")

# Drivers behind /dev/video* nodes that are codecs, not cameras. A browser
# doing hardware video decoding opens one of these, and calling that "camera
# in use" would be a lie the user cannot dismiss.
CODEC_DRIVERS = {
    "amdgpu",
    "bcm2835-codec",
    "hantro-vpu",
    "mtk-vcodec",
    "rkvdec",
    "v4l2-mem2mem",
    "venus",
    "vim2m",
    "visl",
}
CODEC_NAME_HINTS = ("codec", "decoder", "encoder", "stateless", "-dec", "-enc")

# Nodes the shell itself owns. Reporting our own audio analysis as "an app is
# listening to you" would be noise the user cannot act on.
IGNORED_PROCESSES = {"qs", "quickshell", "cava", "pipewire", "wireplumber"}


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace").strip()
    except OSError:
        return ""


def video_capture_nodes() -> dict[str, str]:
    """Map /dev/videoN -> human label, for nodes that can actually capture."""
    nodes: dict[str, str] = {}
    try:
        entries = sorted(SYS_V4L.iterdir())
    except OSError:
        return nodes

    for entry in entries:
        if not entry.name.startswith("video"):
            continue
        label = read_text(entry / "name") or entry.name
        driver = ""
        try:
            driver = os.path.basename(os.path.realpath(entry / "device" / "driver"))
        except OSError:
            pass
        lowered = label.lower()
        if driver in CODEC_DRIVERS:
            continue
        if any(hint in lowered for hint in CODEC_NAME_HINTS):
            continue
        nodes[f"/dev/{entry.name}"] = label.split(":", 1)[0].replace("_", " ").strip() or entry.name
    return nodes


def process_name(pid: str) -> str:
    return read_text(PROC / pid / "comm")


def camera_users(nodes: dict[str, str]) -> list[dict[str, Any]]:
    if not nodes:
        return []

    found: dict[tuple[int, str], dict[str, Any]] = {}
    for entry in PROC.iterdir():
        if not entry.name.isdigit():
            continue
        fd_dir = entry / "fd"
        try:
            handles = list(fd_dir.iterdir())
        except OSError:
            # Not ours, or gone between listing and opening. Both are normal.
            continue
        for handle in handles:
            try:
                target = os.readlink(handle)
            except OSError:
                continue
            if target not in nodes:
                continue
            name = process_name(entry.name)
            if not name or name in IGNORED_PROCESSES:
                continue
            key = (int(entry.name), target)
            found[key] = {
                "kind": "camera",
                "app": name,
                "pid": int(entry.name),
                "detail": nodes[target],
            }
    return list(found.values())


def pipewire_streams() -> list[dict[str, Any]]:
    try:
        completed = subprocess.run(
            ["pw-dump"],
            check=False,
            capture_output=True,
            text=True,
            timeout=4,
            env={**os.environ, "LANG": "C", "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if completed.returncode != 0 or not completed.stdout.strip():
        return []
    try:
        objects = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return []

    streams: list[dict[str, Any]] = []
    for obj in objects:
        info = obj.get("info") or {}
        props = info.get("props") or {}
        media_class = str(props.get("media.class") or "")
        if info.get("state") != "running":
            continue

        if media_class.startswith("Stream/Input/Audio"):
            kind = "microphone"
        elif media_class.startswith("Stream/Input/Video"):
            kind = "screen" if props.get("media.role") == "Screen" else "camera"
        else:
            continue

        binary = str(props.get("application.process.binary") or "")
        app = str(
            props.get("application.name")
            or binary
            or props.get("node.description")
            or props.get("node.name")
            or ""
        ).strip()
        if not app or app in IGNORED_PROCESSES or binary in IGNORED_PROCESSES:
            continue

        pid = props.get("application.process.id")
        streams.append(
            {
                "kind": kind,
                "app": app,
                "pid": int(pid) if isinstance(pid, int) else 0,
                "detail": str(props.get("node.description") or props.get("node.name") or ""),
            }
        )
    return streams


def location_in_use() -> list[dict[str, Any]]:
    try:
        completed = subprocess.run(
            [
                "busctl",
                "--system",
                "get-property",
                "org.freedesktop.GeoClue2",
                "/org/freedesktop/GeoClue2/Manager",
                "org.freedesktop.GeoClue2.Manager",
                "InUse",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=4,
        )
    except (OSError, subprocess.TimeoutExpired):
        return []
    if completed.returncode != 0 or completed.stdout.strip() != "b true":
        return []
    # GeoClue keeps no publicly readable client list, so the app stays unnamed.
    return [{"kind": "location", "app": "", "pid": 0, "detail": ""}]


def collect(kinds: set[str], nodes: dict[str, str]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    if {"camera", "microphone", "screen"} & kinds:
        items.extend(pipewire_streams())
    if "camera" in kinds:
        items.extend(camera_users(nodes))
    if "location" in kinds:
        items.extend(location_in_use())

    deduped: dict[tuple[str, str, int], dict[str, Any]] = {}
    for item in items:
        if item["kind"] not in kinds:
            continue
        deduped[(item["kind"], item["app"].lower(), item["pid"])] = item
    return sorted(deduped.values(), key=lambda item: (item["kind"], item["app"].lower()))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Privacy indicator probe")
    parser.add_argument("--interval", type=float, default=1.2)
    parser.add_argument(
        "--kinds",
        default="camera,microphone,screen",
        help="Comma separated: camera, microphone, screen, location",
    )
    parser.add_argument("--once", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    kinds = {part.strip() for part in args.kinds.split(",") if part.strip()}
    interval = max(0.4, args.interval)

    nodes = video_capture_nodes()
    rescan_at = time.monotonic() + 30
    last = None

    while True:
        now = time.monotonic()
        if now >= rescan_at:
            # A webcam can be plugged in while the shell runs.
            nodes = video_capture_nodes()
            rescan_at = now + 30

        items = collect(kinds, nodes)
        payload = {"ok": True, "items": items}
        serialized = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        if serialized != last:
            last = serialized
            print(serialized, flush=True)

        if args.once:
            return 0
        time.sleep(interval)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
