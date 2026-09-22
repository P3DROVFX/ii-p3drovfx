#!/usr/bin/env python3
"""Report which applications are currently using the camera, the microphone,
the screen or the location service.

Runs as a long-lived bridge rather than a one-shot: the privacy pill has to
appear the moment an access starts. One JSON line is written to stdout
whenever the picture changes, and nothing at all while it doesn't.

It is event-driven and sleeps while nothing happens. PipeWire is followed
through one long-lived `pw-dump --monitor` instead of a full graph dump per
tick (~600 KB of JSON to parse every second), and the /proc fd walk for the
camera only runs when inotify sees a capture node opened or closed. Only
location, and the camera while something holds it, still poll at --interval.

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
import ctypes
import json
import os
from pathlib import Path
import select
import signal
import struct
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
IGNORED_PROCESSES = {"qs", "quickshell", "cava", "pipewire", "wireplumber",
                     # Camera relays (IPU6/IPU7 laptops) keep their v4l2loopback node
                     # open for the whole session as its producer, and start the real
                     # sensor only once something reads the node - that reader is the
                     # app to report. `comm` is cut to 15 characters.
                     "camera-relay-mo", "camera-relay-gs"}


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
    return streams_from_objects(objects)


def streams_from_objects(objects: Any) -> list[dict[str, Any]]:
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


PR_SET_PDEATHSIG = 1


def _die_with_parent() -> None:
    """Runs in the child before exec. The shell gives this probe a parent-death
    signal, but fork clears it, so without its own the monitor would outlive a
    killed probe - and at idle it never writes, so no SIGPIPE ever ends it."""
    try:
        ctypes.CDLL(None, use_errno=True).prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except (OSError, AttributeError):
        pass


class PipewireMonitor:
    """Mirror of the PipeWire nodes, kept current by `pw-dump --monitor`.

    The monitor prints the full graph once, then one JSON array per change in
    which every changed object is repeated whole; a removed object comes back
    as a bare {"id": N, "info": null}. Each array opens with a "[" line and
    closes with a "]" line at column 0, which is how they are split apart.
    """

    RESPAWN_MIN = 1.0
    RESPAWN_MAX = 30.0

    def __init__(self) -> None:
        self.proc: subprocess.Popen[bytes] | None = None
        self.nodes: dict[int, dict[str, Any]] = {}
        self.ready = False
        self._partial = b""
        self._lines: list[bytes] = []
        self._respawn_at = 0.0
        self._backoff = self.RESPAWN_MIN

    def fileno(self) -> int | None:
        return self.proc.stdout.fileno() if self.proc and self.proc.stdout else None

    def respawn_due(self, now: float) -> float | None:
        return None if self.proc else self._respawn_at

    def start(self, now: float) -> None:
        if self.proc or now < self._respawn_at:
            return
        try:
            self.proc = subprocess.Popen(
                ["pw-dump", "--monitor", "--no-colors"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                env={**os.environ, "LANG": "C", "LC_ALL": "C"},
                preexec_fn=_die_with_parent,
            )
        except OSError:
            self._schedule_respawn(now)
            return
        os.set_blocking(self.proc.stdout.fileno(), False)

    def _schedule_respawn(self, now: float) -> None:
        self._respawn_at = now + self._backoff
        self._backoff = min(self.RESPAWN_MAX, self._backoff * 2)

    def stop(self) -> None:
        if self.proc:
            self.proc.kill()
            self.proc.wait()
        self.proc = None

    def read(self, now: float) -> bool:
        """Drain stdout. Returns True when a node may have changed."""
        if not self.proc or not self.proc.stdout:
            return False
        changed = False
        while True:
            try:
                chunk = os.read(self.proc.stdout.fileno(), 262144)
            except BlockingIOError:
                break
            if not chunk:
                # PipeWire went away (restart, logout). Drop the mirror: a
                # stale "microphone in use" is worse than a brief blank.
                self.stop()
                self.nodes.clear()
                self.ready = False
                self._partial = b""
                self._lines = []
                self._schedule_respawn(now)
                return True
            changed |= self._feed(chunk)
        return changed

    def _feed(self, chunk: bytes) -> bool:
        data = self._partial + chunk
        *lines, self._partial = data.split(b"\n")
        changed = False
        for line in lines:
            self._lines.append(line)
            if line.rstrip() != b"]":
                continue
            text = b"\n".join(self._lines)
            self._lines = []
            try:
                objects = json.loads(text)
            except ValueError:
                continue
            changed |= self._apply(objects)
        return changed

    def _apply(self, objects: Any) -> bool:
        if not isinstance(objects, list):
            return False
        changed = not self.ready
        self.ready = True
        self._backoff = self.RESPAWN_MIN
        for obj in objects:
            if not isinstance(obj, dict) or "id" not in obj:
                continue
            node_id = obj["id"]
            if "type" not in obj and obj.get("info") is None:
                changed |= self.nodes.pop(node_id, None) is not None
            elif obj.get("type") == "PipeWire:Interface:Node":
                self.nodes[node_id] = obj
                changed = True
        return changed

    def streams(self) -> list[dict[str, Any]]:
        return streams_from_objects(self.nodes.values())


class NodeWatch:
    """inotify on the capture nodes: an open or a close is the only moment
    who-holds-the-camera can change, so the /proc walk runs only then.

    Opening a node is not the same as using it, though: Discord's
    VideoDevicePoll thread opens and closes every /dev/video* twice a second
    to enumerate cameras. Every open is eventually followed by exactly one
    close, so each node's net count (opens minus closes) only differs from
    what it was at the last walk when someone kept a node open or let one go.
    """

    IN_CLOSE_WRITE = 0x08
    IN_CLOSE_NOWRITE = 0x10
    IN_OPEN = 0x20
    IN_Q_OVERFLOW = 0x4000
    EVENT = struct.Struct("iIII")

    def __init__(self) -> None:
        self.fd: int | None = None
        self.complete = False
        self.net: dict[int, int] = {}
        self._baseline: dict[int, int] = {}
        self._overflowed = False
        try:
            self._libc = ctypes.CDLL(None, use_errno=True)
            fd = self._libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        except (OSError, AttributeError):
            return
        if fd >= 0:
            self.fd = fd

    def watch(self, nodes: dict[str, str]) -> None:
        """(Re)watch every node. `complete` is False when any node could not
        be watched, and the caller then falls back to polling."""
        if self.fd is None:
            self.complete = False
            return
        mask = self.IN_OPEN | self.IN_CLOSE_WRITE | self.IN_CLOSE_NOWRITE
        ok = True
        # Re-adding a watched inode just returns its existing watch.
        for node in nodes:
            if self._libc.inotify_add_watch(self.fd, node.encode(), mask) < 0:
                ok = False
        self.complete = ok

    def drain(self) -> bool:
        if self.fd is None:
            return False
        fired = False
        while True:
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                break
            if not data:
                break
            fired = True
            self._count(data)
        return fired

    def _count(self, data: bytes) -> None:
        offset = 0
        while offset + self.EVENT.size <= len(data):
            wd, mask, _cookie, name_len = self.EVENT.unpack_from(data, offset)
            offset += self.EVENT.size + name_len
            if mask & self.IN_Q_OVERFLOW:
                self._overflowed = True
            elif mask & self.IN_OPEN:
                self.net[wd] = self.net.get(wd, 0) + 1
            elif mask & (self.IN_CLOSE_WRITE | self.IN_CLOSE_NOWRITE):
                self.net[wd] = self.net.get(wd, 0) - 1

    def moved(self) -> bool:
        """True when some node is held by more or fewer files than at the last
        walk, or when events were lost and the counts can't be trusted."""
        if self._overflowed:
            return True
        return any(count != self._baseline.get(wd, 0) for wd, count in self.net.items())

    def mark_walked(self) -> None:
        self._overflowed = False
        self._baseline = dict(self.net)


def collect(
    kinds: set[str],
    nodes: dict[str, str],
    streams: list[dict[str, Any]] | None = None,
    cameras: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    if {"camera", "microphone", "screen"} & kinds:
        items.extend(pipewire_streams() if streams is None else streams)
    if "camera" in kinds:
        items.extend(camera_users(nodes) if cameras is None else cameras)
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
    if args.once:
        emit(collect(kinds, nodes), None)
        return 0
    return run(kinds, nodes, interval)


def emit(items: list[dict[str, Any]], last: str | None) -> str:
    payload = {"ok": True, "items": items}
    serialized = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
    if serialized != last:
        print(serialized, flush=True)
    return serialized


# A burst of graph changes (a stream linking up is ~15 arrays over ~100 ms)
# is read as one: the picture is taken once it settles, so a stream that is
# running for a blink doesn't flash the pill any more than polling did.
SETTLE = 0.25
# Once a node event arrives the inotify fd is left alone this long, so a
# burst (a camera app opening several nodes, Discord sweeping all of them)
# queues up in the kernel and is read in one wake instead of dozens.
CAMERA_SETTLE = 0.4
RESCAN_EVERY = 30.0


def run(kinds: set[str], nodes: dict[str, str], interval: float) -> int:
    watch_pw = bool({"camera", "microphone", "screen"} & kinds)
    watch_camera = "camera" in kinds
    poll_location = "location" in kinds

    monitor = PipewireMonitor() if watch_pw else None
    node_watch = NodeWatch() if watch_camera else None
    if node_watch:
        node_watch.watch(nodes)

    now = time.monotonic()
    if monitor:
        monitor.start(now)
    cameras = camera_users(nodes) if watch_camera else []
    camera_due: float | None = None
    camera_forced = False
    if node_watch:
        node_watch.mark_walked()
    rescan_at = now + RESCAN_EVERY
    poll_at = now + interval
    # Held back until the first dump is read, but always sent: QML expects a
    # first payload even when PipeWire is missing.
    emit_at: float | None = now
    last: str | None = None

    while True:
        now = time.monotonic()
        # Polling survives only where no event exists: location (GeoClue's
        # flag), a camera held right now (a holder can fork or hand its fd
        # over without an open), and nodes inotify could not watch.
        camera_poll = watch_camera and (bool(cameras) or not (node_watch and node_watch.complete))
        polling = poll_location or camera_poll

        deadlines = [rescan_at]
        if polling:
            deadlines.append(poll_at)
        if emit_at is not None:
            deadlines.append(emit_at)
        if camera_due is not None:
            deadlines.append(camera_due)
        if monitor and (respawn := monitor.respawn_due(now)) is not None:
            deadlines.append(respawn)

        fds = []
        if monitor and monitor.fileno() is not None:
            fds.append(monitor.fileno())
        if node_watch and node_watch.fd is not None and camera_due is None:
            fds.append(node_watch.fd)
        timeout = max(0.0, min(deadlines) - now)
        try:
            ready, _, _ = select.select(fds, [], [], timeout)
        except InterruptedError:
            continue
        now = time.monotonic()

        if monitor:
            if monitor.fileno() in ready and monitor.read(now) and emit_at is None:
                emit_at = now + SETTLE
            if monitor.proc is None:
                monitor.start(now)
        if node_watch and node_watch.fd in ready and node_watch.drain():
            camera_due = now + CAMERA_SETTLE

        if now >= rescan_at:
            # A webcam can be plugged in while the shell runs; the walk also
            # backs up inotify for anything it cannot see.
            nodes = video_capture_nodes()
            if node_watch:
                node_watch.watch(nodes)
            if watch_camera:
                camera_forced = True
                camera_due = now
            rescan_at = now + RESCAN_EVERY

        if polling and now >= poll_at:
            if camera_poll:
                camera_forced = True
                camera_due = now
            poll_at = now + interval
            if emit_at is None:
                emit_at = now

        if camera_due is not None and now >= camera_due:
            camera_due = None
            if node_watch:
                node_watch.drain()
            # Mere enumeration (open then close) leaves every count where it
            # was, and needs no walk.
            if camera_forced or (node_watch and node_watch.moved()):
                camera_forced = False
                if node_watch:
                    node_watch.mark_walked()
                fresh = camera_users(nodes)
                if fresh != cameras:
                    cameras = fresh
                    emit_at = now if emit_at is None else emit_at
                if cameras and poll_at < now:
                    poll_at = now + interval

        if emit_at is not None and now >= emit_at:
            emit_at = None
            if monitor and not monitor.ready and monitor.proc is not None:
                # Still reading the first dump; don't report "nothing" early.
                emit_at = now + SETTLE
                continue
            streams = monitor.streams() if monitor else []
            last = emit(collect(kinds, nodes, streams, cameras), last)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
