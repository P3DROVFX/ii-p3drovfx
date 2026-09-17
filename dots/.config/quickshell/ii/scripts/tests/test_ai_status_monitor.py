#!/usr/bin/env python3
"""Contract tests for services/ai_status_monitor.py (the Dynamic Island AI fallback).

These lock in the behaviours whose absence produced the "timer restarts every three
seconds" bug: the verdict must depend on the CPU *rate*, not on the sampling interval,
and it must not react to the agent's own tool children or to look-alike command lines.
"""
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
