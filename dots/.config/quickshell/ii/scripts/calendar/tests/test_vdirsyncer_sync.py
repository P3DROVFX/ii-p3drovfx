#!/usr/bin/env python3
"""Unit tests for the khal-to-vdirsyncer collection mapper."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts" / "calendar" / "vdirsyncer_sync.py"
SPEC = importlib.util.spec_from_file_location("vdirsyncer_sync", MODULE_PATH)
assert SPEC and SPEC.loader
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class VdirsyncerSyncTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="ii-vdirsyncer-test-")
        self.root = Path(self.temp.name)
        self.local_root = self.root / "Personal"
        self.local_root.mkdir()
        self.config = self.root / "vdirsyncer.conf"
        self.config.write_text(
            "\n".join([
                "[pair personal_sync]",
                'a = "personal"',
                'b = "personallocal"',
                "",
                "[storage personal]",
                'type = "google_calendar"',
                "",
                "[storage personallocal]",
                'type = "filesystem"',
                'path = "' + str(self.local_root) + '"',
                "",
            ]),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_resolves_the_pair_for_the_calendar_directory(self) -> None:
        calendar_root = self.local_root / "pedro@example.com"
        self.assertEqual(
            SYNC.resolve_target("pedro@example.com", calendar_root, self.config),
            "personal_sync/pedro@example.com",
        )

    def test_does_not_target_an_unrelated_filesystem_storage(self) -> None:
        self.assertEqual(
            SYNC.resolve_target("elsewhere@example.com", self.root / "Elsewhere", self.config),
            "",
        )


if __name__ == "__main__":
    unittest.main()
