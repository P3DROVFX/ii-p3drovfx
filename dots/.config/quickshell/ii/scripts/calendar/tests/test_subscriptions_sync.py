#!/usr/bin/env python3
"""Tests for the vdirsyncer bridge behind read-only calendar subscriptions."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path
from unittest import mock

from scripts.calendar import subscriptions_sync


ROOT = Path(__file__).resolve().parents[3]


class SubscriptionSyncTests(unittest.TestCase):
    def test_missing_vdirsyncer_is_a_readable_reply_not_a_crash(self) -> None:
        with mock.patch.object(subscriptions_sync.shutil, "which", return_value=None):
            reply = subscriptions_sync.sync_request({"pairs": ["ii_timetable_ics_abc"]})

        self.assertFalse(reply["ok"])
        self.assertIn("not installed", reply["error"])

    def test_each_pair_is_discovered_before_it_is_synchronized(self) -> None:
        calls: list[list[str]] = []

        def fake_run(command, **kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        with mock.patch.object(subscriptions_sync.shutil, "which", return_value="/usr/bin/vdirsyncer"), \
                mock.patch.object(subscriptions_sync.subprocess, "run", side_effect=fake_run):
            reply = subscriptions_sync.sync_request({"pairs": ["ii_timetable_ics_abc"]})

        self.assertTrue(reply["ok"])
        self.assertEqual(calls, [
            ["vdirsyncer", "discover", "ii_timetable_ics_abc"],
            ["vdirsyncer", "sync", "ii_timetable_ics_abc"],
        ])

    def test_only_the_named_pairs_are_touched(self) -> None:
        calls: list[list[str]] = []

        def fake_run(command, **kwargs):
            calls.append(command)
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        with mock.patch.object(subscriptions_sync.shutil, "which", return_value="/usr/bin/vdirsyncer"), \
                mock.patch.object(subscriptions_sync.subprocess, "run", side_effect=fake_run):
            subscriptions_sync.sync_request({"pairs": ["ii_a", "ii_a", "ii_b"]})

        self.assertEqual([command[-1] for command in calls], ["ii_a", "ii_a", "ii_b", "ii_b"])

    def test_a_hostile_pair_name_never_reaches_a_command(self) -> None:
        with mock.patch.object(subscriptions_sync.subprocess, "run") as run:
            with self.assertRaises(ValueError):
                subscriptions_sync.sync_request({"pairs": ["evil; rm -rf /"]})
        run.assert_not_called()

    def test_a_failing_pair_reports_its_own_error(self) -> None:
        def fake_run(command, **kwargs):
            failed = command[1] == "sync"
            return subprocess.CompletedProcess(command, 1 if failed else 0, stdout="", stderr="network down")

        with mock.patch.object(subscriptions_sync.shutil, "which", return_value="/usr/bin/vdirsyncer"), \
                mock.patch.object(subscriptions_sync.subprocess, "run", side_effect=fake_run):
            reply = subscriptions_sync.sync_request({"pairs": ["ii_timetable_ics_abc"]})

        self.assertFalse(reply["ok"])
        self.assertEqual(reply["pairs"], [])
        self.assertIn("network down", reply["error"])

    def test_service_runs_the_bridge_and_always_clears_the_syncing_state(self) -> None:
        service = (ROOT / "services" / "CalendarSubscriptions.qml").read_text(encoding="utf-8")

        self.assertIn('"/calendar/subscriptions_sync.py"', service)
        self.assertNotIn('command: ["vdirsyncer", "sync"]', service)
        self.assertIn("root.managedPairs()", service)


if __name__ == "__main__":
    unittest.main()
