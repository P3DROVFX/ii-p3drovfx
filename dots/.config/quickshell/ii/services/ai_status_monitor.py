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
work can still fall below all three. Only the CLI itself can report that.

That is what the hook path below now does. `scripts/ai/claude_status_hook.py` writes one
file per session, and this monitor prefers it over anything it can infer: the state is
the real one (working, running a tool, asking you something, waiting on a permission,
done), the turn's clock is the CLI's own - so a shell reload does not restart it - and
the token counts come from the transcript. The CPU heuristic is left for the CLIs that
report nothing, and is suppressed for any process a hook is already speaking for.
"""
import json
import os
import sys
import time

CLK_TCK = os.sysconf("SC_CLK_TCK")

# Exact process names (/proc/<pid>/comm, or the basename of argv[0]).
# `comm` is what the kernel reports, truncated to 15 characters.
# The name is shown beside a "CLI" badge, so it does not repeat the word: "Claude CLI
# [CLI]" said the same thing twice and cost the row the space a status line needs.
KNOWN_AGENTS = {
    "claude": ("Claude", "bootstrap_claude.svg"),
    "gemini": ("Gemini", "google-gemini-symbolic.svg"),
    "aider": ("Aider", "google-gemini-symbolic.svg"),
    "goose": ("Goose", "google-gemini-symbolic.svg"),
    "codex": ("Codex", "openai-symbolic.svg"),
    "commandcode": ("Command Code", "openai-symbolic.svg"),
    "antigravity-cli": ("Antigravity", "material-symbols_antigravity.svg"),
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
# A hook session reports real state changes, so it is read back promptly; the
# cost is a listdir and a few small reads.
INTERVAL_WITH_HOOKS = 1.0

# ── The hook path ───────────────────────────────────────────────────────────────
# Where claude_status_hook.py leaves one file per live session. On tmpfs, so a reboot
# clears it; a dead pid or a stale file is pruned here as well.
HOOK_STATE_DIR = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell", "ai-status")

# A finished turn is worth showing for a moment - "done" is information - but not for
# the rest of the day. The same for the CLI's own "still waiting on you" notice.
DONE_LINGER_SECONDS = 10.0
# A file whose session died without a SessionEnd (a kill -9, a crash) is dropped.
HOOK_STALE_SECONDS = 12 * 3600
# ...but not the moment its pid stops answering. Identifying the CLI behind a hook can
# fail outright - an async hook is reparented away from it - and dropping the file
# there restarted the turn clock and threw the turn's token count away with it. A file
# that is still being written stays, whatever its pid says.
HOOK_FRESH_SECONDS = 120.0

# The turn is over and the island says so once, in its centre.
ENDED_STATES = ("done", "interrupted")

# What each reported state means to the island. `attention` is what promotes the
# activity to an interrupt: it takes the island's centre and stays there.
HOOK_STATES = {
    "working":      {"show": True,  "attention": False},
    "tool":         {"show": True,  "attention": False},
    "asking":       {"show": True,  "attention": True},
    "needsAction":  {"show": True,  "attention": True},
    "compacting":   {"show": True,  "attention": False},
    "interrupted":  {"show": "linger", "attention": False},
    "done":         {"show": "linger", "attention": False},
    "waitingInput": {"show": "linger", "attention": False},
    "idle":         {"show": False, "attention": False},
}


# ── The transcript ──────────────────────────────────────────────────────────────
# The CLI writes the truth here as it goes, and some of it reaches no hook at all:
#
#   * Escape ends the turn and fires no event - the CLI simply stops. It does write the
#     interruption down, timestamped, so that is what is read; the island otherwise
#     went on counting a turn that had already been abandoned.
#   * The turn's opening prompt carries the moment the CLI started counting, which is
#     what its own footer shows. The hook file agrees when it survives, and this is
#     what puts the clock back when it does not.
#   * Token usage lands on every assistant message, while hook events can be half a
#     minute apart - reading it here is what makes the numbers follow the CLI's footer
#     instead of trailing the last tool call.
#
# Only what was appended since the last look is read, so a running turn costs a stat
# and a few kilobytes per second, and an idle one costs the stat alone.
INTERRUPT_MARKER = "[Request interrupted"
# An interrupt during a tool call is recorded inside that tool's result rather than as
# a message of its own. Matched exactly: the same sentence quoted in a command's output
# is not an interruption, and used to read as one.
TOOL_INTERRUPT_MARKER = "[Request interrupted by user for tool use]"
# How much of an unseen transcript's tail to read the first time...
TRANSCRIPT_TAIL_BYTES = 256 * 1024
# ...grown up to this until the prompt that opened the turn is in it. One pasted
# screenshot is a megabyte of record, and a turn read from its middle has the wrong
# clock and an output count missing everything before the window.
TRANSCRIPT_MAX_TAIL_BYTES = 16 * 1024 * 1024
# User records that are not the user asking for something: the CLI's own bookkeeping
# around a slash command, a `!` shell line, and notes it injects for the model.
NOT_A_PROMPT_PREFIXES = ("<local-command", "<command-name>", "<command-message>",
                         "<bash-", "<system-reminder>")

_transcripts = {}


def _parse_timestamp(text):
    """The transcript's ISO-8601 stamps, as epoch seconds."""
    if not text:
        return 0.0
    try:
        from datetime import datetime
        return datetime.strptime(text.replace("Z", "+0000"),
                                 "%Y-%m-%dT%H:%M:%S.%f%z").timestamp()
    except (ValueError, ImportError):
        return 0.0


def _user_blocks(content):
    """A user record's own text, and the tool results it carries, separately.

    Tool results arrive as `user` records too: telling them apart is what separates a
    prompt from a tool call coming back, and the agent's own quoted output from a real
    interruption.
    """
    if isinstance(content, str):
        return [content], []
    texts, results = [], []
    for block in content or []:
        if not isinstance(block, dict):
            continue
        if block.get("type") == "text":
            texts.append(str(block.get("text") or ""))
        elif block.get("type") == "tool_result":
            inner = block.get("content")
            if isinstance(inner, str):
                results.append(inner)
            else:
                results.extend(str(part.get("text") or "")
                               for part in inner or [] if isinstance(part, dict))
    return texts, results


class TranscriptTail:
    """A session's transcript, followed forward from wherever we last stopped."""

    __slots__ = ("inode", "offset", "interrupt", "context", "output", "model",
                 "turn_started", "seen")

    def __init__(self):
        self.inode = 0
        self.offset = 0
        self.forget()

    def forget(self):
        self.interrupt = 0.0
        # None is "not seen yet", and the hook's figure stands in for it. Zero is a
        # fact: the window was just compacted and nothing has been sent since.
        self.context = None
        self.model = ""
        self.new_turn(0.0)

    def new_turn(self, stamp):
        # The context and the model belong to the session and carry over; only what the
        # turn itself produced starts again.
        self.turn_started = stamp
        self.output = 0
        self.seen = set()

    def rewind(self, stat, window=TRANSCRIPT_TAIL_BYTES):
        """Start again from the tail of the file, forgetting the turn so far."""
        self.inode = stat.st_ino
        # Not aligned to a line: the first fragment simply fails to parse and is
        # dropped, which is cheaper than hunting for a newline.
        self.offset = max(0, stat.st_size - window)
        self.forget()

    def feed(self, raw):
        try:
            record = json.loads(raw)
        except ValueError:
            return
        if not isinstance(record, dict):
            return
        if record.get("isSidechain"):
            return      # a subagent's own conversation: its prompts are not the user's
        if record.get("type") == "system" and record.get("subtype") == "compact_boundary":
            self.context = 0
            return
        message = record.get("message") or {}
        if not isinstance(message, dict):
            return
        role = message.get("role")
        stamp = _parse_timestamp(record.get("timestamp"))
        if role == "user":
            texts, results = _user_blocks(message.get("content"))
            if any(text.lstrip().startswith(INTERRUPT_MARKER) for text in texts) \
                    or any(text.strip() == TOOL_INTERRUPT_MARKER for text in results):
                if stamp > 0:
                    self.interrupt = max(self.interrupt, stamp)
                return
            if results or stamp <= 0 or record.get("isMeta") or record.get("isCompactSummary"):
                return
            if any(text.lstrip().startswith(NOT_A_PROMPT_PREFIXES) for text in texts[:1]):
                return
            # Something the user asked for: the turn starts here, and its counters with
            # it. A message typed into a turn already running never lands here - the CLI
            # hands it over as an attachment - so every one of these opens a turn.
            # Slash-command bookkeeping is written late with its original timestamp,
            # hence never moving backwards.
            if stamp > self.turn_started:
                self.new_turn(stamp)
            return
        if role != "assistant":
            return
        usage = message.get("usage") or record.get("usage")
        if not isinstance(usage, dict):
            return
        # Context is the newest message's input side, not a sum: every message re-reads
        # the whole window, so adding them up counts the conversation once per message.
        self.context = ((usage.get("input_tokens") or 0)
                        + (usage.get("cache_read_input_tokens") or 0)
                        + (usage.get("cache_creation_input_tokens") or 0))
        self.model = str(message.get("model") or self.model)
        # The usage block is repeated on every content block of one message, so
        # messages are counted once by id.
        key = message.get("id")
        if key:
            if key in self.seen:
                return
            self.seen.add(key)
        self.output += usage.get("output_tokens") or 0


def transcript_tail(path):
    """This transcript, read up to date. None when there is nothing to read."""
    if not path:
        return None
    try:
        stat = os.stat(path)
    except OSError:
        return None
    tail = _transcripts.get(path)
    if tail is None:
        # Bounded by the number of sessions ever seen in this process; cleared rather
        # than aged, since a transcript re-read costs one tail and nothing else.
        if len(_transcripts) > 32:
            _transcripts.clear()
        tail = _transcripts[path] = TranscriptTail()
    if tail.inode != stat.st_ino or stat.st_size < tail.offset:
        # First sight of this file. The window grows until the prompt that opened the
        # turn is inside it, so a shell reload in the middle of a long turn comes back
        # with the CLI's own clock and the whole turn's output.
        window = TRANSCRIPT_TAIL_BYTES
        while True:
            tail.rewind(stat, window)
            _read_appended(path, stat, tail)
            if tail.turn_started > 0 or window >= stat.st_size \
                    or window >= TRANSCRIPT_MAX_TAIL_BYTES:
                return tail
            window *= 4
    _read_appended(path, stat, tail)
    return tail


def _read_appended(path, stat, tail):
    if stat.st_size <= tail.offset:
        return
    try:
        with open(path, "rb") as handle:
            handle.seek(tail.offset)
            chunk = handle.read(stat.st_size - tail.offset)
    except OSError:
        return
    cut = chunk.rfind(b"\n")
    if cut == -1:
        # A record still being written; it is read once its line is complete.
        return
    tail.offset += cut + 1
    for line in chunk[:cut].split(b"\n"):
        if line.strip():
            tail.feed(line)


def interrupted_at(path):
    """When the newest interruption in this transcript happened, or 0."""
    tail = transcript_tail(path)
    return tail.interrupt if tail else 0.0


def pid_alive(pid, proc_root="/proc"):
    return pid > 0 and os.path.isdir("%s/%d" % (proc_root, pid))


def read_hook_sessions(now, state_dir=HOOK_STATE_DIR, proc_root="/proc"):
    """Every session a hook is currently speaking for, newest state first.

    Files for sessions whose process is gone are deleted here rather than left to
    accumulate: `SessionEnd` covers the ordinary exit, this covers the rest.
    """
    sessions = []
    try:
        entries = os.listdir(state_dir)
    except OSError:
        return sessions
    for entry in entries:
        if not entry.endswith(".json"):
            continue
        path = os.path.join(state_dir, entry)
        try:
            with open(path, "r") as handle:
                record = json.load(handle)
        except (OSError, ValueError):
            continue
        if not isinstance(record, dict):
            continue
        pid = int(record.get("pid") or 0)
        updated = float(record.get("updatedAt") or 0)
        silent = (now - updated) > HOOK_FRESH_SECONDS
        if (silent and not pid_alive(pid, proc_root)) or (now - updated) > HOOK_STALE_SECONDS:
            try:
                os.remove(path)
            except OSError:
                pass
            continue
        sessions.append(record)
    return sessions


def turn_start(record, tail):
    """When the turn on show began, and whether the transcript was read from there.

    The CLI counts from the prompt it picked up, and its own timestamp for that prompt
    is in the transcript - so that is the answer whenever the prompt is the turn's. The
    hook's clock agrees to milliseconds when its file lived through the turn, and is
    late when it did not (a lost file adopts the next event as the start).

    The prompt is not the turn's when something ended its turn and the hook has opened
    another since: work that starts without a typed prompt - a skill's slash command, a
    background task reporting back - leaves no prompt behind, only the hook's event.
    """
    hooked = float(record.get("turnStartedAt") or 0)
    prompt = tail.turn_started if tail else 0.0
    if prompt <= 0:
        return hooked, False
    ends = (float(record.get("turnEndedAt") or 0), tail.interrupt)
    if any(prompt < end < hooked for end in ends):
        return hooked, False
    return prompt, True


def hook_agents(sessions, now):
    """The hook sessions worth putting on the island, as island entries."""
    agents = []
    for record in sessions:
        state = str(record.get("state") or "idle")
        rule = HOOK_STATES.get(state)
        if not rule or not rule["show"]:
            continue
        ended = float(record.get("turnEndedAt") or 0)
        tail = transcript_tail(record.get("transcriptPath"))
        started, whole_turn = turn_start(record, tail)
        # Abandoned with Escape: the turn is over even though no event said so, and the
        # file still reads "running a tool". Said out loud for a moment, like "done".
        if rule["show"] is True and started > 0 and tail and tail.interrupt > started:
            state, ended = "interrupted", tail.interrupt
            rule = HOOK_STATES[state]
        if rule["show"] == "linger":
            if ended <= 0 or (now - ended) > DONE_LINGER_SECONDS:
                continue
        key = str(record.get("agent") or "claude")
        name, icon = KNOWN_AGENTS.get(key, ("AI Agent", "google-gemini-symbolic.svg"))
        entry = {
            "id": "%s_%s" % (key, record.get("sessionId") or record.get("pid")),
            "pid": int(record.get("pid") or 0),
            "name": name,
            "icon": icon,
            "source": "cli",
            "state": state,
            "tool": str(record.get("tool") or ""),
            "requiresAttention": rule["attention"],
            # A turn that just ended leads for the moment it is announced, ahead of the
            # sessions still working: it is the one the island is talking about.
            "priority": 0 if rule["attention"] else (5 if state in ENDED_STATES else 10),
            "sessionId": str(record.get("sessionId") or ""),
            "cwd": str(record.get("cwd") or ""),
            "tokensIn": int(record.get("tokensIn") or 0),
            "tokensOut": int(record.get("tokensOut") or 0),
            "model": str(record.get("model") or ""),
        }
        # Usage lands on every assistant message, while hook events can be a tool call
        # apart; read live, the counters move with the CLI's own footer rather than
        # jumping a minute late.
        if tail:
            if tail.context is not None:
                entry["tokensIn"] = tail.context
            # A transcript picked up part-way through a turn has not seen all of it, and
            # the hook's count is the better one until it has.
            entry["tokensOut"] = tail.output if whole_turn \
                else max(entry["tokensOut"], tail.output)
            entry["model"] = tail.model or entry["model"]
        # The turn's clock is the CLI's, written when the turn began. A running turn
        # hands the island the start so it can tick between samples; a finished one
        # hands it the length, so the island shows how long it took.
        if rule["show"] == "linger":
            entry["runtime"] = max(0, int(ended - started)) if started > 0 else 0
            entry["startedAtEpoch"] = 0
        else:
            entry["startedAtEpoch"] = int(started)
            entry["runtime"] = max(0, int(now - started)) if started > 0 else 0
        agents.append(entry)
    return agents


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
    not be part of the change test, or every sample would be a change. The token counts
    are excluded for the same reason - they are carried on every line regardless, and
    the island reads them without rebuilding its widgets."""
    return sorted((agent["id"], agent["state"], agent.get("tool", ""),
                   agent.get("requiresAttention", False)) for agent in agents)


def merge(hooked, inferred, sessions=()):
    """The hook wins. A CLI that reports its own state must never also be guessed at:
    the guess has no idea whether a quiet process is thinking or waiting for you, and a
    second entry for the same process would show the island two agents where there is
    one.

    That holds for a session with nothing to show as much as for one on the island. It
    used to cover only the latter, so the moment a session went quiet - interrupted,
    finished, idle at its prompt - the guess took the same process over: "Working", on
    a clock of its own, without tokens, for as long as the CLI redrew its input box.
    """
    spoken_for = {agent["pid"] for agent in hooked}
    spoken_for.update(int(record.get("pid") or 0) for record in sessions)
    # A session whose process could not be identified still rules the guess out for its
    # kind of CLI: hooks are installed per CLI, not per session.
    anonymous = {"%s_" % (record.get("agent") or "claude") for record in sessions
                 if int(record.get("pid") or 0) <= 0}
    return hooked + [agent for agent in inferred
                     if agent["pid"] not in spoken_for
                     and not any(agent["id"].startswith(key) for key in anonymous)]


def main():
    tracker = AgentTracker()
    last_shape = None
    last_payload = None
    while True:
        try:
            now = time.time()
            sessions = read_hook_sessions(now)
            hooked = hook_agents(sessions, now)
            candidates = scan_candidates()
            inferred = tracker.sample(candidates, time.monotonic())
            agents = merge(hooked, inferred, sessions)
            shape = reported_shape(agents)
            payload = json.dumps({"agents": agents})
            # Token counts move without the shape changing, so a line is also written
            # when only they did - but only then, never on the runtime alone.
            if shape != last_shape or (shape and payload != last_payload):
                last_shape = shape
                last_payload = payload
                print(payload, flush=True)
        except BrokenPipeError:
            sys.exit(0)
        except Exception as error:  # keep the stream alive; the island degrades quietly
            try:
                print(json.dumps({"agents": [], "error": str(error)}), flush=True)
            except BrokenPipeError:
                sys.exit(0)
            candidates = []
            sessions = []
        # A hook session is worth watching closely; with nothing at all, back off.
        if sessions:
            time.sleep(INTERVAL_WITH_HOOKS)
        else:
            time.sleep(INTERVAL_WITH_CANDIDATES if candidates else INTERVAL_IDLE)


if __name__ == "__main__":
    main()
