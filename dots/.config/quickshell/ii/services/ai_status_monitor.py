#!/usr/bin/env python3
"""AI agent activity monitor for the Quickshell ii Dynamic Island.

This is the *fallback* detector, used for CLIs that cannot report their own state.
It answers one question — "is this agent working right now?" — from CPU usage, and
it has to answer it stably, because the island shows a running timer for the turn.

The previous version compared a raw tick delta (`delta >= 15`) against a sampling
interval that changed with the result (1s while active, 3s while idle). Fifteen ticks
is 15% CPU over one second but only 5% over three, so a steady 8% process was read as
ACTIVE at 3s and IDLE at 1s, and the detector oscillated on its own: idle(3s) -> active
-> 1s -> idle -> off -> 3s -> active. Every flip reset the turn start, which is why the
island's timer restarted every few seconds. Measured on 2026-09-17.

What changed:
  * CPU is a *rate*: delta ticks / (elapsed wall time * CLK_TCK), smoothed with an EMA.
  * The sampling interval never depends on the outcome.
  * Hysteresis: a high bar to start, a low bar held over time to stop.
  * Processes are matched by exact `comm`/argv[0], not by substring over the whole
    command line. The old substring match reported the agent's own tool calls: Claude
    Code's shell snapshots run as `/usr/bin/zsh -c source ~/.claude/...`, which contains
    "claude" and was skipped only for `bash -c`/`sh -c`.
  * Child processes are not evidence of work. A persistent `zsh` or a language server
    kept the old detector "busy" forever.
  * Output is written only when the reported set actually changes, so the QML side does
    not rebuild its widget list once a second.

Known limit, and the reason hooks are the primary source: an agent waiting on the model
API burns almost no CPU in its own process (measured: 3% while running a tool call), so
work is inferred from three signals together - the agent's own CPU, the CPU of its tool
children, and tool children appearing. A turn that is purely "thinking" with no local
work can still fall below all three. Only the CLI itself can report that, which is what
the hook path does.
"""
import json
import os
import sys
import time

CLK_TCK = os.sysconf("SC_CLK_TCK")

# Exact process names (/proc/<pid>/comm, or the basename of argv[0]).
# `comm` is what the kernel reports, truncated to 15 characters.
KNOWN_AGENTS = {
    "claude": ("Claude CLI", "bootstrap_claude.svg"),
    "gemini": ("Gemini CLI", "google-gemini-symbolic.svg"),
    "aider": ("Aider", "google-gemini-symbolic.svg"),
    "goose": ("Goose", "google-gemini-symbolic.svg"),
    "codex": ("Codex CLI", "openai-symbolic.svg"),
    "commandcode": ("Command Code", "openai-symbolic.svg"),
    "antigravity-cli": ("Antigravity CLI", "material-symbols_antigravity.svg"),
}

# Thresholds are percentages of one core.
START_PERCENT = 18.0      # must be exceeded...
START_SAMPLES = 2         # ...this many samples in a row to call it working
STOP_PERCENT = 4.0        # must stay below...
STOP_SECONDS = 6.0        # ...this long to call it idle
EMA_ALPHA = 0.4

STOP_SECONDS_EFFECTIVE = 10.0   # grace once every signal is quiet
TOOL_CHILD_FRESH_SECONDS = 45.0  # a child this young is a tool call in flight
TOOL_CHILD_BUSY_PERCENT = 5.0    # ...or one that is actually burning CPU

# A persistent child is not evidence of work: a long-lived shell or language server kept
# the old detector "busy" forever.
IGNORED_CHILD_MARKERS = ("mcp", "language_server", "chrome-devtools", "lsp", "tailwind")

INTERVAL_WITH_CANDIDATES = 2.0
INTERVAL_IDLE = 8.0


def read_proc_stat_ticks(proc_root, pid):
    """utime + stime for a pid, or None if it is gone.

    Children are deliberately excluded: `cutime`/`cstime` only accumulate when a child
    *exits*, so a finished tool call used to look like a burst of new work.
    """
    try:
        with open(f"{proc_root}/{pid}/stat", "r") as handle:
            content = handle.read()
    except (OSError, ValueError):
        return None
    close = content.rfind(")")
    if close == -1:
        return None
    fields = content[close + 1:].split()
    try:
        return int(fields[11]) + int(fields[12])
    except (IndexError, ValueError):
        return None


def read_comm(proc_root, pid):
    try:
        with open(f"{proc_root}/{pid}/comm", "r") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def read_argv0_base(proc_root, pid):
    try:
        with open(f"{proc_root}/{pid}/cmdline", "rb") as handle:
            raw = handle.read()
    except OSError:
        return ""
    if not raw:
        return ""
    argv0 = raw.split(b"\0", 1)[0].decode("utf-8", "replace")
    return os.path.basename(argv0)


def read_children(proc_root, pid):
    """Direct children of a pid, from the thread group's children file."""
    try:
        with open(f"{proc_root}/{pid}/task/{pid}/children", "r") as handle:
            return [int(part) for part in handle.read().split()]
    except (OSError, ValueError):
        return []


def read_start_ticks(proc_root, pid):
    """Field 22 of /proc/<pid>/stat: process start time, in ticks since boot."""
    try:
        with open(f"{proc_root}/{pid}/stat", "r") as handle:
            content = handle.read()
    except OSError:
        return None
    close = content.rfind(")")
    if close == -1:
        return None
    fields = content[close + 1:].split()
    try:
        return int(fields[19])
    except (IndexError, ValueError):
        return None


def boot_time_ticks(proc_root):
    """Uptime in ticks, to turn a start time into an age without trusting wall clocks."""
    try:
        with open(f"{proc_root}/uptime", "r") as handle:
            return float(handle.read().split()[0]) * CLK_TCK
    except (OSError, ValueError, IndexError):
        return None


def agent_identity(proc_root, pid):
    """The agent this pid is, or None. Exact names only."""
    for name in (read_comm(proc_root, pid), read_argv0_base(proc_root, pid)):
        if name in KNOWN_AGENTS:
            return name
    return None


def scan_candidates(proc_root="/proc"):
    """Every live pid that is one of the known agents."""
    found = []
    self_pid = os.getpid()
    try:
        entries = os.listdir(proc_root)
    except OSError:
        return found
    for entry in entries:
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == self_pid:
            continue
        key = agent_identity(proc_root, pid)
        if key is None:
            continue
        ticks = read_proc_stat_ticks(proc_root, pid)
        if ticks is None:
            continue
        found.append({
            "pid": pid,
            "key": key,
            "ticks": ticks,
            "children": collect_tool_children(proc_root, pid),
        })
    return found


def collect_tool_children(proc_root, pid):
    """Tool children of an agent, with the data needed to judge them."""
    uptime = boot_time_ticks(proc_root)
    children = []
    for child in read_children(proc_root, pid):
        comm = read_comm(proc_root, child)
        argv0 = read_argv0_base(proc_root, child)
        haystack = f"{comm} {argv0}".lower()
        if any(marker in haystack for marker in IGNORED_CHILD_MARKERS):
            continue
        ticks = read_proc_stat_ticks(proc_root, child)
        if ticks is None:
            continue
        start = read_start_ticks(proc_root, child)
        age = None
        if uptime is not None and start is not None:
            age = max(0.0, (uptime - start) / CLK_TCK)
        children.append({"pid": child, "ticks": ticks, "age": age})
    return children


class AgentTracker:
    """Turns tick samples into a stable working/idle verdict per pid."""

    def __init__(self):
        self.states = {}

    def _tool_children_working(self, state, candidate, elapsed):
        """True when the agent is running a tool right now.

        Three things count: a child that just appeared, a child young enough to still be
        a tool call in flight, and a child actually burning CPU (a long build). A child
        that merely *exists*, idle, counts for nothing - that was the old detector's
        permanent "busy" state.
        """
        children = candidate.get("children", [])
        previous = state.get("child_ticks", {})
        current = {}
        working = False
        for child in children:
            pid = child["pid"]
            current[pid] = child["ticks"]
            if pid not in previous:
                working = True          # a new tool process
                continue
            if child["age"] is not None and child["age"] < TOOL_CHILD_FRESH_SECONDS:
                working = True          # still in flight
                continue
            if elapsed > 0:
                rate = ((child["ticks"] - previous[pid]) / CLK_TCK) / elapsed * 100.0
                if rate > TOOL_CHILD_BUSY_PERCENT:
                    working = True      # a long-running command doing real work
        state["child_ticks"] = current
        return working

    def sample(self, candidates, now):
        """Feed one scan; return the agents considered to be working."""
        seen = {candidate["pid"] for candidate in candidates}
        for pid in [pid for pid in self.states if pid not in seen]:
            del self.states[pid]

        working = []
        for candidate in candidates:
            pid = candidate["pid"]
            state = self.states.get(pid)
            if state is None:
                # A new pid is only a baseline for its rate, but it is still tracked
                # from this moment, so it can be reported on the very next sample.
                self.states[pid] = {
                    "ticks": candidate["ticks"],
                    "at": now,
                    "ema": 0.0,
                    "above": 0,
                    "below_since": now,
                    "working": False,
                    "started_at": 0.0,
                    "started_wall": 0.0,
                    "child_ticks": {child["pid"]: child["ticks"]
                                    for child in candidate.get("children", [])},
                }
                continue

            elapsed = now - state["at"]
            if elapsed <= 0:
                continue
            delta = max(0, candidate["ticks"] - state["ticks"])
            percent = (delta / CLK_TCK) / elapsed * 100.0
            state["ticks"] = candidate["ticks"]
            state["at"] = now
            state["ema"] = EMA_ALPHA * percent + (1.0 - EMA_ALPHA) * state["ema"]

            tool_work = self._tool_children_working(state, candidate, elapsed)

            # Starting uses the smoothed rate, so a single spike (a GC pause, a
            # spinner redraw) cannot start a turn. Stopping uses the raw rate, because
            # an EMA from a busy turn needs ~7 samples just to decay past the floor,
            # which left the island claiming to be working ~26s after the agent stopped.
            if state["ema"] > START_PERCENT:
                state["above"] += 1
            else:
                state["above"] = 0

            busy_now = percent >= STOP_PERCENT or tool_work
            if busy_now:
                state["below_since"] = now

            if not state["working"]:
                # A tool child is immediate evidence; own CPU needs confirmation.
                if tool_work or state["above"] >= START_SAMPLES:
                    state["working"] = True
                    state["started_at"] = now
                    state["started_wall"] = time.time()
                    state["below_since"] = now
            elif (now - state["below_since"]) >= STOP_SECONDS_EFFECTIVE:
                state["working"] = False
                state["started_at"] = 0.0
                state["started_wall"] = 0.0

            if state["working"]:
                name, icon = KNOWN_AGENTS[candidate["key"]]
                working.append({
                    "id": f"{candidate['key']}_{pid}",
                    "pid": pid,
                    "name": name,
                    "icon": icon,
                    "source": "cli",
                    "state": "running",
                    # Held across samples: it only moves when work actually stops.
                    "runtime": max(0, int(now - state["started_at"])),
                    # Wall clock, so the UI can keep the timer moving between samples.
                    # Output is only written when the set changes, so a `runtime` field
                    # alone would freeze on screen.
                    "startedAtEpoch": int(state["started_wall"]),
                })
        return working


def reported_shape(agents):
    """What the island cares about. The runtime ticks on its own in the UI, so it must
    not be part of the change test, or every sample would be a change."""
    return sorted((agent["id"], agent["state"]) for agent in agents)


def main():
    tracker = AgentTracker()
    last_shape = None
    while True:
        try:
            candidates = scan_candidates()
            agents = tracker.sample(candidates, time.monotonic())
            shape = reported_shape(agents)
            if shape != last_shape:
                last_shape = shape
                print(json.dumps({"agents": agents}), flush=True)
        except BrokenPipeError:
            sys.exit(0)
        except Exception as error:  # keep the stream alive; the island degrades quietly
            try:
                print(json.dumps({"agents": [], "error": str(error)}), flush=True)
            except BrokenPipeError:
                sys.exit(0)
            candidates = []
        time.sleep(INTERVAL_WITH_CANDIDATES if candidates else INTERVAL_IDLE)


if __name__ == "__main__":
    main()
