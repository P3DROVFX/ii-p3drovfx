#!/usr/bin/env python3
"""Contracts for the opt-in Gmail ICS attachment discovery path."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
EMAIL_SCRIPTS = ROOT / "scripts" / "email"
SCANNER = EMAIL_SCRIPTS / "list_ics_attachments.py"


def load_scanner():
    sys.path.insert(0, str(EMAIL_SCRIPTS))
    spec = importlib.util.spec_from_file_location("ii_gmail_ics_scanner", SCANNER)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class GmailIcsAttachmentTests(unittest.TestCase):
    def test_finds_named_and_inline_calendar_parts_only(self) -> None:
        scanner = load_scanner()
        payload = {
            "mimeType": "multipart/mixed",
            "parts": [
                {"mimeType": "application/pdf", "filename": "agenda.pdf", "body": {"attachmentId": "pdf"}},
                {"mimeType": "text/calendar", "filename": "", "body": {"data": "QUJD"}},
                {"mimeType": "application/octet-stream", "filename": "schedule.ICAL", "body": {"attachmentId": "ical"}},
            ],
        }
        parts = list(scanner.iter_ics_parts(payload))
        self.assertEqual([part["mimeType"] for _, part in parts], ["text/calendar", "application/octet-stream"])

    def test_candidate_key_includes_message_attachment_and_content_identity(self) -> None:
        scanner = load_scanner()
        part = {"mimeType": "text/calendar", "filename": "invite.ics", "body": {"attachmentId": "att-1"}}
        first = scanner.candidate_for_part("message-1", 2, part, b"BEGIN:VCALENDAR")
        second = scanner.candidate_for_part("message-1", 2, part, b"BEGIN:VCALENDAR")
        changed = scanner.candidate_for_part("message-1", 2, part, b"BEGIN:VCALENDAR\nCHANGED")
        self.assertEqual(first["key"], second["key"])
        self.assertNotEqual(first["key"], changed["key"])
        self.assertIn("icsBase64", first)
        self.assertNotIn("contents", first)

    def test_gmail_ics_import_is_opt_in_and_persistently_deduplicated(self) -> None:
        config = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
        persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")
        service = (ROOT / "services" / "GmailCalendarImport.qml").read_text(encoding="utf-8")
        calendar = (ROOT / "services" / "CalendarService.qml").read_text(encoding="utf-8")
        sidebar = (ROOT / "modules" / "ii" / "cheatsheet" / "timetable" / "EventSidebar.qml").read_text(encoding="utf-8")
        shell = (ROOT / "shell.qml").read_text(encoding="utf-8")

        self.assertIn("property JsonObject gmailIcs: JsonObject", config)
        self.assertIn("property bool enable: false", config)
        self.assertIn("property list<string> timetableGmailIcsImports: []", persistent)
        self.assertIn("CalendarService.importIcsBase64", service)
        self.assertIn("timetableGmailIcsImports", service)
        self.assertIn("function scanNow()", service)
        self.assertIn("function importIcsBase64", calendar)
        self.assertIn('text: Translation.tr("Import ICS attachments from Gmail")', sidebar)
        self.assertIn("GmailCalendarImport.enabled", shell)


if __name__ == "__main__":
    unittest.main()
