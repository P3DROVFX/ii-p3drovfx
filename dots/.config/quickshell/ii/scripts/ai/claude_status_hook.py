#!/usr/bin/env python3
"""Report a Claude Code session's real state to the Dynamic Island.

The island used to infer "an agent is working" from CPU usage alone, which cannot see a
turn spent waiting on the model (measured: 3% of one core while a tool call runs), and
cannot tell working from waiting-for-you at all. The CLI knows both exactly, so this
hook writes it down and the island reads it.

One file per session under `$XDG_RUNTIME_DIR/quickshell/ai-status/`, rewritten on every
hook event. Everything the island shows lives in that file, including the turn's start
time *as the CLI saw it* - so a shell reload, or killing Quickshell outright, does not
restart the timer the way a shell-side clock did.

Install with `install_claude_status_hook.py`. Every event exits 0 whatever happens: a
status indicator must never be able to break the agent it is reporting on.
"""
import fcntl
import glob
import json
import os
import sys
import time

STATE_DIR = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell", "ai-status")

# How much of the transcript's tail to read when looking for the newest token usage.
# The file is JSONL and grows without bound; the last few records are all we need.
TRANSCRIPT_TAIL_BYTES = 256 * 1024
# ...grown up to this when the tail held no usage record, which happens when the last
# few records are large tool results.
TRANSCRIPT_MAX_TAIL_BYTES = 16 * 1024 * 1024

# The CLI processes a hook event fires under. `comm` is truncated to 15 characters.
AGENT_COMMS = ("claude", "gemini", "aider", "goose", "codex", "antigravity-cli")


def read_comm(pid):
    try:
        with open("/proc/%d/comm" % pid, "r") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def read_ppid(pid):
    try:
        with open("/proc/%d/stat" % pid, "r") as handle:
            content = handle.read()
    except OSError:
        return 0
    close = content.rfind(")")
    if close == -1:
        return 0
    try:
        return int(content[close + 1:].split()[1])
    except (IndexError, ValueError):
        return 0


def owning_agent(remembered=0):
    """The CLI this hook was spawned by: (pid, comm).

    Walked rather than assumed, because a hook runs several processes deep - a shell,
    then this script - and the island keys its entries on the agent's own pid so a dead
    session can be pruned without waiting for a timeout.

    The walk can come up empty: an async hook is reparented away from the CLI. Naming
    the shell that spawned us instead was worse than naming nobody - that pid is dead
    the moment this exits, and the island pruned the session's file on it, restarting
    the turn clock and dropping the turn's token count. So the pid last written for
    this session is reused while it is still a CLI, and otherwise nothing is claimed.
    """
    pid = os.getppid()
    for _ in range(12):
        if pid <= 1:
            break
        comm = read_comm(pid)
        if comm in AGENT_COMMS:
            return pid, comm
        pid = read_ppid(pid)
    comm = read_comm(remembered) if remembered > 0 else ""
    if comm in AGENT_COMMS:
        return remembered, comm
    return 0, "claude"


def find_transcript(session_id, given, remembered):
    """The session's transcript: what the event named, else what we saw last, else the
    file Claude Code keeps under ~/.claude/projects for this session id.

    Not every hook event carries `transcript_path`, and a token count that appears and
    disappears depending on which event fired last is worse than none.
    """
    for candidate in (given, remembered):
        if candidate and os.path.isfile(candidate):
            return candidate
    if not session_id:
        return ""
    matches = glob.glob(os.path.expanduser(
        "~/.claude/projects/*/%s.jsonl" % session_id))
    return matches[0] if matches else ""


def read_usage(transcript_path):
    """The newest token usage in the transcript, as {input, output}.

    Only the tail is read: the transcript is append-only JSONL and can reach megabytes,
    and a hook that reads all of it before every tool call would be felt. A single
    record can itself be hundreds of kilobytes (a large tool result), so the window
    grows until a usage record is in it rather than giving up on the first miss.
    """
    if not transcript_path or not os.path.isfile(transcript_path):
        return None
    window = TRANSCRIPT_TAIL_BYTES
    while window <= TRANSCRIPT_MAX_TAIL_BYTES:
        try:
            size = os.path.getsize(transcript_path)
            with open(transcript_path, "rb") as handle:
                if size > window:
                    handle.seek(size - window)
                    handle.readline()      # drop the partial line the seek landed in
                lines = handle.read().decode("utf-8", "replace").splitlines()
        except OSError:
            return None

        usage = _newest_usage(lines)
        # A turn whose start is not in the window yet is under-counted, so the window
        # grows until the whole turn is in it (or the file is).
        if size <= window or (usage is not None and _saw_turn_start(lines)):
            return usage
        window *= 4
    return None


def _saw_turn_start(lines):
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            if _is_user_prompt(json.loads(line)):
                return True
        except ValueError:
            continue
    return False


def _parse_timestamp(text):
    """The transcript's ISO-8601 stamps, as epoch seconds."""
    if not text:
        return 0.0
    try:
        from datetime import datetime
        return datetime.strptime(str(text).replace("Z", "+0000"),
                                 "%Y-%m-%dT%H:%M:%S.%f%z").timestamp()
    except (ValueError, ImportError):
        return 0.0


INTERRUPT_MARKER = "[Request interrupted"
# User records that are not the user asking for something: the CLI's own bookkeeping
# around a slash command, a `!` shell line, and notes it injects for the model.
NOT_A_PROMPT_PREFIXES = ("<local-command", "<command-name>", "<command-message>",
                         "<bash-", "<system-reminder>")


def _user_text(record):
    """What a user record says, or None when it is a tool call coming back.

    Tool results come back as `user` records too, so a naive role check would end the
    turn at the first tool call and report a fraction of it.
    """
    message = record.get("message") or {}
    if message.get("role") != "user" or record.get("isSidechain"):
        return None
    content = message.get("content")
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None
    blocks = [block for block in content if isinstance(block, dict)]
    if any(block.get("type") == "tool_result" for block in blocks):
        return None
    for block in blocks:
        if block.get("type") == "text":
            return str(block.get("text") or "")
    return ""


def _is_interrupt(record):
    text = _user_text(record)
    return text is not None and text.lstrip().startswith(INTERRUPT_MARKER)


def _is_user_prompt(record):
    """A record that starts a turn: something the user actually asked for."""
    text = _user_text(record)
    if text is None or record.get("isMeta") or record.get("isCompactSummary"):
        return False
    return not text.lstrip().startswith(NOT_A_PROMPT_PREFIXES + (INTERRUPT_MARKER,))


def interrupted_at(transcript_path):
    """When the turn was last abandoned with Escape, or 0.

    Escape fires no hook, so the file goes on saying "running a tool" and the next
    prompt looks like one typed into a turn in progress. The CLI does write the
    interruption into the transcript, and it is always near the end when it matters:
    nothing is appended after it until the user does something.
    """
    if not transcript_path:
        return 0.0
    try:
        size = os.path.getsize(transcript_path)
        with open(transcript_path, "rb") as handle:
            if size > TRANSCRIPT_TAIL_BYTES:
                handle.seek(size - TRANSCRIPT_TAIL_BYTES)
                handle.readline()
            lines = handle.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return 0.0
    for line in reversed(lines):
        if INTERRUPT_MARKER not in line:
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if _is_interrupt(record):
            return _parse_timestamp(record.get("timestamp"))
    return 0.0


def _newest_usage(lines):
    """Context size and the turn's own output, from the transcript's tail.

    Two different numbers, and reporting one as the other is what made the island
    disagree with the CLI's own footer:

      * context - what the window currently holds, nearly all of it cached reads. It is
        the newest assistant message's input side, not a sum: each message re-reads the
        whole conversation, so adding them up would count the context once per message.
      * output  - what this turn has generated, summed over the turn's assistant
        messages. That is the figure the CLI shows, and a turn is many messages.

    The usage block is repeated on every content block of one message (thinking, text,
    tool_use all carry it), so messages are counted once by id.
    """
    context = None
    model = ""
    output = 0
    seen = set()
    found = False
    # The turn's opening prompt: when the CLI started counting, which is what its own
    # footer shows. A session whose clock was never set, or was lost with its file,
    # takes it from here rather than from the moment the island happened to look. The
    # first *answer* is not it - thinking before the first tool call is part of the
    # turn, and reading the clock from there lost half a minute of it.
    turn_started = 0.0
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if _is_user_prompt(record):
            turn_started = _parse_timestamp(record.get("timestamp")) or turn_started
            break                       # the turn starts here
        if record.get("isSidechain"):
            continue
        if record.get("type") == "system" and record.get("subtype") == "compact_boundary":
            # Whatever was in the window before this is gone. The turn may well carry
            # on across it, so its output is still summed.
            if context is None:
                context = 0
                found = True
            continue
        message = record.get("message") or {}
        usage = message.get("usage") or record.get("usage")
        if not isinstance(usage, dict):
            continue
        found = True
        if context is None:
            context = ((usage.get("input_tokens") or 0)
                       + (usage.get("cache_read_input_tokens") or 0)
                       + (usage.get("cache_creation_input_tokens") or 0))
            model = str(message.get("model") or "")
        key = message.get("id") or id(record)
        if key in seen:
            continue
        seen.add(key)
        output += usage.get("output_tokens") or 0
    if not found:
        return None
    return {"tokensIn": int(context or 0), "tokensOut": int(output), "model": model,
            "turnStartedAtFromTranscript": turn_started}


def load(path):
    try:
        with open(path, "r") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return {}


def store(path, data):
    # A tmp file per process, never a shared one. Hooks are asynchronous and several run
    # at once around a tool call; with one `<session>.json.tmp` between them, one writer
    # truncated the file another was part-way through writing and the rename published
    # the wreck. The island then read invalid JSON, the next hook read it back as "no
    # previous state", and the turn's start time - the whole point of the file - was
    # reset to now. Measured: the island's timer restarting every few seconds.
    tmp = "%s.%d.tmp" % (path, os.getpid())
    try:
        with open(tmp, "w") as handle:
            json.dump(data, handle)
        os.replace(tmp, path)      # the island may read at any moment
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


class SessionLock:
    """Serialises the read-modify-write across the hooks running at once.

    Without it two hooks both read the state, both update their own copy, and whichever
    lands last silently drops the other's work - a `PostToolUse` carrying fresh token
    counts losing to a `PreToolUse` that had none.
    """

    def __init__(self, path):
        self.path = path + ".lock"
        self.handle = None

    def __enter__(self):
        try:
            self.handle = open(self.path, "w")
            fcntl.flock(self.handle, fcntl.LOCK_EX)
        except OSError:
            self.handle = None      # a status light never blocks the agent
        return self

    def __exit__(self, *exc):
        if self.handle is None:
            return False
        try:
            fcntl.flock(self.handle, fcntl.LOCK_UN)
            self.handle.close()
        except OSError:
            pass
        return False


def state_for(event, payload, previous):
    """The one thing the island shows: what this session is doing right now."""
    tool = str(payload.get("tool_name") or "")
    if event == "SessionStart":
        if payload.get("source") == "compact" and previous.get("state") == "compacting":
            # The CLI starts a "new" session once the summary is in. Compacting on its
            # own initiative it then carries on with the turn; asked to, it is finished.
            if previous.get("compactTrigger") == "auto":
                return "working", ""
            return "done", ""
        return "idle", ""
    if event == "UserPromptSubmit":
        return "working", ""
    if event == "PreToolUse":
        # A question put to the user blocks the turn until it is answered, which is a
        # different thing from working and the island treats it as one.
        if tool in ("AskUserQuestion", "ExitPlanMode"):
            return "asking", tool
        return "tool", tool
    if event == "PostToolUse":
        return "working", ""
    if event == "Notification":
        # A question left open is nudged by the CLI a few seconds later, in the words it
        # uses for a permission prompt. It is still a question: the island went from
        # "waiting for your answer" to "needs your approval" with nothing to approve.
        if previous.get("state") == "asking":
            return "asking", previous.get("tool", "")
        message = str(payload.get("message") or "").lower()
        if "permission" in message or "approve" in message:
            return "needsAction", previous.get("tool", "")
        # The CLI also notifies when it has been waiting on the user for a while.
        return "waitingInput", ""
    if event == "PreCompact":
        return "compacting", ""
    if event == "Stop":
        return "done", ""
    # SubagentStop falls through: a subagent finishing is the turn carrying on, and
    # calling it done both blanked the island mid-turn and restarted the clock at the
    # next tool call.
    return previous.get("state", "idle"), previous.get("tool", "")


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, OSError):
        payload = {}
    if not isinstance(payload, dict):
        payload = {}

    event = str(payload.get("hook_event_name") or "")
    session_id = str(payload.get("session_id") or "")
    if session_id == "":
        return

    os.makedirs(STATE_DIR, exist_ok=True)
    path = os.path.join(STATE_DIR, session_id + ".json")

    if event == "SessionEnd":
        try:
            os.remove(path)
        except OSError:
            pass
        return

    with SessionLock(path):
        write_state(path, payload, event, session_id)


def write_state(path, payload, event, session_id):
    previous = load(path)
    pid, comm = owning_agent(int(previous.get("pid") or 0))
    now = time.time()
    state, tool = state_for(event, payload, previous)

    record = dict(previous)
    record.update({
        "sessionId": session_id,
        "pid": pid,
        "agent": comm or previous.get("agent") or "claude",
        "state": state,
        "tool": tool,
        "event": event,
        "cwd": str(payload.get("cwd") or previous.get("cwd") or ""),
        "updatedAt": now,
    })
    record.setdefault("sessionStartedAt", now)

    # The turn's clock is the CLI's own, written once when the turn begins and left
    # alone afterwards. Read back from this file it survives a shell reload, a crash or
    # a `qs kill` - the island used to measure the turn itself and restart it at every
    # one of those.
    # A turn begins at the prompt; it is also adopted when the first busy state arrives
    # without one, which is what happens to a session that was already running when the
    # hooks were installed.
    busy = state in ("working", "tool", "asking", "needsAction", "compacting")
    # A turn begins when the agent picks work up from rest - not at every prompt. A
    # message typed while it is already working is queued into the turn in progress,
    # and the CLI goes on counting from where it started; restarting the clock there
    # made the island disagree with the CLI's own footer by minutes.
    transcript = find_transcript(session_id, payload.get("transcript_path"),
                                 previous.get("transcriptPath"))
    if transcript:
        record["transcriptPath"] = transcript

    resting = previous.get("state", "idle") in ("idle", "done", "waitingInput", "")
    # Only the two events that open work can find a turn abandoned: a tool call still
    # reporting back after Escape is the old turn's, and must not reopen it.
    opening = event == "UserPromptSubmit" \
        or (event == "PreCompact" and payload.get("trigger") != "auto")
    if opening and not resting:
        resting = interrupted_at(transcript) > float(previous.get("turnStartedAt") or 0)
    adopted = False
    if busy and resting:
        # Work picked up from rest, whatever announced it: a prompt, a compaction, or
        # a background task waking the agent with no prompt at all.
        record["turnStartedAt"] = now
        record["tokensOut"] = 0
    elif busy and not previous.get("turnStartedAt"):
        # A session that was already running when the hooks were installed adopts the
        # first busy state as its start; an existing one is never moved forward.
        record["turnStartedAt"] = now
        adopted = True
    if event == "PreCompact":
        record["compactTrigger"] = str(payload.get("trigger") or "manual")
    if state in ("idle", "done", "waitingInput") and event in ("Stop", "SessionStart", "Notification"):
        record["turnEndedAt"] = now
    compacted = event == "SessionStart" and payload.get("source") == "compact"
    if compacted:
        record["tokensIn"] = 0      # the window was just emptied; the next answer says

    usage = read_usage(transcript)
    if usage:
        hinted = usage.pop("turnStartedAtFromTranscript", 0.0)
        # A turn being opened has produced nothing yet, and the transcript's newest
        # figures are still the last turn's - the new prompt may not be in it yet.
        if not (busy and resting) and not compacted:
            record.update(usage)
        # An adopted clock is late by however long the turn had already run. The
        # prompt's own timestamp is what the CLI counts from, so it is taken instead -
        # but only then: a clock set by the turn's own opening event is already right,
        # and "the newest prompt" next to it may be the one before an interruption.
        if adopted and hinted > float(record.get("turnEndedAt") or 0):
            record["turnStartedAt"] = min(record["turnStartedAt"], hinted)

    try:
        store(path, record)
    except OSError:
        pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Never fail the agent for the sake of a status light.
        pass
    sys.exit(0)
