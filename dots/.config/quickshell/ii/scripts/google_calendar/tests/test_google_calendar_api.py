#!/usr/bin/env python3
"""Offline contract tests for the Google Calendar stdin client."""

import json
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch


CALENDAR_DIR = Path(__file__).resolve().parents[1]
if str(CALENDAR_DIR) not in sys.path:
    sys.path.insert(0, str(CALENDAR_DIR))

import api  # noqa: E402


def response(body, status=200):
    mock = MagicMock()
    mock.status = status
    mock.read.return_value = json.dumps(body).encode("utf-8")
    mock.__enter__.return_value = mock
    mock.__exit__.return_value = None
    return mock


class GoogleCalendarApiTests(unittest.TestCase):
    @patch("urllib.request.urlopen")
    def test_calendar_list_collects_each_page(self, mock_urlopen):
        mock_urlopen.side_effect = [
            response({"items": [{"id": "work"}], "nextPageToken": "next"}),
            response({"items": [{"id": "home"}]}),
        ]

        result = api.calendar_list("token")

        self.assertTrue(result["ok"])
        self.assertEqual([item["id"] for item in result["data"]["items"]], ["work", "home"])
        self.assertIn("maxResults=250", mock_urlopen.call_args_list[0].args[0].full_url)
        self.assertIn("pageToken=next", mock_urlopen.call_args_list[1].args[0].full_url)

    @patch("urllib.request.urlopen")
    def test_events_escape_calendar_and_keep_time_window(self, mock_urlopen):
        mock_urlopen.return_value = response({"items": []})

        result = api.events("token", "team/calendar", "2026-08-23T00:00:00Z", "2026-08-24T00:00:00Z")

        self.assertTrue(result["ok"])
        request = mock_urlopen.call_args.args[0]
        self.assertIn("team%2Fcalendar/events", request.full_url)
        self.assertIn("timeMin=2026-08-23T00%3A00%3A00Z", request.full_url)
        self.assertEqual(request.headers.get("Authorization"), "Bearer token")

    @patch("urllib.request.urlopen")
    def test_event_colors_keys_on_the_recurring_master(self, mock_urlopen):
        # singleEvents=false is what makes iCalUID the master's UID, which is the
        # only id a khal calendar file carries.
        mock_urlopen.side_effect = [
            response({"items": [{"id": "a", "iCalUID": "a@google.com", "colorId": "5"}], "nextPageToken": "next"}),
            response({"items": [{"id": "b", "iCalUID": "b@google.com"}]}),
        ]

        result = api.event_colors("token", "family@group.calendar.google.com")

        self.assertTrue(result["ok"])
        self.assertEqual([item["iCalUID"] for item in result["data"]["items"]], ["a@google.com", "b@google.com"])
        first = mock_urlopen.call_args_list[0].args[0].full_url
        self.assertIn("singleEvents=false", first)
        self.assertIn("family%40group.calendar.google.com/events", first)
        # The projection is what keeps a whole-account scan affordable.
        self.assertIn("fields=items%28id%2CiCalUID%2CcolorId%2CrecurringEventId%29%2CnextPageToken", first)
        self.assertIn("pageToken=next", mock_urlopen.call_args_list[1].args[0].full_url)

    @patch("urllib.request.urlopen")
    def test_colors_reads_the_account_palette(self, mock_urlopen):
        mock_urlopen.return_value = response({"event": {"5": {"background": "#ffb878", "foreground": "#1d1d1d"}}})

        result = api.colors("token")

        self.assertTrue(result["ok"])
        self.assertEqual(result["data"]["event"]["5"]["background"], "#ffb878")
        self.assertTrue(mock_urlopen.call_args.args[0].full_url.endswith("/colors"))

    @patch("urllib.request.urlopen")
    def test_create_event_keeps_unicode_body_and_primary_default(self, mock_urlopen):
        mock_urlopen.return_value = response({"id": "event-id"})
        body = {"summary": "Reunião Café ☕", "start": {"dateTime": "2026-08-23T14:00:00-03:00"}}

        result = api.create_event("token", "", body)

        self.assertTrue(result["ok"])
        request = mock_urlopen.call_args.args[0]
        self.assertIn("/calendars/primary/events", request.full_url)
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(json.loads(request.data.decode("utf-8")), body)

    @patch("urllib.request.urlopen")
    def test_delete_event_escapes_both_ids(self, mock_urlopen):
        mock_urlopen.return_value = response({}, status=204)

        result = api.delete_event("token", "calendar/a", "event#1?")

        self.assertTrue(result["ok"])
        request = mock_urlopen.call_args.args[0]
        self.assertIn("calendar%2Fa/events/event%231%3F", request.full_url)
        self.assertEqual(request.get_method(), "DELETE")


if __name__ == "__main__":
    unittest.main()
