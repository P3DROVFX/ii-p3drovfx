#!/usr/bin/env python3
"""Contracts for the bounded Outlook ICS attachment discovery bridge."""

from __future__ import annotations

import base64
import unittest
from unittest.mock import patch

from scripts.outlook import list_ics_attachments as scanner


ICS = b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n"


class OutlookIcsAttachmentTests(unittest.TestCase):
    def attachment(self, **overrides: object) -> dict:
        attachment = {
            "id": "attachment-id",
            "name": "invite.ics",
            "contentType": "text/calendar",
            "size": len(ICS),
            "isInline": False,
            "@odata.type": "#microsoft.graph.fileAttachment",
            "contentBytes": base64.b64encode(ICS).decode("ascii"),
        }
        attachment.update(overrides)
        return attachment

    def test_candidate_contains_only_identity_and_bounded_calendar_bytes(self) -> None:
        candidate = scanner.candidate_for_attachment("message-id", self.attachment())

        self.assertIsNotNone(candidate)
        self.assertEqual(set(candidate), {"key", "icsBase64"})
        self.assertTrue(candidate["key"].startswith("message-id|attachment-id|"))
        self.assertEqual(base64.b64decode(candidate["icsBase64"]), ICS)

    def test_inline_non_calendar_and_oversized_files_are_rejected(self) -> None:
        self.assertIsNone(scanner.candidate_for_attachment("message", self.attachment(isInline=True)))
        self.assertFalse(scanner.is_ics_attachment(self.attachment(name="document.pdf", contentType="application/pdf")))
        self.assertEqual(scanner.bounded_ics_base64(base64.b64encode(b"x" * (scanner.MAX_ATTACHMENT_BYTES + 1)).decode("ascii")), "")

    def test_discovery_fetches_only_matching_attachment_content(self) -> None:
        with patch.object(scanner, "list_messages", return_value=[{"id": "message-id", "hasAttachments": True}]), \
             patch.object(scanner, "list_attachments", return_value=[self.attachment(contentBytes="")]), \
             patch.object(scanner, "get_attachment", return_value=self.attachment()) as get_attachment:
            candidates = scanner.discover("access-token", 25)

        self.assertEqual(len(candidates), 1)
        get_attachment.assert_called_once_with("access-token", "message-id", "attachment-id")


if __name__ == "__main__":
    unittest.main()
