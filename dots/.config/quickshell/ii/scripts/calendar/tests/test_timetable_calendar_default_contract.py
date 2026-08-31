#!/usr/bin/env python3
"""Regression contracts for the Timetable's persistent khal default."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class TimetableCalendarDefaultContractTests(unittest.TestCase):
    def test_created_event_remembers_its_writable_khal_calendar(self) -> None:
        config = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
        service = (ROOT / "services" / "CalendarService.qml").read_text(encoding="utf-8")
        helper = (ROOT / "scripts" / "calendar" / "ics.py").read_text(encoding="utf-8")

        self.assertIn("property string defaultCalendar", config)
        self.assertIn("function setDefaultCalendar(name, persist = true)", service)
        self.assertIn("root.setDefaultCalendar(persisted, false)", service)
        self.assertIn("root.setDefaultCalendar(khalDefault, false)", service)
        self.assertIn("root.setDefaultCalendar(target)", service)
        self.assertIn('"defaultCalendar": default_calendar', helper)

    def test_every_mutation_queues_a_confirmed_vdirsyncer_sync(self) -> None:
        service = (ROOT / "services" / "CalendarService.qml").read_text(encoding="utf-8")

        self.assertIn("function requestCalendarSync(calendar = \"\")", service)
        self.assertIn("property list<string> calendarSyncQueue", service)
        self.assertIn("function requestWritableCalendarSyncs()", service)
        self.assertIn('"python3", root.vdirsyncerSyncPath', service)
        self.assertIn("root.requestCalendarSync(String(current?.payload?.calendar ?? \"\"));", service)
        self.assertIn("onExited: exitCode =>", service)
        self.assertIn("[CalendarService] vdirsyncer sync failed:", service)
        self.assertIn("Qt.callLater(function() { root.requestCalendarSync(next); });", service)

    def test_created_events_are_projected_before_the_calendar_helper_returns(self) -> None:
        service = (ROOT / "services" / "CalendarService.qml").read_text(encoding="utf-8")

        self.assertIn("property list<var> optimisticEvents: []", service)
        self.assertIn("function newEventUid()", service)
        self.assertIn("function optimisticEvent(calendar, fields)", service)
        self.assertIn("function addOptimisticEvent(event)", service)
        self.assertIn("function removeOptimisticEvent(uid)", service)
        self.assertIn("const evts = root.visibleEvents;", service)
        self.assertIn("payload.uid = root.newEventUid();", service)
        self.assertIn("root.addOptimisticEvent(root.optimisticEvent(target, payload));", service)
        self.assertIn("root.removeOptimisticEvent(payload.uid);", service)


if __name__ == "__main__":
    unittest.main()
