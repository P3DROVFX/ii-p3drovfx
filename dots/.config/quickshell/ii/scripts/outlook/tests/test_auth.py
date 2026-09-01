#!/usr/bin/env python3
"""Unit contracts for the secret-free Microsoft device flow helper."""

from __future__ import annotations

import unittest
from unittest.mock import patch

from scripts.outlook import auth


class OutlookAuthTests(unittest.TestCase):
    def test_device_code_requests_only_public_client_fields_and_read_scopes(self) -> None:
        with patch.object(auth, "form_post", return_value={"ok": True, "data": {
            "device_code": "private-device-code", "user_code": "ABCD-EFGH",
            "verification_uri": "https://microsoft.example.test/device", "expires_in": 900, "interval": 5,
        }}) as request:
            reply = auth.device_code({"clientId": "public-client-id"})

        self.assertTrue(reply["ok"])
        self.assertEqual(reply["userCode"], "ABCD-EFGH")
        _, values = request.call_args.args
        self.assertEqual(values["client_id"], "public-client-id")
        self.assertNotIn("client_secret", values)
        self.assertIn("Calendars.Read", values["scope"])
        self.assertIn("Mail.Read", values["scope"])
        self.assertIn("offline_access", values["scope"])

    def test_pending_device_authorization_stays_machine_readable(self) -> None:
        with patch.object(auth, "form_post", return_value={
            "ok": False, "code": "authorization_pending", "message": "Waiting",
        }):
            reply = auth.token_for_device_code({"clientId": "public-client-id", "deviceCode": "device-code"})

        self.assertFalse(reply["ok"])
        self.assertEqual(reply["code"], "authorization_pending")


if __name__ == "__main__":
    unittest.main()
