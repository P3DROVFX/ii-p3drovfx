#!/usr/bin/env python3
"""Unit tests for the vdirsyncer OAuth reauthorization helper."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts" / "calendar" / "vdirsyncer_reauth.py"
SPEC = importlib.util.spec_from_file_location("vdirsyncer_reauth", MODULE_PATH)
assert SPEC and SPEC.loader
REAUTH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REAUTH)


class VdirsyncerReauthTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="ii-reauth-test-")
        self.root = Path(self.temp.name)
        self.config = self.root / "vdirsyncer.conf"
        self.token_file = self.root / "google_token.json"
        self.config.write_text(
            "\n".join([
                "[general]",
                'status_path = "~/.calendars/status"',
                "",
                "[pair personal_sync]",
                'a = "personal"',
                'b = "personallocal"',
                "",
                "[storage personal]",
                'type = "google_calendar"',
                f'token_file = "{self.token_file}"',
                'client_id = "test-client-id.apps.googleusercontent.com"',
                'client_secret = "test-client-secret"',
                "",
                "[storage personallocal]",
                'type = "filesystem"',
                'path = "~/.calendars/Personal"',
                'fileext = ".ics"',
                "",
            ]),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_parses_sections_correctly(self) -> None:
        sections = REAUTH.parse_vdirsyncer_sections(self.config)
        self.assertIn("storage personal", sections)
        self.assertEqual(sections["storage personal"]["type"], "google_calendar")
        self.assertEqual(sections["storage personal"]["client_id"], "test-client-id.apps.googleusercontent.com")

    def test_extracts_google_credentials(self) -> None:
        creds = REAUTH.get_vdirsyncer_google_credentials(self.config)
        self.assertEqual(creds["client_id"], "test-client-id.apps.googleusercontent.com")
        self.assertEqual(creds["client_secret"], "test-client-secret")
        self.assertEqual(creds["token_file"], self.token_file)

    def test_writes_token_atomically_with_safe_permissions(self) -> None:
        payload = {
            "access_token": "ya29.test-access-token",
            "expires_in": 3600,
            "scope": ["https://www.googleapis.com/auth/calendar"],
            "token_type": "Bearer",
            "expires_at": 1788923000,
            "refresh_token": "1//test-refresh-token",
        }
        REAUTH.write_atomic_token(self.token_file, payload)

        self.assertTrue(self.token_file.is_file())
        loaded = json.loads(self.token_file.read_text(encoding="utf-8"))
        self.assertEqual(loaded["access_token"], "ya29.test-access-token")
        self.assertEqual(loaded["refresh_token"], "1//test-refresh-token")

        mode = stat.S_IMODE(os.stat(self.token_file).st_mode)
        self.assertEqual(mode, 0o600)

    def test_run_reauth_returns_error_when_credentials_missing(self) -> None:
        result = REAUTH.run_reauth(
            client_id="",
            client_secret="",
            token_file=self.token_file,
        )
        self.assertFalse(result["ok"])
        self.assertEqual(result["code"], "missing_credentials")


if __name__ == "__main__":
    unittest.main()
