#!/usr/bin/env python3
"""Tests for the non-destructive vdirsyncer/khal subscription bridge."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.calendar import subscriptions


ROOT = Path(__file__).resolve().parents[3]


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

    def mirror_of(self, url: str) -> Path:
        root = self.root / "subscriptions"
        return subscriptions.subscriptions_from_urls([url], root)[0].local_path

    def seed_mirror(self, url: str) -> Path:
        """Give a subscription the mirrored event and status files a sync leaves."""
        mirror = self.mirror_of(url)
        mirror.mkdir(parents=True, exist_ok=True)
        (mirror / "event.ics").write_text("BEGIN:VCALENDAR\nEND:VCALENDAR\n", encoding="utf-8")
        status = self.root / "status"
        status.mkdir(parents=True, exist_ok=True)
        for suffix in (".items", ".collections"):
            (status / (mirror.name + suffix)).write_text("{}", encoding="utf-8")
        return mirror

    def test_a_removed_subscription_stops_showing_its_events(self) -> None:
        wrong = "https://calendar.example.test/wrong.ics"
        right = "https://calendar.example.test/right.ics"
        subscriptions.apply_subscriptions(self.payload([wrong, right]))
        wrong_mirror = self.seed_mirror(wrong)
        right_mirror = self.seed_mirror(right)

        result = subscriptions.apply_subscriptions(self.payload([right]))

        self.assertTrue(result["ok"])
        self.assertTrue(result["changed"])
        self.assertFalse(wrong_mirror.exists())
        self.assertTrue((right_mirror / "event.ics").is_file())
        status = self.root / "status"
        self.assertFalse((status / (wrong_mirror.name + ".items")).exists())
        self.assertTrue((status / (right_mirror.name + ".items")).is_file())

    def test_removing_every_subscription_also_removes_its_events(self) -> None:
        url = "https://calendar.example.test/work.ics"
        subscriptions.apply_subscriptions(self.payload([url]))
        mirror = self.seed_mirror(url)

        subscriptions.apply_subscriptions(self.payload([]))

        self.assertFalse(mirror.exists())

    def test_a_directory_ii_does_not_own_is_never_deleted(self) -> None:
        subscriptions.apply_subscriptions(self.payload(["https://calendar.example.test/work.ics"]))
        foreign = self.root / "subscriptions" / "my-own-calendar"
        foreign.mkdir(parents=True, exist_ok=True)
        (foreign / "event.ics").write_text("BEGIN:VCALENDAR\nEND:VCALENDAR\n", encoding="utf-8")

        subscriptions.apply_subscriptions(self.payload([]))

        self.assertTrue((foreign / "event.ics").is_file())

    def test_disabling_imports_keeps_the_mirrors_it_already_downloaded(self) -> None:
        url = "https://calendar.example.test/work.ics"
        subscriptions.apply_subscriptions(self.payload([url]))
        mirror = self.seed_mirror(url)

        payload = self.payload([])
        payload["knownSubscriptions"] = [url]
        result = subscriptions.apply_subscriptions(payload)

        self.assertTrue(result["ok"])
        self.assertTrue((mirror / "event.ics").is_file())

    def test_the_service_reports_every_configured_url_not_only_the_enabled_ones(self) -> None:
        service = (ROOT / "services" / "CalendarSubscriptions.qml").read_text(encoding="utf-8")
        self.assertIn('"knownSubscriptions": root.subscriptionUrls()', service)
        self.assertIn('"subscriptions": root.effectiveSubscriptionUrls()', service)

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
