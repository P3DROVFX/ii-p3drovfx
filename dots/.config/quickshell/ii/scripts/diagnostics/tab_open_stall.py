#!/usr/bin/env python3
"""Measure the main-thread stall a cheatsheet tab click causes in the live shell.

A page is built on the click, on the QML/GUI thread, so the metric that matches
what the user feels is how long that thread stays busy without interruption.
This samples `/proc/<pid>/task/<pid>/stat` (the leader thread is the QML thread)
every 10 ms, fires one `qs ipc -c ii call cheatsheet openTab <tab>`, and reports
the longest contiguous busy stretch.

Manual and opt-in on purpose: it does nothing until invoked, starts no sampler,
and only touches the shell through the same IPC a keyboard shortcut uses. Both
the measured tab and a light reference tab are opened once and closed before the
measurement, because QML compilation is cached per engine generation — measuring
the first open after a reload measures the compiler instead of the page.

Usage:
  python3 scripts/diagnostics/tab_open_stall.py --pid "$(pgrep -x qs | head -1)" --tab timetable
"""
from __future__ import annotations

import argparse
import os
import subprocess
import threading
import time

TICKS = os.sysconf("SC_CLK_TCK")
SAMPLE_S = 0.010
# /proc CPU counters advance in jiffies (10 ms at USER_HZ=100), so a per-sample
# ratio is aliased noise; the busy/quiet verdict comes from a sliding window.
WINDOW_S = 0.050
BUSY_RATIO = 0.5


def main_thread_ticks(pid: int) -> int:
    with open(f"/proc/{pid}/task/{pid}/stat", "rb") as handle:
        data = handle.read()
    fields = data[data.rfind(b")") + 2:].split()
    return int(fields[11]) + int(fields[12])


def ipc(*args: str) -> None:
    subprocess.run(["qs", "ipc", "-c", "ii", "call", *args], capture_output=True)


def sample(pid: int, stop: threading.Event, out: list[tuple[float, int]]) -> None:
    while not stop.is_set():
        try:
            out.append((time.monotonic(), main_thread_ticks(pid)))
        except FileNotFoundError:
            return
        time.sleep(SAMPLE_S)


def measure(pid: int, tab: str, window: float, settle: float) -> dict:
    ipc("cheatsheet", "close")
    time.sleep(0.4)
    ipc("cheatsheet", "openTab", "email")
    time.sleep(settle)
    ipc("cheatsheet", "close")
    time.sleep(0.8)
    ipc("cheatsheet", "openTab", tab)
    time.sleep(max(settle, 2.0))
    ipc("cheatsheet", "close")
    time.sleep(0.8)

    stop = threading.Event()
    samples: list[tuple[float, int]] = []
    probe = threading.Thread(target=sample, args=(pid, stop, samples), daemon=True)
    probe.start()
    time.sleep(0.4)
    triggered = time.monotonic()
    ipc("cheatsheet", "openTab", tab)
    time.sleep(window)
    stop.set()
    probe.join()

    rows = [(stamp - triggered, ticks) for stamp, ticks in samples if stamp >= triggered]
    if len(rows) < 2:
        return {"longest_ms": 0.0, "cpu_ms": 0.0, "peak_ratio": 0.0}
    longest = current = 0.0
    peak = 0.0
    start_index = 0
    for index, (stamp, ticks) in enumerate(rows):
        while rows[start_index][0] < stamp - WINDOW_S:
            start_index += 1
        span = stamp - rows[start_index][0]
        ratio = (ticks - rows[start_index][1]) / TICKS / span if span > 0 else 0.0
        peak = max(peak, ratio)
        if ratio >= BUSY_RATIO:
            current += SAMPLE_S
            longest = max(longest, current)
        else:
            current = 0.0
    return {
        "longest_ms": longest * 1000.0,
        "cpu_ms": (rows[-1][1] - rows[0][1]) / TICKS * 1000.0,
        "peak_ratio": peak,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True, help="pid of the running qs instance")
    parser.add_argument("--tab", required=True, help="cheatsheet tab id, e.g. timetable")
    parser.add_argument("--runs", type=int, default=2)
    parser.add_argument("--window", type=float, default=6.0, help="seconds sampled after the click")
    parser.add_argument("--settle", type=float, default=2.0)
    args = parser.parse_args()

    for run in range(1, args.runs + 1):
        result = measure(args.pid, args.tab, args.window, args.settle)
        print(f"[{args.tab} run {run}] longest contiguous busy ~{result['longest_ms']:.0f} ms | "
              f"main-thread CPU {result['cpu_ms']:.0f} ms in {args.window:.0f} s | "
              f"peak 50 ms window {result['peak_ratio'] * 100:.0f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())