#!/usr/bin/env python3
"""What a tool changed is written down before it changes anything.

The journal already worked for the two tools that had one, but it knew them by
name: `kind` was "shell" or "config", and the line it wrote was chosen by an
`if` on that. Any new tool that changes something would have had to be added to
that `if`. These tests pin the generalised form, and the two states that only
matter when something goes wrong: a fingerprint that makes a repeat
recognisable, and an outcome nobody can be sure of.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
MESSAGE = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class JournalTests(unittest.TestCase):
    def test_the_journal_knows_tools_by_id_not_by_category(self):
        begin = body_between(AI_QML, "function beginToolExecution(message: AiMessageData, toolId: string",
                             "function markToolNeedsInspection")
        for gone in ('kind === "shell"', 'pending.command', 'pending.changes'):
            with self.subTest(token=gone):
                self.assertNotIn(gone, begin)
        self.assertIn("root.toolbox.describeArgs(id, args)", begin)

    def test_both_callers_name_their_tool(self):
        self.assertIn('beginToolExecution(message, "run_shell_command"', AI_QML)
        self.assertIn('beginToolExecution(message, "set_shell_config"', AI_QML)

    def test_the_side_effect_is_chosen_from_a_map(self):
        starters = body_between(AI_QML, "readonly property var sideEffectStarters: ({", "})")
        self.assertIn('"run_shell_command":', starters)
        self.assertIn('"set_shell_config":', starters)

    def test_an_approved_tool_with_no_way_to_run_is_not_silently_dropped(self):
        ack = body_between(AI_QML, "function handleToolJournalSaveSucceeded", "readonly property var sideEffectStarters")
        self.assertIn("markToolNeedsInspection", ack)

    def test_the_approval_is_acknowledged_before_the_effect_starts(self):
        ack = body_between(AI_QML, "function handleToolJournalSaveSucceeded", "readonly property var sideEffectStarters")
        # Two phases: the approval is written and confirmed, then a second
        # checkpoint marks the irreversible boundary, then it runs.
        self.assertIn('pending.phase === "approved"', ack)
        self.assertIn('status: "executionStarted"', ack)
        self.assertLess(ack.index('status: "executionStarted"'), ack.index("sideEffectStarters" if "sideEffectStarters" in ack else "starter("))

    def test_only_one_side_effect_is_ever_being_prepared(self):
        begin = body_between(AI_QML, "function beginToolExecution(message: AiMessageData, toolId: string",
                             "function markToolNeedsInspection")
        self.assertIn("if (root.pendingToolExecution)", begin)


class FingerprintTests(unittest.TestCase):
    def test_the_hash_ignores_the_order_keys_were_written_in(self):
        hasher = body_between(AI_QML, "function argsHash(args: var)", "/**\n     * Writes an approved side effect")
        self.assertIn("Object.keys(value).sort()", hasher)

    def test_the_hash_is_recorded_with_the_approval(self):
        begin = body_between(AI_QML, "function beginToolExecution(message: AiMessageData, toolId: string",
                             "function markToolNeedsInspection")
        self.assertIn("argsHash: hash", begin)


class AmbiguityTests(unittest.TestCase):
    def test_an_unknown_outcome_never_offers_a_retry(self):
        mark = body_between(AI_QML, "function markToolNeedsInspection", "/**\n     * A stable fingerprint"
                            if "A stable fingerprint" in AI_QML.split("function markToolNeedsInspection", 1)[1][:4000]
                            else "function handleToolJournalSaveSucceeded")
        self.assertIn('status: "needsInspection"', mark)
        self.assertIn("retryable: false", mark)
        self.assertIn("Do not try it again", mark)

    def test_a_killed_command_is_ambiguous_and_an_exit_code_is_not(self):
        exited = body_between(AI_QML, "id: commandExecutionProc", "function describeConfigValue")
        self.assertIn("exitStatus !== 0", exited)
        self.assertIn("markToolNeedsInspection", exited)

    def test_a_side_effect_interrupted_by_a_restart_says_so_on_reopen(self):
        recover = body_between(AI_QML, "function recoverInterruptedCheckpoints", "function recoverInterruptedMessages")
        self.assertIn('"executionStarted"', recover)
        self.assertIn('status: "needsInspection"', recover)
        self.assertIn("root.recoverInterruptedCheckpoints(", AI_QML.split("function recoverInterruptedCheckpoints", 1)[1])


class ActivityTests(unittest.TestCase):
    def test_how_a_call_went_is_recorded_on_the_call(self):
        note = body_between(AI_QML, "function noteToolCallState(message, callId: string", "/** The broker's key")
        self.assertIn("String(call.id ?? \"\") === String(callId)", note)

    def test_the_broker_reports_both_ends_of_a_call(self):
        broker = body_between(AI_QML, "readonly property AiToolBroker broker: AiToolBroker {", "\n    }")
        self.assertIn("onCallStarted:", broker)
        self.assertIn("onCallFinished:", broker)
        self.assertIn('state: "running"', broker)

    def test_the_transcript_shows_the_outcome_not_only_the_request(self):
        row = body_between(MESSAGE, "delegate: AiActivityRow {", "// ── The answer")
        self.assertIn("stepToolRow.outcome", row)
        self.assertIn('"needsInspection"', row)
        self.assertIn("networkUsed", row)

    def test_a_session_without_states_still_animates_sensibly(self):
        # Saved before the broker existed: no state on the call at all.
        row = body_between(MESSAGE, "delegate: AiActivityRow {", "// ── The answer")
        self.assertIn("stepToolRow.state.length === 0", row)


if __name__ == "__main__":
    unittest.main()
