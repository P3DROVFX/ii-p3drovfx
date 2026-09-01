#!/usr/bin/env python3
"""Pure local contracts for the Outlook calendar mirror."""

from __future__ import annotations

import tempfile
import unittest
from datetime import date, datetime, timezone
from pathlib import Path

from scripts.outlook import calendar_sync


def timed_event(identifier: str = "event-1") -> dict:
    return {
        "id": identifier,
        "subject": "Review",
        "bodyPreview": "Planning notes",
        "start": {"dateTime": "2026-08-25T13:00:00Z"},
        "end": {"dateTime": "2026-08-25T14:00:00Z"},
        "location": {"displayName": "Office"},
        "organizer": {"emailAddress": {"address": "owner@example.test"}},
        "categories": ["Work"],
        "webLink": "https://outlook.example.test/event",
    }


class OutlookCalendarSyncTests(unittest.TestCase):
    def test_timed_event_has_stable_local_uid_and_utc_times(self) -> None:
        event = timed_event()
        calendar = calendar_sync.event_calendar("user@example.test", event)
        component = calendar.subcomponents[0]

        self.assertTrue(str(component["UID"]).startswith("ii-outlook-"))
        self.assertEqual(str(component["X-II-TIMETABLE-SOURCE"]), "outlook")
        self.assertEqual(component.decoded("DTSTART"), datetime(2026, 8, 25, 13, tzinfo=timezone.utc))
        self.assertEqual(component.decoded("DTEND"), datetime(2026, 8, 25, 14, tzinfo=timezone.utc))

    def test_all_day_event_keeps_its_calendar_dates(self) -> None:
        event = timed_event("all-day")
        event.update({
            "isAllDay": True,
            "start": {"dateTime": "2026-08-25T00:00:00.0000000"},
            "end": {"dateTime": "2026-08-26T00:00:00.0000000"},
        })

        component = calendar_sync.event_calendar("user@example.test", event).subcomponents[0]

        self.assertEqual(component.decoded("DTSTART"), date(2026, 8, 25))
        self.assertEqual(component.decoded("DTEND"), date(2026, 8, 26))

    def test_reconciliation_removes_only_its_stale_files(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ii-outlook-sync-") as temp:
            destination = Path(temp)
            calendar_sync.write_collection(destination, "user@example.test", [timed_event("first"), timed_event("second")])
            (destination / "user-owned.ics").write_text("BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n", encoding="utf-8")

            result = calendar_sync.write_collection(destination, "user@example.test", [timed_event("second")])

            self.assertEqual(result, {"written": 1, "removed": 1})
            self.assertTrue((destination / "user-owned.ics").exists())
            self.assertEqual(len(list(destination.glob("ii-outlook-*.ics"))), 1)


if __name__ == "__main__":
    unittest.main()
