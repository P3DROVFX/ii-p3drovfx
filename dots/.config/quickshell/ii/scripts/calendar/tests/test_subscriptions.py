#!/usr/bin/env python3
"""Tests for the non-destructive vdirsyncer/khal subscription bridge."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.calendar import subscriptions


class SubscriptionBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="ii-subscriptions-test-")
        self.root = Path(self.temp.name)
        self.khal_path = self.root / "khal.conf"
        self.vdirsyncer_path = self.root / "vdirsyncer.conf"
        self.calendar_dir = self.root / "personal"
        self.calendar_dir.mkdir()
        self.khal_path.write_text("\n".join([
            "# user-owned comment",
            "[calendars]",
            "[[personal]]",
            f"path = {self.calendar_dir}",
            "type = calendar",
            "",
            "[locale]",
            "timeformat = %H:%M",
            "dateformat = %d/%m/%Y",
            "longdateformat = %d/%m/%Y",
            "datetimeformat = %d/%m/%Y %H:%M",
            "longdatetimeformat = %d/%m/%Y %H:%M",
            "",
            "[default]",
            "default_calendar = personal",
            "",
        ]), encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def payload(self, urls: list[str]) -> dict:
        return {
            "vdirsyncerConfigPath": str(self.vdirsyncer_path),
            "khalConfigPath": str(self.khal_path),
            "statusPath": str(self.root / "status"),
            "subscriptionRoot": str(self.root / "subscriptions"),
            "subscriptions": urls,
        }

    def test_adds_readonly_configs_and_preserves_user_sections(self) -> None:
        result = subscriptions.apply_subscriptions(self.payload([
            "https://calendar.example.test/work.ics?token=private",
        ]))

        self.assertTrue(result["ok"])
        self.assertTrue(result["syncRequired"])
        self.assertEqual(len(result["subscriptions"]), 1)
        self.assertTrue(result["subscriptions"][0]["readOnly"])

        vdirsyncer = self.vdirsyncer_path.read_text(encoding="utf-8")
        khal = self.khal_path.read_text(encoding="utf-8")
        self.assertIn(subscriptions.BEGIN_MARKER, vdirsyncer)
        self.assertIn('type = "http"', vdirsyncer)
        self.assertIn('partial_sync = "revert"', vdirsyncer)
        self.assertIn("# user-owned comment", khal)
        self.assertIn("[[personal]]", khal)
        self.assertIn("[[ii_timetable_subscriptions]]", khal)
        self.assertIn("readonly = True", khal)

        parsed = subprocess.run(
            ["vdirsyncer", "-c", str(self.vdirsyncer_path), "showconfig"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertEqual(parsed.returncode, 0, parsed.stderr)

    def test_removing_last_url_removes_only_managed_blocks(self) -> None:
        subscriptions.apply_subscriptions(self.payload(["https://calendar.example.test/work.ics"]))
        result = subscriptions.apply_subscriptions(self.payload([]))

        self.assertTrue(result["ok"])
        self.assertNotIn(subscriptions.BEGIN_MARKER, self.vdirsyncer_path.read_text(encoding="utf-8"))
        khal = self.khal_path.read_text(encoding="utf-8")
        self.assertNotIn(subscriptions.BEGIN_MARKER, khal)
        self.assertIn("# user-owned comment", khal)
        self.assertIn("[[personal]]", khal)

    def test_invalid_url_does_not_write_any_config(self) -> None:
        original_khal = self.khal_path.read_text(encoding="utf-8")
        with self.assertRaises(subscriptions.SubscriptionError):
            subscriptions.apply_subscriptions(self.payload(["file:///tmp/not-a-subscription.ics"]))

        self.assertEqual(self.khal_path.read_text(encoding="utf-8"), original_khal)
        self.assertFalse(self.vdirsyncer_path.exists())

    def test_outlook_collection_is_readonly_without_creating_a_remote_pair(self) -> None:
        payload = self.payload([])
        payload.update({
            "outlookRoot": str(self.root / "outlook"),
            "outlookEnabled": True,
        })

        result = subscriptions.apply_subscriptions(payload)

        self.assertTrue(result["ok"])
        self.assertFalse(result["syncRequired"])
        self.assertTrue((self.root / "outlook").is_dir())
        khal = self.khal_path.read_text(encoding="utf-8")
        self.assertIn("[[ii_timetable_outlook]]", khal)
        self.assertIn(f"path = {self.root / 'outlook'}", khal)
        self.assertIn("readonly = True", khal)
        self.assertFalse(self.vdirsyncer_path.exists())


if __name__ == "__main__":
    unittest.main()
