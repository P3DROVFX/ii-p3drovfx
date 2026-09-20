#!/usr/bin/env python3
"""Contract tests for services/ai_status_monitor.py (the Dynamic Island AI fallback).

These lock in the behaviours whose absence produced the "timer restarts every three
seconds" bug: the verdict must depend on the CPU *rate*, not on the sampling interval,
and it must not react to the agent's own tool children or to look-alike command lines.
"""
import json
import os
import sys
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "services"))
import ai_status_monitor as monitor  # noqa: E402

CLK = monitor.CLK_TCK


class FakeProc:
    """A /proc tree on disk, so scan_candidates() can be pointed at it."""

    def __init__(self, tmpdir):
        self.root = tmpdir

    def add(self, pid, comm, argv0=None, ticks=0):
        path = os.path.join(self.root, str(pid))
        os.makedirs(path, exist_ok=True)
        with open(os.path.join(path, "comm"), "w") as handle:
            handle.write(comm + "\n")
        with open(os.path.join(path, "cmdline"), "wb") as handle:
            handle.write(((argv0 or comm) + "\0").encode())
        self.set_ticks(pid, ticks)

    def set_ticks(self, pid, ticks):
        # utime is field 14 overall, i.e. index 11 after the comm parenthesis.
        fields = ["0"] * 30
        fields[11] = str(ticks)   # utime
        fields[12] = "0"          # stime
        body = " ".join(fields)
        with open(os.path.join(self.root, str(pid), "stat"), "w") as handle:
            handle.write(f"{pid} (fake) S 1 {body}\n")


def ticks_for(percent, seconds):
    return int(percent / 100.0 * CLK * seconds)


class RateNotIntervalTests(unittest.TestCase):
    """The bug: the same load classified differently per sampling interval."""

    def _run_at_interval(self, percent, interval, samples=8):
        tracker = monitor.AgentTracker()
        now = 1000.0
        verdicts = []
        total = 0
        for _ in range(samples):
            candidates = [{"pid": 1, "key": "claude", "ticks": total}]
            working = tracker.sample(candidates, now)
            verdicts.append(bool(working))
            total += ticks_for(percent, interval)
            now += interval
        return verdicts

    def test_steady_idle_load_never_activates_at_any_interval(self):
        # 8% CPU was reported ACTIVE at a 3s interval and IDLE at 1s by the old code.
        for interval in (1.0, 2.0, 3.0, 8.0):
            with self.subTest(interval=interval):
                self.assertNotIn(True, self._run_at_interval(8.0, interval),
                                 f"8% CPU must never count as working (interval {interval}s)")

    def test_real_work_activates_at_any_interval(self):
        for interval in (1.0, 2.0, 3.0):
            with self.subTest(interval=interval):
                self.assertIn(True, self._run_at_interval(90.0, interval),
                              f"90% CPU must count as working (interval {interval}s)")


class StabilityTests(unittest.TestCase):
    def test_turn_start_survives_a_brief_dip(self):
        """A pause between tool calls must not restart the timer."""
        tracker = monitor.AgentTracker()
        now, total = 1000.0, 0
        started = None
        for step, percent in enumerate([90, 90, 90, 0, 0, 90, 90]):
            working = tracker.sample([{"pid": 1, "key": "claude", "ticks": total}], now)
            if working:
                if started is None:
                    started = working[0]["startedAtEpoch"]
                else:
                    self.assertEqual(working[0]["startedAtEpoch"], started,
                                     f"turn start moved at step {step}")
            total += ticks_for(percent, 2.0)
            now += 2.0
        self.assertIsNotNone(started, "the agent never registered as working")

    def test_sustained_idle_stops_the_agent(self):
        tracker = monitor.AgentTracker()
        now, total = 1000.0, 0
        for percent in [90, 90, 90]:
            tracker.sample([{"pid": 1, "key": "claude", "ticks": total}], now)
            total += ticks_for(percent, 2.0)
            now += 2.0
        self.assertTrue(tracker.sample([{"pid": 1, "key": "claude", "ticks": total}], now))
        # Idle must be reached promptly: the island shows a live timer, so a long tail
        # would keep claiming the agent is working after it stopped.
        silence_started = now
        while True:
            now += 2.0
            working = tracker.sample([{"pid": 1, "key": "claude", "ticks": total}], now)
            if not working:
                break
            self.assertLess(now - silence_started, 10.0,
                            "took too long to notice the agent stopped")
        self.assertGreaterEqual(now - silence_started, monitor.STOP_SECONDS,
                                "stopped before the grace period; a pause between tool "
                                "calls would end the turn")

    def test_exited_pid_is_forgotten(self):
        tracker = monitor.AgentTracker()
        tracker.sample([{"pid": 1, "key": "claude", "ticks": 0}], 1000.0)
        tracker.sample([], 1002.0)
        self.assertEqual(tracker.states, {})


class ToolChildTests(unittest.TestCase):
    """The old detector called any `zsh`/`python` child "work", so a persistent shell
    pinned the island to busy forever. A child only counts when it is new, young, or
    actually burning CPU."""

    def _sample(self, tracker, children, now, own_ticks=0):
        return tracker.sample(
            [{"pid": 1, "key": "claude", "ticks": own_ticks, "children": children}], now)

    def test_persistent_idle_child_is_not_work(self):
        tracker = monitor.AgentTracker()
        old_child = [{"pid": 50, "ticks": 500, "age": 3600.0}]
        self._sample(tracker, old_child, 1000.0)          # baseline
        verdicts = []
        now = 1000.0
        for _ in range(8):
            now += 2.0
            verdicts.append(bool(self._sample(tracker, old_child, now)))
        self.assertNotIn(True, verdicts,
                         "an idle long-lived child must never count as work")

    def test_new_tool_child_starts_a_turn_immediately(self):
        tracker = monitor.AgentTracker()
        self._sample(tracker, [], 1000.0)
        working = self._sample(tracker, [{"pid": 77, "ticks": 0, "age": 0.2}], 1002.0)
        self.assertTrue(working, "a tool call in flight is work")

    def test_busy_long_running_child_keeps_the_turn_alive(self):
        """A build that runs for minutes is work, even past the freshness window."""
        tracker = monitor.AgentTracker()
        now, child_ticks = 1000.0, 0
        self._sample(tracker, [{"pid": 88, "ticks": child_ticks, "age": 120.0}], now)
        verdicts = []
        for _ in range(5):
            now += 2.0
            child_ticks += ticks_for(80.0, 2.0)
            verdicts.append(bool(self._sample(
                tracker, [{"pid": 88, "ticks": child_ticks, "age": 120.0 + now - 1000.0}], now)))
        self.assertTrue(all(verdicts), "a busy child must keep the turn alive")

    def test_persistent_servers_are_not_children_evidence(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            proc = FakeProc(tmp)
            proc.add(1, "claude", ticks=0)
            os.makedirs(os.path.join(tmp, "1", "task", "1"), exist_ok=True)
            with open(os.path.join(tmp, "1", "task", "1", "children"), "w") as handle:
                handle.write("90 91\n")
            with open(os.path.join(tmp, "uptime"), "w") as handle:
                handle.write("5000.0 4000.0\n")
            proc.add(90, "node", argv0="/usr/bin/node-mcp-server", ticks=10)
            proc.add(91, "language_server", argv0="language_server_linux_x64", ticks=10)
            children = monitor.collect_tool_children(tmp, 1)
            self.assertEqual(children, [],
                             "MCP servers and language servers are not tool calls")


class MatchingTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        self._tmp = tempfile.TemporaryDirectory()
        self.proc = FakeProc(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_agent_cli_is_found(self):
        self.proc.add(4242, "claude", ticks=10)
        found = monitor.scan_candidates(self.proc.root)
        self.assertEqual([c["pid"] for c in found], [4242])

    def test_claude_code_own_shell_snapshot_is_ignored(self):
        """The exact false positive the old substring matcher reported."""
        self.proc.add(4243, "zsh",
                      argv0="/usr/bin/zsh",
                      ticks=10)
        self.assertEqual(monitor.scan_candidates(self.proc.root), [])

    def test_editor_opened_in_a_claude_directory_is_ignored(self):
        self.proc.add(4244, "nvim", argv0="/usr/bin/nvim", ticks=5)
        self.assertEqual(monitor.scan_candidates(self.proc.root), [])

    def test_mcp_server_started_by_the_cli_is_ignored(self):
        self.proc.add(4245, "node", argv0="/usr/bin/node", ticks=99)
        self.assertEqual(monitor.scan_candidates(self.proc.root), [])


class OutputTests(unittest.TestCase):
    def test_runtime_is_not_part_of_the_change_test(self):
        """Otherwise every sample is a "change" and the QML side rebuilds its widgets."""
        a = [{"id": "claude_1", "state": "running", "runtime": 3}]
        b = [{"id": "claude_1", "state": "running", "runtime": 4}]
        self.assertEqual(monitor.reported_shape(a), monitor.reported_shape(b))

    def test_a_new_agent_is_a_change(self):
        a = [{"id": "claude_1", "state": "running", "runtime": 3}]
        b = a + [{"id": "gemini_2", "state": "running", "runtime": 1}]
        self.assertNotEqual(monitor.reported_shape(a), monitor.reported_shape(b))

    def test_sampling_interval_never_depends_on_the_verdict(self):
        self.assertNotEqual(monitor.INTERVAL_WITH_CANDIDATES, 1.0,
                            "the 1s/3s alternation is what made the detector oscillate")
        self.assertGreater(monitor.INTERVAL_IDLE, monitor.INTERVAL_WITH_CANDIDATES)


if __name__ == "__main__":
    unittest.main(verbosity=2)


class HookPathTests(unittest.TestCase):
    """The hook is the authority: what it says is what the island shows.

    These lock in the reason it exists. CPU cannot tell a turn spent thinking from an
    idle process, nor working from waiting-for-you, and a shell-side clock restarted the
    turn timer on every reload.
    """

    def setUp(self):
        import tempfile
        self.tmp = tempfile.mkdtemp()
        self.state_dir = os.path.join(self.tmp, "ai-status")
        os.makedirs(self.state_dir)
        self.proc_root = os.path.join(self.tmp, "proc")
        os.makedirs(os.path.join(self.proc_root, "4242"))     # a live pid
        self.now = 1_000_000.0

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, session="s1", pid=4242, **fields):
        import json as jsonlib
        record = {"sessionId": session, "pid": pid, "agent": "claude",
                  "state": "working", "updatedAt": self.now}
        record.update(fields)
        with open(os.path.join(self.state_dir, session + ".json"), "w") as handle:
            jsonlib.dump(record, handle)
        return record

    def agents(self, now=None):
        now = self.now if now is None else now
        sessions = monitor.read_hook_sessions(now, state_dir=self.state_dir,
                                              proc_root=self.proc_root)
        return monitor.hook_agents(sessions, now)

    def test_working_session_is_reported(self):
        self.write(state="working", turnStartedAt=self.now - 30)
        agents = self.agents()
        self.assertEqual(len(agents), 1)
        self.assertEqual(agents[0]["state"], "working")
        self.assertEqual(agents[0]["pid"], 4242)

    def test_idle_session_is_not_an_activity(self):
        self.write(state="idle")
        self.assertEqual(self.agents(), [])

    def test_a_question_asks_for_attention(self):
        self.write(state="asking", tool="AskUserQuestion", turnStartedAt=self.now - 5)
        agent = self.agents()[0]
        self.assertTrue(agent["requiresAttention"])
        self.assertEqual(agent["tool"], "AskUserQuestion")

    def test_a_permission_prompt_asks_for_attention(self):
        self.write(state="needsAction", turnStartedAt=self.now - 5)
        self.assertTrue(self.agents()[0]["requiresAttention"])

    def test_working_does_not_ask_for_attention(self):
        self.write(state="working", turnStartedAt=self.now - 5)
        self.assertFalse(self.agents()[0]["requiresAttention"])

    def test_the_turn_clock_is_the_cli_s_own(self):
        # The point of the whole hook path: a restart of the shell must not restart the
        # timer, so the start time is read from the file rather than measured here.
        self.write(state="working", turnStartedAt=self.now - 125)
        agent = self.agents()[0]
        self.assertEqual(agent["startedAtEpoch"], int(self.now - 125))
        self.assertEqual(agent["runtime"], 125)

    def test_done_is_announced_then_rests_until_the_next_prompt(self):
        self.write(state="done", turnStartedAt=self.now - 60, turnEndedAt=self.now - 1)
        self.assertEqual(len(self.agents()), 1)
        self.assertEqual(self.agents()[0]["runtime"], 59)   # how long the turn took
        self.assertTrue(self.agents()[0]["announce"])
        # The session is still open an hour later, so it is still there - said once,
        # with the clock stopped where the turn ended.
        rested = self.agents(now=self.now + 3600)[0]
        self.assertFalse(rested["announce"])
        self.assertEqual((rested["state"], rested["runtime"], rested["startedAtEpoch"]),
                         ("done", 59, 0))

    def test_a_session_that_never_had_a_turn_has_nothing_to_rest_on(self):
        self.write(state="waitingInput", turnStartedAt=0, turnEndedAt=0)
        self.assertEqual(self.agents(), [])

    def test_a_dead_session_is_dropped_and_its_file_removed(self):
        self.write(session="gone", pid=999999, state="working",
                   updatedAt=self.now - monitor.HOOK_FRESH_SECONDS - 1)
        self.assertEqual(self.agents(), [])
        self.assertFalse(os.path.exists(os.path.join(self.state_dir, "gone.json")))

    def test_a_session_still_writing_survives_a_pid_it_cannot_prove(self):
        # Identifying the CLI behind an async hook can fail, and pruning the file on
        # that restarted the turn clock and lost the turn's tokens with it.
        self.write(session="live", pid=999999, state="working", turnStartedAt=self.now)
        self.assertEqual(len(self.agents()), 1)
        self.assertTrue(os.path.exists(os.path.join(self.state_dir, "live.json")))

    def test_a_stale_file_is_removed(self):
        self.write(state="working", updatedAt=self.now - monitor.HOOK_STALE_SECONDS - 1)
        self.assertEqual(self.agents(), [])
        self.assertFalse(os.path.exists(os.path.join(self.state_dir, "s1.json")))

    def test_token_counts_are_carried_through(self):
        self.write(state="working", turnStartedAt=self.now, tokensIn=12345,
                   tokensOut=678, model="claude-opus-5")
        agent = self.agents()[0]
        self.assertEqual(agent["tokensIn"], 12345)
        self.assertEqual(agent["tokensOut"], 678)
        self.assertEqual(agent["model"], "claude-opus-5")

    def test_a_missing_directory_is_not_an_error(self):
        self.assertEqual(monitor.read_hook_sessions(self.now,
                         state_dir=os.path.join(self.tmp, "nope")), [])


class MergeTests(unittest.TestCase):
    def test_the_hook_wins_over_the_guess_for_the_same_process(self):
        hooked = [{"id": "claude_s1", "pid": 42, "state": "asking"}]
        inferred = [{"id": "claude_42", "pid": 42, "state": "running"}]
        merged = monitor.merge(hooked, inferred)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["state"], "asking")

    def test_a_cli_with_no_hook_still_gets_the_fallback(self):
        hooked = [{"id": "claude_s1", "pid": 42, "state": "working"}]
        inferred = [{"id": "gemini_7", "pid": 7, "state": "running"}]
        self.assertEqual(len(monitor.merge(hooked, inferred)), 2)

    def test_a_hooked_session_with_nothing_to_show_is_still_not_guessed_at(self):
        # Interrupted, finished or idle at its prompt, the session leaves the island -
        # and the guess used to take the same process straight back: "Working", on its
        # own clock, with no tokens, while the CLI did nothing but redraw its input box.
        inferred = [{"id": "claude_42", "pid": 42, "state": "running"}]
        sessions = [{"sessionId": "s1", "pid": 42, "agent": "claude", "state": "idle"}]
        self.assertEqual(monitor.merge([], inferred, sessions), [])

    def test_a_session_whose_process_is_unknown_silences_the_guess_for_its_cli(self):
        inferred = [{"id": "claude_42", "pid": 42, "state": "running"},
                    {"id": "gemini_7", "pid": 7, "state": "running"}]
        sessions = [{"sessionId": "s1", "pid": 0, "agent": "claude", "state": "idle"}]
        self.assertEqual([agent["id"] for agent in monitor.merge([], inferred, sessions)],
                         ["gemini_7"])

    def test_the_tool_in_use_is_part_of_the_change_test(self):
        # Moving from one tool to the next is a change worth telling the island about;
        # the runtime ticking is not.
        one = [{"id": "a", "state": "tool", "tool": "Bash", "requiresAttention": False}]
        two = [{"id": "a", "state": "tool", "tool": "Edit", "requiresAttention": False}]
        self.assertNotEqual(monitor.reported_shape(one), monitor.reported_shape(two))


class InterruptTests(unittest.TestCase):
    """Escape ends a turn and fires no hook. The transcript is what says so."""

    def setUp(self):
        import tempfile
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "transcript.jsonl")
        self.proc_root = os.path.join(self.tmp, "proc")
        os.makedirs(os.path.join(self.proc_root, "4242"))
        self.now = 1789939000.0
        monitor._transcripts.clear()

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)
        monitor._transcripts.clear()

    def write_transcript(self, *records):
        with open(self.path, "w") as handle:
            for record in records:
                handle.write(json.dumps(record) + "\n")

    @staticmethod
    def interrupt(stamp):
        return {"type": "user", "timestamp": stamp,
                "message": {"role": "user",
                            "content": [{"type": "text",
                                         "text": "[Request interrupted by user]"}]}}

    @staticmethod
    def assistant(stamp, context=0, output=10, ident="m1"):
        return {"type": "assistant", "timestamp": stamp,
                "message": {"role": "assistant", "id": ident,
                            "usage": {"input_tokens": 0,
                                      "cache_read_input_tokens": context,
                                      "output_tokens": output},
                            "content": [{"type": "text", "text": "hello"}]}}

    @staticmethod
    def prompt(stamp, text="do the thing"):
        return {"type": "user", "timestamp": stamp,
                "message": {"role": "user",
                            "content": [{"type": "text", "text": text}]}}

    def agent(self, state="working", turn_started=None, transcript=None):
        return {"sessionId": "s1", "pid": 4242, "agent": "claude", "state": state,
                "updatedAt": self.now,
                "turnStartedAt": self.now - 60 if turn_started is None else turn_started,
                "transcriptPath": self.path if transcript is None else transcript}

    def test_an_interrupt_after_the_turn_started_ends_it(self):
        self.write_transcript(self.assistant("2026-09-20T21:00:00.000Z"),
                              self.interrupt("2026-09-20T21:16:39.316Z"))
        started = monitor._parse_timestamp("2026-09-20T21:10:00.000Z")
        ended = monitor._parse_timestamp("2026-09-20T21:16:39.316Z")
        # Said for a moment, with how long the turn ran, the way "done" is...
        agents = monitor.hook_agents([self.agent(state="tool", turn_started=started)], ended + 2)
        self.assertEqual([agent["state"] for agent in agents], ["interrupted"])
        self.assertEqual(agents[0]["runtime"], int(ended - started))
        self.assertEqual(agents[0]["startedAtEpoch"], 0)      # nothing left to count
        self.assertTrue(agents[0]["announce"])
        # ...and it stays interrupted afterwards, although the file will say "running a
        # tool" until the next prompt: nothing tells the hook that Escape was pressed.
        rested = monitor.hook_agents([self.agent(state="tool", turn_started=started)],
                                     ended + 3600)
        self.assertEqual([(agent["state"], agent["announce"], agent["runtime"])
                          for agent in rested], [("interrupted", False, int(ended - started))])

    def test_a_turn_that_just_ended_leads_the_sessions_still_working(self):
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"))
        done = dict(self.agent(state="done"), sessionId="s2", turnEndedAt=self.now - 1)
        agents = monitor.hook_agents([self.agent(), done], self.now)
        agents.sort(key=lambda agent: agent["priority"])
        self.assertEqual([agent["state"] for agent in agents], ["done", "working"])

    def test_an_older_interrupt_does_not_end_the_current_turn(self):
        self.write_transcript(self.interrupt("2026-09-20T21:00:00.000Z"),
                              self.assistant("2026-09-20T21:20:00.000Z"))
        started = monitor._parse_timestamp("2026-09-20T21:10:00.000Z")
        agents = monitor.hook_agents([self.agent(turn_started=started)], self.now)
        self.assertEqual(len(agents), 1)

    def test_a_transcript_that_cannot_be_read_is_not_an_interrupt(self):
        agents = monitor.hook_agents([self.agent(transcript="/nope/missing.jsonl")], self.now)
        self.assertEqual(len(agents), 1)

    def test_the_marker_quoted_inside_a_tool_result_is_not_an_interrupt(self):
        # The phrase turns up in tool output (a grep over one's own transcript does it),
        # and mistaking that for an interrupt would blank a working agent.
        self.write_transcript({
            "type": "user", "timestamp": "2026-09-20T21:16:39.316Z",
            "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "t1",
                 "content": "grep found: [Request interrupted by user]"}]}})
        started = monitor._parse_timestamp("2026-09-20T21:10:00.000Z")
        self.assertEqual(len(monitor.hook_agents([self.agent(turn_started=started)], self.now)), 1)

    def test_only_what_was_appended_is_read_again(self):
        # The transcript is megabytes and this runs every second while an agent works,
        # so each record is parsed once and the file is only ever read forward.
        self.write_transcript(self.interrupt("2026-09-20T21:16:39.316Z"))
        first = monitor.interrupted_at(self.path)
        self.assertGreater(first, 0)
        tail = monitor._transcripts[self.path]
        self.assertEqual(tail.offset, os.path.getsize(self.path))
        self.assertEqual(monitor.interrupted_at(self.path), first)
        with open(self.path, "a") as handle:
            handle.write(json.dumps(self.assistant("2026-09-20T21:17:00.000Z")) + "\n")
        self.assertEqual(monitor.interrupted_at(self.path), first)
        self.assertEqual(tail.offset, os.path.getsize(self.path))

    def test_a_half_written_record_is_left_for_the_next_look(self):
        # The CLI appends as it goes; a line without its newline yet is not a record.
        self.write_transcript(self.interrupt("2026-09-20T21:16:39.316Z"))
        monitor.interrupted_at(self.path)
        with open(self.path, "a") as handle:
            handle.write('{"type": "user", "timestamp": "2026-09-20T21:18:0')
        self.assertEqual(monitor.interrupted_at(self.path),
                         monitor._parse_timestamp("2026-09-20T21:16:39.316Z"))

    def test_an_interrupt_inside_a_tool_result_ends_the_turn(self):
        # Escape pressed while a tool runs is recorded there and nowhere else; the
        # island counted those turns forever.
        self.write_transcript({
            "type": "user", "timestamp": "2026-09-20T21:16:39.316Z",
            "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "t1",
                 "content": "[Request interrupted by user for tool use]"}]}})
        started = monitor._parse_timestamp("2026-09-20T21:10:00.000Z")
        agents = monitor.hook_agents([self.agent(turn_started=started)], self.now + 3600)
        self.assertEqual([(agent["state"], agent["startedAtEpoch"]) for agent in agents],
                         [("interrupted", 0)])

    def test_the_turn_starts_at_the_prompt_the_cli_picked_up(self):
        # The hook file can be late, or lost with its session's file, and the clock
        # then started at whatever the island first noticed. The prompt says when the
        # CLI started counting.
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"),
                              self.assistant("2026-09-20T21:00:36.000Z"))
        late = monitor._parse_timestamp("2026-09-20T21:00:36.000Z")
        agents = monitor.hook_agents([self.agent(turn_started=late)], self.now)
        self.assertEqual(agents[0]["startedAtEpoch"],
                         int(monitor._parse_timestamp("2026-09-20T21:00:00.000Z")))

    def test_a_message_typed_into_a_running_turn_does_not_restart_the_clock(self):
        # The CLI hands it to the model as an attachment and goes on counting from
        # where it started; so does the island.
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"),
                              self.assistant("2026-09-20T21:00:36.000Z"),
                              {"type": "attachment", "timestamp": "2026-09-20T21:05:00.000Z",
                               "attachment": {"type": "queued_command", "prompt": "and this"}})
        started = monitor._parse_timestamp("2026-09-20T21:00:00.000Z")
        agents = monitor.hook_agents([self.agent(turn_started=started)], self.now)
        self.assertEqual(agents[0]["startedAtEpoch"], int(started))

    def test_a_prompt_after_an_interrupt_is_a_new_turn(self):
        # The file still carries the abandoned turn's clock when the hook missed the
        # restart; the island went on counting the old turn, minutes ahead of the CLI.
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"),
                              self.interrupt("2026-09-20T21:04:00.000Z"),
                              self.prompt("2026-09-20T21:05:00.000Z"))
        stale = monitor._parse_timestamp("2026-09-20T21:00:00.031Z")
        agents = monitor.hook_agents([self.agent(turn_started=stale)], self.now)
        self.assertEqual([agent["state"] for agent in agents], ["working"])
        self.assertEqual(agents[0]["startedAtEpoch"],
                         int(monitor._parse_timestamp("2026-09-20T21:05:00.000Z")))

    def test_a_turn_opened_without_a_prompt_runs_on_the_hooks_clock(self):
        # A skill's slash command or a background task reporting back leaves no typed
        # prompt behind; the newest one in the transcript belongs to a turn that ended.
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"),
                              self.assistant("2026-09-20T21:00:36.000Z"))
        record = self.agent(turn_started=monitor._parse_timestamp("2026-09-20T21:10:00.000Z"))
        record["turnEndedAt"] = monitor._parse_timestamp("2026-09-20T21:02:00.000Z")
        self.assertEqual(monitor.hook_agents([record], self.now)[0]["startedAtEpoch"],
                         int(record["turnStartedAt"]))

    def test_the_clis_own_bookkeeping_is_not_a_prompt(self):
        opened = "2026-09-20T21:00:00.000Z"
        noise = [self.prompt("2026-09-20T21:01:00.000Z", "<local-command-stdout>ok"),
                 self.prompt("2026-09-20T21:01:01.000Z", "<command-name>/model</command-name>"),
                 dict(self.prompt("2026-09-20T21:01:02.000Z", "[Image: source: x]"), isMeta=True),
                 dict(self.prompt("2026-09-20T21:01:03.000Z", "This session is being continued"),
                      isCompactSummary=True),
                 dict(self.prompt("2026-09-20T21:01:04.000Z", "look into it"), isSidechain=True)]
        self.write_transcript(self.prompt(opened), *noise)
        self.assertEqual(monitor.transcript_tail(self.path).turn_started,
                         monitor._parse_timestamp(opened))

    def test_the_context_is_empty_after_a_compaction_until_the_next_answer(self):
        # The file's figure is the window as it was before; showing it was showing a
        # context that no longer exists.
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"),
                              self.assistant("2026-09-20T21:00:36.000Z", context=150000),
                              self.prompt("2026-09-20T21:02:00.000Z", "/compact"),
                              {"type": "system", "subtype": "compact_boundary",
                               "timestamp": "2026-09-20T21:04:00.000Z"})
        record = self.agent(state="compacting")
        record["tokensIn"] = 150000
        self.assertEqual(monitor.hook_agents([record], self.now)[0]["tokensIn"], 0)

    def test_a_transcript_first_seen_mid_turn_is_read_back_to_its_prompt(self):
        # A shell reload lands in the middle of turns, and one pasted screenshot is more
        # than the first window: the turn came back with a late clock and part of its
        # output.
        bulky = self.assistant("2026-09-20T21:00:40.000Z", output=50, ident="big")
        bulky["message"]["content"][0]["text"] = "x" * (monitor.TRANSCRIPT_TAIL_BYTES + 1024)
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"),
                              self.assistant("2026-09-20T21:00:36.000Z", output=25, ident="m1"),
                              bulky)
        tail = monitor.transcript_tail(self.path)
        self.assertEqual(tail.turn_started, monitor._parse_timestamp("2026-09-20T21:00:00.000Z"))
        self.assertEqual(tail.output, 75)

    def test_token_counts_follow_the_transcript_between_events(self):
        # Hook events can be a tool call apart; the counters would sit a minute behind
        # the CLI's own footer.
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"),
                              self.assistant("2026-09-20T21:00:36.000Z", context=90000,
                                             output=1200, ident="m1"),
                              self.assistant("2026-09-20T21:01:36.000Z", context=91000,
                                             output=800, ident="m2"))
        record = self.agent()
        record.update({"tokensIn": 1, "tokensOut": 2})
        entry = monitor.hook_agents([record], self.now)[0]
        self.assertEqual(entry["tokensIn"], 91000)
        self.assertEqual(entry["tokensOut"], 2000)

    def test_usage_repeated_on_every_block_of_one_message_counts_once(self):
        usage = {"input_tokens": 5, "cache_read_input_tokens": 90000,
                 "output_tokens": 1200}
        record = {"type": "assistant", "timestamp": "2026-09-20T21:00:36.000Z",
                  "message": {"role": "assistant", "id": "m1", "usage": usage,
                              "content": [{"type": "text", "text": "hi"}]}}
        self.write_transcript(self.prompt("2026-09-20T21:00:00.000Z"), record, dict(record))
        entry = monitor.hook_agents([self.agent()], self.now)[0]
        self.assertEqual(entry["tokensOut"], 1200)

    def test_a_deleted_transcript_reports_no_interrupt(self):
        self.write_transcript(self.interrupt("2026-09-20T21:16:39.316Z"))
        monitor.interrupted_at(self.path)
        os.remove(self.path)
        self.assertEqual(monitor.interrupted_at(self.path), 0.0)
