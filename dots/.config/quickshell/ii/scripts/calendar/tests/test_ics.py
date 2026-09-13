#!/usr/bin/env python3
"""End-to-end tests for the timetable ICS bridge in an isolated khal home."""

from __future__ import annotations

import json
import base64
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from configobj import ConfigObj
from icalendar import Calendar


ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "scripts" / "calendar" / "ics.py"


class IcsHelperTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="ii-calendar-test-")
        self.root = Path(self.temp.name)
        self.calendar_dir = self.root / "calendar"
        self.calendar_dir.mkdir()
        self.config = self.root / "khal.conf"
        self.config.write_text(
            "\n".join([
                "[calendars]",
                "",
                "[[work]]",
                f"path = {self.calendar_dir}",
                "type = calendar",
                "color = light blue",
                "",
                "[[readonly]]",
                f"path = {self.root / 'readonly'}",
                "type = calendar",
                "readonly = True",
                "",
                "[[calendar@virtual]]",
                f"path = {self.root / 'virtual'}",
                "type = calendar",
                "",
                "[locale]",
                "timeformat = %H:%M",
                "dateformat = %d/%m/%Y",
                "longdateformat = %d/%m/%Y",
                "datetimeformat = %d/%m/%Y %H:%M",
                "longdatetimeformat = %d/%m/%Y %H:%M",
                "",
                "[sqlite]",
                f"path = {self.root / 'khal.db'}",
                "",
                "[default]",
                "default_calendar = work",
                "",
            ]),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def request(self, payload: dict) -> dict:
        completed = subprocess.run(
            [sys.executable, str(HELPER), "--config", str(self.config)],
            input=json.dumps(payload) + "\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        self.assertEqual(completed.stderr, "")
        return json.loads(completed.stdout)

    def event(self, **changes: object) -> dict:
        result = {
            "summary": "Architecture review",
            "start": "2026-09-15T10:00:00",
            "end": "2026-09-15T11:00:00",
            "description": "Bring the recurrence plan.",
            "url": "https://meet.example.test/review",
            "categories": ["work", "work"],
            "color": "tertiary",
            "recurrence": {"freq": "WEEKLY", "interval": 1, "byDay": ["TU"], "count": 10},
            "alarms": [{"minutesBefore": 30, "action": "DISPLAY"}],
        }
        result.update(changes)
        return result

    def load_event(self, uid: str):
        matches = []
        for path in self.calendar_dir.rglob("*.ics"):
            calendar = Calendar.from_ical(path.read_bytes())
            for component in calendar.walk("VEVENT"):
                if str(component.get("UID")) == uid:
                    matches.append(component)
        self.assertEqual(len(matches), 1)
        return matches[0]

    def listed_uids(self) -> list[str]:
        completed = subprocess.run(
            ["khal", "--config", str(self.config), "list", "--json", "uid", "01/09/2026", "30/09/2026"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        values = []
        for line in completed.stdout.splitlines():
            line = line.strip()
            if line and line != "[]":
                values.extend(item["uid"] for item in json.loads(line))
        return values

    def listed_days(self, uid: str) -> list[str]:
        completed = subprocess.run(
            ["khal", "--config", str(self.config), "list", "--json", "uid", "--json", "start-date", "01/09/2026", "30/09/2026"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        days = []
        for line in completed.stdout.splitlines():
            line = line.strip()
            if line and line != "[]":
                days.extend(item["start-date"] for item in json.loads(line) if item["uid"] == uid)
        return days

    def plant_synced_event(self, href: str, uid: str, start: str, end: str) -> Path:
        """Write the file the way vdirsyncer does: random href, server-side UID."""
        path = self.calendar_dir / href
        path.write_text(
            "\r\n".join([
                "BEGIN:VCALENDAR",
                "VERSION:2.0",
                "PRODID:-//Google Inc//Google Calendar 70.9054//EN",
                "BEGIN:VEVENT",
                f"UID:{uid}",
                "DTSTAMP:20260823T030000Z",
                "SUMMARY:Synced meeting",
                f"DTSTART:{start}",
                f"DTEND:{end}",
                "END:VEVENT",
                "END:VCALENDAR",
                "",
            ]),
            encoding="utf-8",
        )
        return path

    def test_editing_a_synced_event_keeps_one_file_and_reindexes(self) -> None:
        # A vdirsyncer href is a random UUID, so it never matches the UID that
        # the server assigned.  ``khal import`` names files after the UID, which
        # used to leave this file behind: the event was then listed on both the
        # old and the new day.
        uid = "0259f5utk0k2k0lrlp7g0hb7sp@google.com"
        href = "0a7df412-2b8d-42ed-b85f-104482f0713d.ics"
        self.plant_synced_event(href, uid, "20260907T140000", "20260907T150000")
        self.assertEqual(self.listed_days(uid), ["07/09/2026"])

        moved = self.request({"op": "save", "event": {"uid": uid, "start": "2026-09-11T14:00:00", "end": "2026-09-11T15:00:00"}})
        self.assertTrue(moved["ok"])
        self.assertEqual(moved["uid"], uid)

        self.assertEqual([path.name for path in self.calendar_dir.rglob("*.ics")], [href])
        self.assertEqual(self.listed_days(uid), ["11/09/2026"])
        self.assertEqual(str(self.load_event(uid).get("SUMMARY")), "Synced meeting")

    def test_save_update_move_preserves_recurrence_url_categories_and_alarm(self) -> None:
        created = self.request({"op": "save", "calendar": "work", "event": self.event()})
        self.assertTrue(created["ok"])
        uid = created["uid"]

        updated = self.request({
            "op": "save",
            "calendar": "work",
            "event": {
                "uid": uid,
                "summary": "Architecture review (moved)",
                "start": "2026-09-16T14:00:00",
                "end": "2026-09-16T15:00:00",
            },
        })
        self.assertEqual(updated, {"ok": True, "uid": uid})

        event = self.load_event(uid)
        self.assertEqual(str(event.get("SUMMARY")), "Architecture review (moved)")
        self.assertEqual(str(event.get("URL")), "https://meet.example.test/review")
        self.assertEqual(str(event.get("RRULE").to_ical(), "utf-8"), "FREQ=WEEKLY;COUNT=10;BYDAY=TU")
        self.assertEqual(sorted(str(value) for value in event.get("CATEGORIES").cats), ["ii/color=tertiary", "work"])
        alarms = [child for child in event.subcomponents if child.name == "VALARM"]
        self.assertEqual(len(alarms), 1)
        self.assertEqual(str(alarms[0].decoded("TRIGGER")), "-1 day, 23:30:00")

        read = self.request({"op": "read", "uid": uid})
        self.assertTrue(read["ok"])
        self.assertEqual(read["event"]["color"], "tertiary")
        self.assertEqual(read["event"]["categories"], ["work"])
        self.assertEqual(read["event"]["alarms"], [{"minutesBefore": 30, "action": "DISPLAY"}])

    def test_same_summary_deletes_only_requested_uid(self) -> None:
        first = self.request({"op": "save", "calendar": "work", "event": self.event(recurrence=None, alarms=[])})
        second = self.request({"op": "save", "calendar": "work", "event": self.event(recurrence=None, alarms=[], start="2026-09-16T10:00:00", end="2026-09-16T11:00:00")})
        self.assertNotEqual(first["uid"], second["uid"])

        deleted = self.request({"op": "deleteSeries", "uid": first["uid"]})
        self.assertEqual(deleted, {"ok": True})
        self.assertEqual(self.request({"op": "read", "uid": first["uid"]})["ok"], False)
        self.assertTrue(self.request({"op": "read", "uid": second["uid"]})["ok"])
        self.assertNotIn(first["uid"], self.listed_uids())
        self.assertIn(second["uid"], self.listed_uids())

    def test_calendar_color_uses_curated_khal_values(self) -> None:
        calendars = self.request({"op": "calendars"})
        self.assertEqual(calendars["defaultCalendar"], "work")
        work = next(calendar for calendar in calendars["calendars"] if calendar["name"] == "work")
        virtual = next(calendar for calendar in calendars["calendars"] if calendar["name"] == "calendar@virtual")
        self.assertEqual(work["color"], "light blue")
        self.assertTrue(virtual["readOnly"])

        changed = self.request({"op": "setCalendarColor", "calendar": "work", "color": "light green"})
        self.assertEqual(changed, {"ok": True, "calendar": "work", "color": "light green"})
        self.assertEqual(ConfigObj(str(self.config), encoding="utf-8")["calendars"]["work"]["color"], "light green")
        self.assertFalse(self.request({"op": "setCalendarColor", "calendar": "work", "color": "#123456"})["ok"])
        self.assertFalse(self.request({"op": "setCalendarColor", "calendar": "readonly", "color": "light red"})["ok"])

    def test_import_ics_preserves_uids_and_skips_replays(self) -> None:
        source = self.root / "class-schedule.ics"
        source.write_text(
            "\r\n".join([
                "BEGIN:VCALENDAR",
                "VERSION:2.0",
                "BEGIN:VEVENT",
                "UID:lecture-1@example.test",
                "SUMMARY:Distributed systems",
                "DTSTART:20260916T140000",
                "DTEND:20260916T150000",
                "END:VEVENT",
                "BEGIN:VEVENT",
                "SUMMARY:Missing UID receives a stable generated UID",
                "DTSTART:20260917T140000",
                "DTEND:20260917T150000",
                "END:VEVENT",
                "END:VCALENDAR",
                "",
            ]),
            encoding="utf-8",
        )

        first = self.request({"op": "importIcs", "path": str(source)})
        self.assertEqual(first["ok"], True)
        self.assertEqual(first["imported"], 2)
        self.assertEqual(first["skipped"], 0)
        self.assertIn("lecture-1@example.test", self.listed_uids())
        self.assertEqual(len(self.listed_uids()), 2)

        second = self.request({"op": "importIcs", "path": str(source)})
        self.assertEqual(second, {"ok": True, "imported": 0, "skipped": 2})
        self.assertEqual(len(self.listed_uids()), 2)

    def test_import_ics_rejects_read_only_calendars_and_large_inputs(self) -> None:
        source = self.root / "readonly.ics"
        source.write_text(
            "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:readonly@example.test\r\n"
            "SUMMARY:Read only\r\nDTSTART:20260916T140000\r\nDTEND:20260916T150000\r\n"
            "END:VEVENT\r\nEND:VCALENDAR\r\n",
            encoding="utf-8",
        )
        blocked = self.request({"op": "importIcs", "calendar": "readonly", "path": str(source)})
        self.assertEqual(blocked["ok"], False)
        self.assertIn("read-only", blocked["error"])

        oversized = self.root / "too-large.ics"
        oversized.write_bytes(b"X" * (1024 * 1024 + 1))
        rejected = self.request({"op": "importIcs", "path": str(oversized)})
        self.assertEqual(rejected["ok"], False)
        self.assertIn("too large", rejected["error"])

    def test_import_ics_accepts_gmail_base64_without_replaying_events(self) -> None:
        raw = (
            b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\n"
            b"UID:gmail-invite@example.test\r\nSUMMARY:Gmail invite\r\n"
            b"DTSTART:20260918T140000\r\nDTEND:20260918T150000\r\n"
            b"END:VEVENT\r\nEND:VCALENDAR\r\n"
        )
        payload = base64.urlsafe_b64encode(raw).decode("ascii")
        first = self.request({"op": "importIcs", "contentsBase64": payload})
        self.assertEqual(first, {"ok": True, "imported": 1, "skipped": 0})
        second = self.request({"op": "importIcs", "contentsBase64": payload})
        self.assertEqual(second, {"ok": True, "imported": 0, "skipped": 1})

    def test_occurrence_operations_and_read_only_guard(self) -> None:
        created = self.request({"op": "save", "calendar": "work", "event": self.event()})
        uid = created["uid"]
        expanded = self.request({"op": "expand", "uid": uid, "from": "2026-09-15T00:00:00", "to": "2026-12-01T00:00:00"})
        self.assertEqual(len(expanded["occurrences"]), 10)

        occurrence = expanded["occurrences"][1]["recurrenceId"]
        self.assertEqual(self.request({"op": "deleteOccurrence", "uid": uid, "recurrenceId": occurrence}), {"ok": True})
        after_delete = self.request({"op": "expand", "uid": uid, "from": "2026-09-15T00:00:00", "to": "2026-12-01T00:00:00"})
        self.assertEqual(len(after_delete["occurrences"]), 9)

        read_after_delete = self.request({"op": "read", "uid": uid})
        self.assertEqual(read_after_delete["event"]["exdates"], [occurrence])
        self.assertEqual(self.request({"op": "save", "calendar": "work", "event": {"uid": uid, "exdates": []}}), {"ok": True, "uid": uid})
        restored = self.request({"op": "expand", "uid": uid, "from": "2026-09-15T00:00:00", "to": "2026-12-01T00:00:00"})
        self.assertEqual(len(restored["occurrences"]), 10)
        self.assertIn(occurrence, [item["recurrenceId"] for item in restored["occurrences"]])

        self.assertEqual(self.request({"op": "deleteOccurrence", "uid": uid, "recurrenceId": occurrence}), {"ok": True})
        after_delete = self.request({"op": "expand", "uid": uid, "from": "2026-09-15T00:00:00", "to": "2026-12-01T00:00:00"})

        override_id = after_delete["occurrences"][1]["recurrenceId"]
        self.assertEqual(self.request({"op": "overrideOccurrence", "uid": uid, "recurrenceId": override_id, "fields": {"summary": "One-off review"}}), {"ok": True})
        split_id = after_delete["occurrences"][2]["recurrenceId"]
        split = self.request({"op": "splitSeries", "uid": uid, "recurrenceId": split_id, "fields": {"summary": "Future reviews"}})
        self.assertTrue(split["ok"])
        self.assertNotEqual(split["uid"], uid)
        prior = self.request({"op": "expand", "uid": uid, "from": "2026-09-15T00:00:00", "to": "2027-02-01T00:00:00"})
        self.assertTrue(all(item["recurrenceId"] < split_id for item in prior["occurrences"]))
        follow_up = self.request({"op": "read", "uid": split["uid"]})
        self.assertEqual(follow_up["event"]["summary"], "Future reviews")
        future = self.request({"op": "expand", "uid": split["uid"], "from": "2026-09-15T00:00:00", "to": "2027-02-01T00:00:00"})
        self.assertEqual(future["occurrences"][0]["recurrenceId"], split_id)
        truncate_id = future["occurrences"][2]["recurrenceId"]
        self.assertEqual(self.request({"op": "truncateSeries", "uid": split["uid"], "recurrenceId": truncate_id}), {"ok": True})
        truncated = self.request({"op": "expand", "uid": split["uid"], "from": "2026-09-15T00:00:00", "to": "2027-02-01T00:00:00"})
        self.assertTrue(all(item["recurrenceId"] < truncate_id for item in truncated["occurrences"]))
        self.assertEqual(self.request({"op": "save", "calendar": "readonly", "event": self.event(summary="Blocked")})["ok"], False)


if __name__ == "__main__":
    unittest.main()
