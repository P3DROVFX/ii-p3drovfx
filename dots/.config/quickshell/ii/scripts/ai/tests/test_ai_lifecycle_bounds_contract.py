#!/usr/bin/env python3
"""Regression contracts for the Phase 6 lifecycle/memory-safety audit.

A subagent audited every place `Ai.qml` and its neighbouring services keep
state that only ever grows, and found eight real gaps (numbered Q1-Q8 in the
audit) plus one more surfaced while reading `AiRunCoordinator.qml`. Two of
the eight were already bounded on inspection (`AiTools.callLog`,
`AiMemory.facts`/`AiDraftStore` drafts) and one was aspirational and not yet
built (a parallel-tool-call cap the current code is already stricter than).
The rest are fixed here:

* Q1 - `root.messageIDs`/`root.messageByID` grew by one QML object per turn
  forever; nothing but an explicit "new chat" ever trimmed them. A very long
  conversation - or `qs ipc call ai ask` scripted in a loop for hours without
  ever starting a new chat - held every `AiMessageData` in RAM for the life
  of the process.
* Q3 - `AiRequest.requestTimeout` clamped only to `Math.max(0, ...)`. A value
  of exactly zero (reachable only by hand-editing config.json outside the
  Settings UI's [30, 1800] clamp) silently dropped *both* the QML watchdog
  and curl's own `--max-time` at once, leaving a hung request with no bound
  but the TCP handshake.
* Q4 - four tools whose handlers can reach the broker's real "pending" async
  state (not just "waiting on a person to click approve") were registered
  with `timeoutMs: 0`, the value the broker exempts *specifically* for the
  approval-wait case. A hung post-approval round trip for any of them would
  never be swept.
* Q6 - `stopGeneration()` cancelled the model stream and the broker's own
  bookkeeping, but left `commandExecutionProc`, `filesToolProc`,
  `ocrToolProc`, `webToolProc`, and a live SongRec recording running to
  completion after "Stop".
* Q7 - the attachment probe/extract `Process` objects had no timeout at all.
  A crash self-healed (closing stdout still fires `acceptProbed`/
  `acceptExtracted`), but a genuine hang froze that job - and everything
  queued behind it - forever.
* Bonus - `AiRunCoordinator.runs` accumulated one entry per exchange for the
  life of the process; nothing ever looks a run up by id once a newer one has
  replaced it as `activeRunId`, so old terminal entries were dead weight.
"""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
REQUEST_QML = (ROOT / "services" / "ai" / "AiRequest.qml").read_text(encoding="utf-8")
REGISTRY_QML = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
RUN_COORDINATOR_QML = (ROOT / "services" / "ai" / "AiRunCoordinator.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


def tool_block(source: str, tool_id: str) -> str:
    """The raw definition object for one tool id, from `{` to its closing `}`."""
    marker = f'id: "{tool_id}",'
    start = source.index(marker)
    # Walk back to the opening brace of this object literal.
    open_brace = source.rindex("{", 0, start)
    depth = 0
    for i in range(open_brace, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[open_brace:i + 1]
    raise AssertionError(f"unterminated block for tool {tool_id!r}")


def field(block: str, name: str):
    match = re.search(rf"^\s*{name}:\s*(.+?),?$", block, re.M)
    return match.group(1).rstrip(",").strip() if match else None


class MessageHistoryCapTests(unittest.TestCase):
    """Q1: a live conversation kept open forever must not grow forever."""

    def test_a_cap_exists_and_is_a_positive_bound(self):
        self.assertIn("readonly property int maxLiveMessages:", AI_QML)
        match = re.search(r"readonly property int maxLiveMessages:\s*(\d+)", AI_QML)
        self.assertIsNotNone(match)
        self.assertGreater(int(match.group(1)), 0)

    def test_the_trim_only_engages_past_the_cap(self):
        trim = body_between(AI_QML, "function trimMessageHistoryIfNeeded() {", "\n    }")
        self.assertIn("root.messageIDs.length - root.maxLiveMessages", trim)
        self.assertIn("if (overflow <= 0)", trim)
        self.assertIn("return", trim)

    def test_trimmed_messages_are_actually_destroyed_not_just_dereferenced(self):
        # Every AiMessageData is created with `root` as its QObject parent
        # (`aiMessageComponent.createObject(root, ...)`); dropping the JS
        # reference alone does not free it. `.destroy()` is the idiom the
        # rest of the file already uses (rollback, removeMessage, forkFrom).
        trim = body_between(AI_QML, "function trimMessageHistoryIfNeeded() {", "\n    }")
        self.assertIn("message.destroy()", trim)
        self.assertIn("delete root.messageByID[id]", trim)

    def test_the_run_in_flight_is_never_a_trim_candidate(self):
        trim = body_between(AI_QML, "function trimMessageHistoryIfNeeded() {", "\n    }")
        self.assertIn("root.currentRunRequestId", trim)
        self.assertIn("root.currentRunResponseId", trim)
        self.assertIn("keepIds.has(id)", trim)

    def test_the_trim_is_actually_wired_into_the_growth_path(self):
        handler = body_between(AI_QML, "onMessageIDsChanged: {", "\n    }\n    on_KnownMessageCountChanged")
        self.assertIn("root.maxLiveMessages", handler)
        self.assertIn("root.trimMessageHistoryIfNeeded", handler)

    def test_the_wiring_defers_rather_than_mutating_mid_signal(self):
        # Reassigning root.messageIDs from inside its own change handler,
        # synchronously, is exactly the kind of thing that turns into a
        # binding loop the moment the trim itself changes the length again.
        handler = body_between(AI_QML, "onMessageIDsChanged: {", "\n    }\n    on_KnownMessageCountChanged")
        self.assertIn("Qt.callLater(root.trimMessageHistoryIfNeeded)", handler)


class RequestTimeoutFloorTests(unittest.TestCase):
    """Q3: requestTimeout=0 must not disable every bound at once."""

    def test_a_hard_ceiling_exists_for_the_zero_case(self):
        self.assertIn("readonly property int hardMaxRequestSeconds:", REQUEST_QML)
        match = re.search(r"readonly property int hardMaxRequestSeconds:\s*(\d+)", REQUEST_QML)
        self.assertIsNotNone(match)
        self.assertGreaterEqual(int(match.group(1)), 1800)  # matches the UI's own upper clamp

    def test_the_effective_timeout_falls_back_when_zero(self):
        self.assertIn(
            "readonly property int effectiveRequestTimeout: root.requestTimeout > 0 ? "
            "root.requestTimeout : root.hardMaxRequestSeconds",
            REQUEST_QML,
        )

    def test_the_watchdog_is_armed_unconditionally(self):
        launch = body_between(REQUEST_QML, "function launch() {", "\n    function buildScript")
        self.assertIn("watchdog.interval = (root.effectiveRequestTimeout + 15) * 1000;", launch)
        self.assertIn("watchdog.restart();", launch)
        # The old code gated both the interval assignment and the restart
        # behind `if (root.requestTimeout > 0)`; a lone zero-guard here means
        # the fallback above is dead code.
        self.assertNotIn("if (root.requestTimeout > 0) {", launch)

    def test_curl_always_gets_a_max_time(self):
        build = body_between(REQUEST_QML, "function buildScript(): string {", "\n        return content;")
        self.assertIn("--max-time ${root.effectiveRequestTimeout}", build)
        # It must not still be conditional on requestTimeout > 0, which is
        # exactly the branch that dropped --max-time for the zero case.
        self.assertNotIn('root.requestTimeout > 0 ? ` --max-time', build)

    def test_the_read_watchdog_restart_is_unconditional(self):
        read_line = body_between(REQUEST_QML, "function readLine(data: string) {", "\n    function retryable")
        self.assertIn("watchdog.restart();", read_line)
        self.assertNotIn("if (root.requestTimeout > 0)\n            watchdog.restart();", read_line)


class ZeroTimeoutToolTests(unittest.TestCase):
    """Q4: a tool whose handler can reach real 'pending' async work must not
    share the deadline the broker exempts for 'approval' waits."""

    ASYNC_PENDING_TOOLS = ["set_shell_config", "settings_apply_changes", "reminder_create", "remember_fact"]
    STILL_SYNCHRONOUS_TOOLS = ["switch_to_search_mode", "settings_open"]

    def test_the_previously_flagged_tools_no_longer_use_the_approval_only_deadline(self):
        for tool_id in self.ASYNC_PENDING_TOOLS:
            with self.subTest(tool=tool_id):
                block = tool_block(REGISTRY_QML, tool_id)
                timeout = field(block, "timeoutMs")
                self.assertIsNotNone(timeout, f"{tool_id} has no timeoutMs field")
                self.assertGreater(int(timeout), 0, f"{tool_id} still uses the approval-only deadline of 0")

    def test_genuinely_synchronous_ui_actions_are_unaffected(self):
        # These two never reach the broker's "pending" state at all - they
        # answer inline - so 0 remains correct and must not have been
        # touched by the same sweep.
        for tool_id in self.STILL_SYNCHRONOUS_TOOLS:
            with self.subTest(tool=tool_id):
                block = tool_block(REGISTRY_QML, tool_id)
                self.assertEqual(field(block, "timeoutMs"), "0")

    def test_the_broker_still_exempts_approval_waits_specifically(self):
        # The fix must work by giving the tool a real ceiling for its
        # *pending* path, not by weakening the broker's approval exemption -
        # that exemption is what makes a human decision take as long as it
        # takes.
        broker = (ROOT / "services" / "ai" / "AiToolBroker.qml").read_text(encoding="utf-8")
        self.assertIn('record.deadline = 0', broker)


class StopGenerationCleansUpProcessesTests(unittest.TestCase):
    """Q6: 'Stop' must actually stop everything it started, not just the
    model stream and the broker's bookkeeping."""

    def test_every_tool_process_is_cancelled(self):
        stop = body_between(AI_QML, "function stopGeneration(): bool {", "\n    /**\n     * Sends the next turn")
        for proc in ("commandExecutionProc", "filesToolProc", "ocrToolProc", "webToolProc"):
            with self.subTest(process=proc):
                self.assertIn(f"if ({proc}.running)", stop)
                self.assertIn(f"{proc}.running = false;", stop)

    def test_a_live_song_identification_is_also_stopped(self):
        stop = body_between(AI_QML, "function stopGeneration(): bool {", "\n    /**\n     * Sends the next turn")
        self.assertIn("root.pendingSongIdentify", stop)
        self.assertIn("root.mediaIntegration.stopIdentify();", stop)

    def test_the_broker_cancellation_still_happens_first(self):
        # Bookkeeping (broker.cancelAll) has to run before the process kills
        # below it - a process onExited handler reads run/queue state that
        # cancelAll is what resets.
        stop = body_between(AI_QML, "function stopGeneration(): bool {", "\n    /**\n     * Sends the next turn")
        self.assertLess(stop.index("root.broker.cancelAll("), stop.index("commandExecutionProc.running"))


class AttachmentProbeWatchdogTests(unittest.TestCase):
    """Q7: a hung probe/extract helper must not freeze the queue forever."""

    def test_a_probe_watchdog_exists_and_kills_the_process(self):
        watchdog = body_between(AI_QML, "id: probeWatchdog", "\n    Process {\n        id: probeProc")
        self.assertIn("probeProc.running = false;", watchdog)
        self.assertIn("if (!probeProc.running)", watchdog)  # only fires while genuinely stuck

    def test_an_extract_watchdog_exists_and_kills_the_process(self):
        watchdog = body_between(AI_QML, "id: extractWatchdog", "\n    Process {\n        id: extractProc")
        self.assertIn("extractProc.running = false;", watchdog)
        self.assertIn("if (!extractProc.running)", watchdog)

    def test_the_watchdogs_are_armed_when_their_process_starts_and_disarmed_on_exit(self):
        probe_proc = body_between(AI_QML, "Process {\n        id: probeProc", "\n    /** Whether the provider")
        self.assertIn("probeWatchdog.restart();", probe_proc)
        self.assertIn("probeWatchdog.stop();", probe_proc)
        extract_proc = body_between(AI_QML, "Process {\n        id: extractProc", "\n    Timer {\n        id: probeWatchdog")
        self.assertIn("extractWatchdog.restart();", extract_proc)
        self.assertIn("extractWatchdog.stop();", extract_proc)

    def test_the_existing_exit_recovery_is_untouched(self):
        # A crash already self-healed via onExited re-arming the next job;
        # the watchdog must reuse that path (by killing the process, which
        # triggers the same onExited), not replace it with a second one.
        probe_proc = body_between(AI_QML, "Process {\n        id: probeProc", "\n    /** Whether the provider")
        self.assertIn("Qt.callLater(root.runProbe);", probe_proc)
        extract_proc = body_between(AI_QML, "Process {\n        id: extractProc", "\n    Timer {\n        id: probeWatchdog")
        self.assertIn("Qt.callLater(root.runExtract);", extract_proc)


class RunCoordinatorPruningTests(unittest.TestCase):
    """Bonus finding: terminal runs must not accumulate forever."""

    def test_a_bound_exists(self):
        self.assertIn("readonly property int maxTerminalRuns:", RUN_COORDINATOR_QML)
        match = re.search(r"readonly property int maxTerminalRuns:\s*(\d+)", RUN_COORDINATOR_QML)
        self.assertIsNotNone(match)
        self.assertGreater(int(match.group(1)), 0)

    def test_pruning_only_ever_touches_terminal_runs(self):
        prune = body_between(RUN_COORDINATOR_QML, "function pruneTerminalRuns() {", "\n}")
        self.assertIn("root.terminalStates.includes(run.state)", prune)

    def test_pruning_keeps_the_newest_entries(self):
        prune = body_between(RUN_COORDINATOR_QML, "function pruneTerminalRuns() {", "\n}")
        self.assertIn("finishedAt", prune)
        self.assertIn(".sort(", prune)

    def test_pruning_runs_after_every_terminal_transition(self):
        transition = body_between(RUN_COORDINATOR_QML, "function transition(runId: string, state: string, reason = \"\", extra = null) {", "\n    function activity(")
        self.assertIn("root.runFinished(next);", transition)
        self.assertIn("root.pruneTerminalRuns();", transition)
        self.assertLess(transition.index("root.runFinished(next);"), transition.index("root.pruneTerminalRuns();"))

    def test_pruning_also_runs_after_a_restored_run_lands_in_the_map(self):
        restore = body_between(RUN_COORDINATOR_QML, "function restore(run: var): var {", "\n}")
        self.assertIn("root.pruneTerminalRuns();", restore)


if __name__ == "__main__":
    unittest.main()
