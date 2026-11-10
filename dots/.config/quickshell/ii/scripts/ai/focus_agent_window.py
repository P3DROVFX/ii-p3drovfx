#!/usr/bin/env python3
"""Bring the window an agent CLI is running in to the front.

Usage: focus_agent_window.py <pid>

A CLI has no window of its own: it runs under a shell, under a terminal, and the
terminal is the Hyprland client. So the pid's ancestors are walked until one of them
owns a window, and that window is focused - which also switches to its workspace.

A terminal running several windows from one process (kitty --single-instance) gives
every one of them the same pid. The CLI sets its window's title, so a title naming the
agent breaks the tie; failing that the first window wins, which is at least the right
application.
"""

import json
import subprocess
import sys


def read_ppid(pid, proc_root="/proc"):
    try:
        with open("%s/%d/stat" % (proc_root, pid), "r") as handle:
            # comm may hold spaces and parentheses; the fields resume after the last ')'.
            return int(handle.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def ancestry(pid, proc_root="/proc"):
    """The pid and every ancestor below init, nearest first."""
    chain = []
    while pid > 1 and pid not in chain:
        chain.append(pid)
        pid = read_ppid(pid, proc_root)
    return chain


def pick_window(chain, clients, hints=()):
    """The client owned by the nearest ancestor that has one, or None."""
    for pid in chain:
        owned = [client for client in clients if int(client.get("pid") or 0) == pid]
        if not owned:
            continue
        for hint in hints:
            for client in owned:
                if hint and hint.lower() in str(client.get("title") or "").lower():
                    return client
        return owned[0]
    return None


def hyprctl(*args):
    try:
        done = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.strip()


def focus(address):
    # A Lua config evaluates the dispatch payload as Lua, where the classic form is a
    # syntax error - and hyprctl exits 0 either way, so only the reply tells.
    if hyprctl("dispatch", "focuswindow", "address:%s" % address).lower() == "ok":
        return True
    reply = hyprctl("dispatch", 'hl.dsp.focus{window="address:%s"}' % address)
    return reply.lower() == "ok"


def main(argv):
    try:
        pid = int(argv[1])
    except (IndexError, ValueError):
        return 2
    try:
        clients = json.loads(hyprctl("clients", "-j") or "[]")
    except ValueError:
        return 1
    window = pick_window(ancestry(pid), clients, hints=argv[2:])
    if not window or not window.get("address"):
        return 1
    return 0 if focus(window["address"]) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
