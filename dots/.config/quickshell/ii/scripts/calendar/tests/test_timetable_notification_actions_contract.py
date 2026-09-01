#!/usr/bin/env python3
"""Static contracts for calendar notifications handled by the shell."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class TimetableNotificationActionsContractTests(unittest.TestCase):
    def test_calendar_reminders_use_internal_notifications_and_preserve_dnd(self) -> None:
        notifier = (ROOT / "services" / "CalendarNotifier.qml").read_text(encoding="utf-8")
        notifications = (ROOT / "services" / "Notifications.qml").read_text(encoding="utf-8")

        self.assertIn("Notifications.publishInternalNotification", notifier)
        self.assertNotIn("notify-send", notifier)
        self.assertIn("if (root.effectiveSilent)", notifications)
        self.assertIn("function publishInternalNotification", notifications)

    def test_reminder_actions_cover_open_join_and_both_snoozes(self) -> None:
        notifier = (ROOT / "services" / "CalendarNotifier.qml").read_text(encoding="utf-8")

        for identifier in (
            "__qs_calendar_open",
            "__qs_calendar_join",
            "__qs_calendar_snooze_5m",
            "__qs_calendar_snooze_1h",
        ):
            self.assertIn(identifier, notifier)
        self.assertIn("EmailDetections.detectAll", notifier)
        self.assertIn("GlobalStates.openTimetableAt", notifier)
        self.assertIn("Qt.openUrlExternally", notifier)

    def test_snoozes_are_persisted_as_safe_dtos(self) -> None:
        notifier = (ROOT / "services" / "CalendarNotifier.qml").read_text(encoding="utf-8")
        persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")

        self.assertIn("property list<var> timetableSnoozes: []", persistent)
        self.assertIn("function _snapshotEvent", notifier)
        self.assertIn("function _eventFromSnapshot", notifier)
        self.assertIn("function _scheduleSnooze", notifier)
        self.assertIn("function _checkSnoozes", notifier)

    def test_open_action_selects_timetable_and_requested_day(self) -> None:
        cheatsheet = (ROOT / "modules" / "ii" / "cheatsheet" / "Cheatsheet.qml").read_text(encoding="utf-8")
        timetable = (ROOT / "modules" / "ii" / "cheatsheet" / "CheatsheetTimetable.qml").read_text(encoding="utf-8")
        month = (ROOT / "modules" / "ii" / "cheatsheet" / "timetable" / "MonthView.qml").read_text(encoding="utf-8")
        states = (ROOT / "GlobalStates.qml").read_text(encoding="utf-8")

        self.assertIn('"id": "timetable"', cheatsheet)
        self.assertIn("function openTimetableNavigation", cheatsheet)
        self.assertIn("Persistent.states.cheatsheet.timetableView = \"month\"", timetable)
        self.assertIn("function focusRequestedDate", month)
        self.assertIn("root.requestDay(date)", month)
        self.assertIn("function openTimetableAt", states)


if __name__ == "__main__":
    unittest.main()
