#!/usr/bin/env python3
"""Collect and manage listening ports for the Port Watcher widget.

The widget only cares about *ports an application is serving on* — a dev
server, a database, a game lobby — not about the hundreds of transient
sockets a desktop opens. So this helper collapses `ss` output into one entry
per (protocol, port, owning process), counts the live connections each one is
serving, and leaves every presentation filter to QML.

`ss` remains the authority for socket state; this helper only normalizes its
output and applies strict ownership checks before process-level actions.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
from typing import Any


PROCESS_RE = re.compile(r'\("((?:\\"|[^"])*)",pid=(\d+),fd=(\d+)')
LISTENER_STATES = {"LISTEN", "UNCONN"}
ACTIVE_TCP_STATES = {
    "ESTAB",
    "SYN-RECV",
    "FIN-WAIT-1",
    "FIN-WAIT-2",
    "CLOSE-WAIT",
    "LAST-ACK",
    "CLOSING",
}
MAX_PORTS = 200
MAX_PEERS = 4
PROTECTED_PROCESSES = {
    "systemd",
    "qs",
    "quickshell",
    "Hyprland",
    "Hyprland-wrapped",
}
KNOWN_SERVICES = {
    (22, "tcp"): "SSH",
    (53, "tcp"): "DNS",
    (53, "udp"): "DNS",
    (80, "tcp"): "HTTP",
    (1716, "tcp"): "KDE Connect",
    (1716, "udp"): "KDE Connect",
    (3702, "udp"): "WS-Discovery",
    (5037, "tcp"): "ADB",
    (5353, "udp"): "mDNS",
    (6463, "tcp"): "Discord RPC",
    (6600, "tcp"): "MPD",
    (443, "tcp"): "HTTPS",
    (631, "tcp"): "Printing",
    (1313, "tcp"): "Hugo",
    (3000, "tcp"): "Dev server",
    (3306, "tcp"): "MySQL",
    (4321, "tcp"): "Astro",
    (5173, "tcp"): "Vite",
    (5432, "tcp"): "PostgreSQL",
    (6379, "tcp"): "Redis",
    (7860, "tcp"): "Gradio",
    (8000, "tcp"): "Web server",
    (8080, "tcp"): "HTTP alt",
    (8888, "tcp"): "Jupyter",
    (9000, "tcp"): "Dev server",
    (11434, "tcp"): "Ollama",
    (27017, "tcp"): "MongoDB",
}

# Runtimes people actually serve things from. Used only to label a row, never
# to hide one — hiding is a user-facing filter and lives in QML.
DEV_PROCESSES = {
    "bun",
    "cargo",
    "caddy",
    "deno",
    "dotnet",
    "esbuild",
    "flask",
    "go",
    "gunicorn",
    "http-server",
    "httpd",
    "hugo",
    "java",
    "jekyll",
    "jupyter",
    "live-server",
    "next-server",
    "nginx",
    "node",
    "npm",
    "ollama",
    "php",
    "pnpm",
    "podman",
    "python",
    "python3",
    "rails",
    "ruby",
    "serve",
    "streamlit",
    "uvicorn",
    "vite",
    "webpack",
    "yarn",
}
WEB_PORTS = {80, 443, 1313, 3000, 4200, 4321, 5000, 5173, 7860, 8000, 8080, 8081, 8888, 9000}
DATABASE_PORTS = {1521, 3306, 5432, 5984, 6379, 9200, 27017}


def emit(payload: dict[str, Any], exit_code: int = 0) -> int:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    return exit_code


def split_endpoint(endpoint: str) -> tuple[str, int | None]:
    value = endpoint.strip()
    if not value:
        return "", None

    if value.startswith("["):
        closing = value.find("]")
        if closing < 0:
            return value.strip("[]"), None
        host = value[1:closing]
        tail = value[closing + 1 :]
        if tail.startswith("%") and ":" in tail:
            zone, port_text = tail.rsplit(":", 1)
            host += zone
        elif tail.startswith(":"):
            port_text = tail[1:]
        else:
            return host, None
    elif ":" in value:
        host, port_text = value.rsplit(":", 1)
    else:
        return value, None

    try:
        return host, int(port_text)
    except ValueError:
        return host, None


def normalized_host(host: str) -> str:
    return host.split("%", 1)[0].strip("[]")


def is_loopback(host: str) -> bool:
    candidate = normalized_host(host)
    try:
        return ipaddress.ip_address(candidate).is_loopback
    except ValueError:
        return candidate in {"localhost", "ip6-localhost"}


def is_wildcard(host: str) -> bool:
    return normalized_host(host) in {"", "*", "0.0.0.0", "::"}


def read_process_identity(pid: int) -> dict[str, Any] | None:
    if pid <= 0:
        return None

    proc_dir = Path("/proc") / str(pid)
    uid = -1
    name = ""
    command = ""
    start_time = ""
    try:
        for line in (proc_dir / "status").read_text(errors="replace").splitlines():
            if line.startswith("Uid:"):
                uid = int(line.split()[1])
                break
    except (OSError, ValueError, IndexError):
        pass

    try:
        raw = (proc_dir / "cmdline").read_bytes().replace(b"\0", b" ").strip()
        command = raw.decode(errors="replace")[:320]
    except OSError:
        pass

    try:
        name = (proc_dir / "comm").read_text(errors="replace").strip()
    except OSError:
        pass

    try:
        stat_tail = (proc_dir / "stat").read_text(errors="replace").rsplit(")", 1)[1].split()
        start_time = stat_tail[19]
    except (OSError, IndexError):
        pass

    if uid < 0 or not name or not start_time:
        return None

    return {
        "uid": uid,
        "name": name,
        "command": command,
        "startTime": start_time,
    }


def process_details(pid: int) -> dict[str, Any]:
    identity = read_process_identity(pid)
    if identity is None:
        return {"uid": -1, "command": "", "canManage": False, "startTime": ""}

    return {
        "uid": identity["uid"],
        "command": identity["command"],
        "canManage": identity["uid"] == os.getuid(),
        "startTime": identity["startTime"],
    }


def service_name(port: int | None, protocol: str) -> str:
    """Only names a person would recognize.

    /etc/services is not a fallback worth having here: it answers port 1716
    with "Xmsg" and 6600 with "Mshvlm", which reads as noise next to the
    process that actually owns the port. An empty label is better than a
    wrong-looking one.
    """
    if port is None:
        return ""
    return KNOWN_SERVICES.get((port, protocol), "")


def categorize(port: int, protocol: str, process: str, owned: bool) -> str:
    """Coarse bucket used by the popup to pick an icon and an accent colour."""
    if not owned:
        return "system"
    if port in DATABASE_PORTS:
        return "database"
    if protocol == "tcp" and port in WEB_PORTS:
        return "web"
    if process.lower() in DEV_PROCESSES:
        return "dev"
    return "app"


def parse_ss_line(
    line: str,
    details_cache: dict[int, dict[str, Any]] | None = None,
) -> dict[str, Any] | None:
    parts = line.split(None, 6)
    if len(parts) < 6:
        return None

    protocol = parts[0].lower()
    if protocol not in {"tcp", "udp"}:
        return None

    state = parts[1].upper()
    if state not in LISTENER_STATES and state not in ACTIVE_TCP_STATES:
        return None

    local_endpoint = parts[4]
    remote_endpoint = parts[5]
    process_blob = parts[6] if len(parts) > 6 else ""

    processes = []
    for name, pid_text, fd_text in PROCESS_RE.findall(process_blob):
        processes.append(
            {
                "name": name.replace('\\"', '"'),
                "pid": int(pid_text),
                "fd": int(fd_text),
            }
        )

    primary = processes[0] if processes else {"name": "", "pid": 0, "fd": -1}
    pid = primary["pid"]
    if details_cache is not None:
        if pid not in details_cache:
            details_cache[pid] = process_details(pid)
        details = details_cache[pid]
    else:
        details = process_details(pid)

    local_host, local_port = split_endpoint(local_endpoint)
    remote_host, remote_port = split_endpoint(remote_endpoint)
    listener = state in LISTENER_STATES
    loopback = is_loopback(local_host)
    wildcard = is_wildcard(local_host)
    owned = details["uid"] == os.getuid() and pid > 0

    return {
        "protocol": protocol,
        "state": state,
        "kind": "listener" if listener else "connection",
        "localAddress": local_host,
        "localPort": local_port or 0,
        "localEndpoint": local_endpoint,
        "remoteAddress": remote_host,
        "remotePort": remote_port or 0,
        "remoteEndpoint": remote_endpoint,
        "process": primary["name"],
        "pid": primary["pid"],
        "command": details["command"],
        "uid": details["uid"],
        "owned": owned,
        "canManage": owned and primary["name"] not in PROTECTED_PROCESSES,
        "startTime": details["startTime"],
        "loopback": loopback,
        "wildcard": wildcard,
        "exposed": listener and (wildcard or not loopback),
    }


def collapse_ports(records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], bool]:
    """One entry per (protocol, port, pid), carrying its live connection count.

    A single server routinely shows up four times in `ss` — IPv4 plus IPv6,
    wildcard plus loopback. Those are one port to the person reading the
    widget, so they are merged here rather than padded out into four rows.
    """
    ports: dict[tuple[str, int, int], dict[str, Any]] = {}
    active: dict[tuple[str, int], list[str]] = {}

    for record in records:
        if record["kind"] == "connection":
            key = (record["protocol"], record["localPort"])
            active.setdefault(key, []).append(record["remoteEndpoint"])
            continue

        port = record["localPort"]
        if port <= 0:
            continue

        key = (record["protocol"], port, record["pid"])
        entry = ports.get(key)
        if entry is None:
            owned = record["owned"]
            process = record["process"] or ("System" if not owned else "Unknown")
            entry = {
                "id": f"{record['protocol']}:{port}:{record['pid']}",
                "protocol": record["protocol"],
                "port": port,
                "addresses": [],
                "process": process,
                "pid": record["pid"],
                "command": record["command"],
                "uid": record["uid"],
                "owned": owned,
                "canManage": record["canManage"],
                "startTime": record["startTime"],
                "service": service_name(port, record["protocol"]),
                "category": categorize(port, record["protocol"], process, owned),
                "exposed": False,
                "loopback": True,
                "connections": 0,
                "peers": [],
            }
            ports[key] = entry

        address = normalized_host(record["localAddress"])
        if address and address not in entry["addresses"]:
            entry["addresses"].append(address)
        if record["exposed"]:
            entry["exposed"] = True
        if not record["loopback"]:
            entry["loopback"] = False

    truncated = False
    for entry in ports.values():
        peers = active.get((entry["protocol"], entry["port"]), [])
        entry["connections"] = len(peers)
        entry["peers"] = sorted(set(peers))[:MAX_PEERS]

    result = sorted(
        ports.values(),
        key=lambda item: (0 if item["owned"] else 1, item["port"], item["protocol"]),
    )
    if len(result) > MAX_PORTS:
        result = result[:MAX_PORTS]
        truncated = True
    return result, truncated


def scan() -> int:
    if not shutil.which("ss"):
        return emit(
            {
                "ok": False,
                "error": "The ss utility from iproute2 is not available.",
                "ports": [],
            },
            1,
        )

    try:
        completed = subprocess.run(
            ["ss", "-H", "-n", "-a", "-t", "-u", "-p"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
            env={**os.environ, "LANG": "C", "LC_ALL": "C"},
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return emit({"ok": False, "error": str(error), "ports": []}, 1)

    records = []
    details_cache: dict[int, dict[str, Any]] = {}
    for line in completed.stdout.splitlines():
        parsed = parse_ss_line(line, details_cache)
        if parsed is not None:
            records.append(parsed)

    ports, truncated = collapse_ports(records)
    warning = completed.stderr.strip()
    return emit(
        {
            "ok": completed.returncode == 0 or bool(ports),
            "error": "" if completed.returncode == 0 else warning or "ss returned an error",
            "warning": warning if completed.returncode == 0 else "",
            "ports": ports,
            "truncated": truncated,
            "limit": MAX_PORTS,
        },
        0 if completed.returncode == 0 or ports else 1,
    )


def owned_process(
    pid: int,
    expected_start_time: str = "",
    expected_name: str = "",
) -> tuple[bool, str, str]:
    if pid <= 1:
        return False, "Invalid process id.", ""

    identity = read_process_identity(pid)
    if identity is None:
        return False, "Could not verify process ownership.", ""

    process_name = identity["name"]
    if identity["uid"] != os.getuid():
        return False, "Only processes owned by the current user can be stopped.", process_name
    if ((expected_start_time and identity["startTime"] != expected_start_time)
            or (expected_name and process_name != expected_name)):
        return False, "The process identity changed since the last scan. Refresh and try again.", process_name
    if process_name in PROTECTED_PROCESSES:
        return False, f"{process_name} is protected from Port Watcher actions.", process_name
    return True, "", process_name


def stop_process(pid: int, force: bool, expected_start_time: str, expected_name: str) -> int:
    if not expected_start_time or not expected_name:
        return emit({"ok": False, "error": "Process identity is missing. Refresh and try again."}, 1)

    pidfd = None
    if hasattr(os, "pidfd_open"):
        try:
            pidfd = os.pidfd_open(pid)
        except ProcessLookupError:
            return emit({"ok": True, "message": "The process already stopped."})
        except OSError as error_value:
            return emit({"ok": False, "error": str(error_value)}, 1)

    try:
        allowed, error, process_name = owned_process(pid, expected_start_time, expected_name)
        if not allowed:
            return emit({"ok": False, "error": error}, 1)

        sig = signal.SIGKILL if force else signal.SIGTERM
        if pidfd is not None and hasattr(signal, "pidfd_send_signal"):
            signal.pidfd_send_signal(pidfd, sig, None, 0)
        else:
            os.kill(pid, sig)
    except ProcessLookupError:
        return emit({"ok": True, "message": "The process already stopped."})
    except PermissionError:
        return emit({"ok": False, "error": "Permission denied while stopping the process."}, 1)
    except OSError as error_value:
        return emit({"ok": False, "error": str(error_value)}, 1)
    finally:
        if pidfd is not None:
            os.close(pidfd)

    if force:
        return emit({"ok": True, "message": f"Force-stopped {process_name} (PID {pid})."})
    return emit({"ok": True, "message": f"Asked {process_name} (PID {pid}) to stop."})


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Port Watcher backend")
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--scan", action="store_true")
    actions.add_argument("--stop-process", action="store_true")
    actions.add_argument("--force-stop-process", action="store_true")
    parser.add_argument("--pid", type=int, default=0)
    parser.add_argument("--start-time", default="")
    parser.add_argument("--process-name", default="")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.scan:
        return scan()
    return stop_process(args.pid, args.force_stop_process, args.start_time, args.process_name)


if __name__ == "__main__":
    sys.exit(main())
