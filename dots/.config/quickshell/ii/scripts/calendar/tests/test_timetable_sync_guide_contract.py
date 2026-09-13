#!/usr/bin/env python3
"""Static contracts for the in-context Google Calendar setup guide."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TIMETABLE = ROOT / "modules" / "ii" / "cheatsheet" / "timetable"


class TimetableSyncGuideContractTests(unittest.TestCase):
    def test_google_calendar_setup_is_explained_in_both_timetable_entry_points(self) -> None:
        guide = (ROOT / "modules" / "common" / "widgets" / "GoogleCalendarSetupGuide.qml").read_text(encoding="utf-8")
        settings = (ROOT / "modules" / "settings" / "configs" / "widgets" / "TimetableConfig.qml").read_text(encoding="utf-8")
        sidebar = (TIMETABLE / "EventSidebar.qml").read_text(encoding="utf-8")

        self.assertIn("Google Calendar ↔ vdirsyncer ↔ khal ↔ Timetable", guide)
        self.assertIn("GOOGLE_CLIENT_ID", guide)
        self.assertIn("GOOGLE_CLIENT_SECRET", guide)
        self.assertIn("Google Calendar API", guide)
        self.assertIn("vdirsyncer discover", guide)
        self.assertIn("khal configure", guide)
        self.assertIn("CalendarService.requestWritableCalendarSyncs()", guide)
        self.assertIn("GoogleCalendarService.startOAuth()", guide)
        self.assertIn("GoogleCalendarSetupGuide", settings)
        self.assertIn("GoogleCalendarSetupGuide", sidebar)


if __name__ == "__main__":
    unittest.main()
