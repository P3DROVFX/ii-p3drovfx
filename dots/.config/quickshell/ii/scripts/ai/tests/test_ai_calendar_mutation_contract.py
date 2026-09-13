#!/usr/bin/env python3
"""Pin calendar writes to reviewed, CalendarService-owned operations."""

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
REGISTRY = (ROOT / "services/ai/AiToolRegistry.qml").read_text(encoding="utf-8")
TIME = (ROOT / "services/ai/integrations/AiTimeIntegration.qml").read_text(encoding="utf-8")
AI = (ROOT / "services/Ai.qml").read_text(encoding="utf-8")
MESSAGE = (ROOT / "modules/ii/sidebarPolicies/aiChat/AiMessage.qml").read_text(encoding="utf-8")
CARD = (ROOT / "services/ai/blocks/AiTaskMutationCard.qml").read_text(encoding="utf-8")


def tool_block(tool_id: str) -> str:
    source = REGISTRY.split(f'id: "{tool_id}"', 1)[1]
    return source.split('\n        },', 1)[0]


class AiCalendarMutationContractTests(unittest.TestCase):
    def test_calendar_writes_are_declared_as_approval_only_local_writes(self):
        for tool_id in (
            "calendar_create_event",
            "calendar_move_event",
            "calendar_delete_event",
        ):
            with self.subTest(tool=tool_id):
                block = tool_block(tool_id)
                self.assertIn('kind: "localWrite"', block)
                self.assertIn('defaultApproval: "ask"', block)
                self.assertNotIn('neverAutoApprove: true', block)
                self.assertIn('uid' if tool_id != "calendar_create_event" else 'title', block)

    def test_recurrence_scope_is_explicit_and_defaults_are_shown(self):
        move = tool_block("calendar_move_event")
        delete = tool_block("calendar_delete_event")
        for block in (move, delete):
            self.assertIn("scope", block)
            self.assertIn("recurrenceId", block)
            self.assertIn("defaults to all", block)
        for token in (
            "function normalizedCalendarScope",
            "A specific occurrence needs its recurrence id",
            "Only this occurrence",
            "This and future occurrences",
            "All occurrences",
            'op: "overrideOccurrence"',
            'op: "splitSeries"',
            'op: "deleteOccurrence"',
            'op: "truncateSeries"',
            'op: "deleteSeries"',
        ):
            with self.subTest(token=token):
                self.assertIn(token, TIME)

    def test_adapter_uses_only_calendar_service_and_reports_async_results(self):
        for token in (
            "CalendarService.enqueueCalendarRequest(",
            "signal calendarMutationFinished",
            "pendingCalendarOperations",
            "function executeCalendarMutation",
            "function calendarCreatePreview",
            "function calendarMovePreview",
            "function calendarDeletePreview",
        ):
            with self.subTest(token=token):
                self.assertIn(token, TIME)
        for forbidden in ("ics.py", "Process", "execDetached"):
            with self.subTest(token=forbidden):
                self.assertNotIn(forbidden, TIME)

    def test_calendar_list_exposes_the_opaque_uid_needed_for_safe_mutations(self):
        block = re.search(r"function calendarEventRef\(event: var\): var \{(.*?)\n    \}", TIME, re.S)
        self.assertIsNotNone(block)
        self.assertIn("uid: String(event?.uid ?? \"\")", block.group(1))
        self.assertIn("recurrenceId: CalendarService.recurrenceIdForEvent(event)", block.group(1))

    def test_ai_journals_then_runs_and_renders_the_same_review_card(self):
        for token in (
            '"calendar_create_event": call => root.toolCalendarCreateEvent(call)',
            '"calendar_move_event": call => root.toolCalendarMoveEvent(call)',
            '"calendar_delete_event": call => root.toolCalendarDeleteEvent(call)',
            '"calendar_create_event": pending => root.startCalendarMutation(pending)',
            "function approveCalendarMutation",
            "function rejectCalendarMutation",
            "function finishCalendarMutation",
            "function startCalendarMutation",
            "onCalendarMutationFinished",
            '"calendarMutationPreview"',
        ):
            with self.subTest(token=token):
                self.assertIn(token, AI)
        self.assertIn('case "calendarMutationPreview":', MESSAGE)
        self.assertIn("root.calendarMutation ? Ai.approveCalendarMutation", CARD)
        self.assertIn("root.calendarMutation ? Ai.rejectCalendarMutation", CARD)


if __name__ == "__main__":
    unittest.main()
