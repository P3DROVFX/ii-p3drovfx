#!/usr/bin/env python3
"""Static contracts for Timetable-owned calendar source imports."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TIMETABLE = ROOT / "modules" / "ii" / "cheatsheet" / "timetable"


class TimetableImportContractTests(unittest.TestCase):
    def test_sources_are_opt_in_and_available_from_each_timetable_view(self) -> None:
        config = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
        subscriptions = (ROOT / "services" / "CalendarSubscriptions.qml").read_text(encoding="utf-8")
        host = (ROOT / "modules" / "ii" / "cheatsheet" / "CheatsheetTimetable.qml").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        month = (TIMETABLE / "MonthView.qml").read_text(encoding="utf-8")
        sidebar = (TIMETABLE / "EventSidebar.qml").read_text(encoding="utf-8")
        file_import = (ROOT / "services" / "CalendarIcsFileImport.qml").read_text(encoding="utf-8")

        self.assertIn("property bool enable: false", config)
        self.assertIn("property JsonObject imports: JsonObject", config)
        self.assertIn("readonly property bool importsEnabled", subscriptions)
        self.assertIn("effectiveSubscriptionUrls", subscriptions)
        self.assertNotIn("TimetableImportPanel", host)
        self.assertIn("eventSidebar.showSources()", week)
        self.assertIn("eventSidebar.showSources()", month)
        self.assertIn('root.setMode("sources")', sidebar)
        self.assertNotIn("FileDialog", sidebar)
        self.assertIn("CalendarIcsFileImport.open()", sidebar)
        self.assertIn("CalendarIcsFileImport.lastStatus", sidebar)
        self.assertIn("Singleton", file_import)
        self.assertIn("FileDialog", file_import)
        self.assertIn("parentWindow: null", file_import)
        self.assertIn("CalendarService.importFromIcs", file_import)
        self.assertIn("CalendarSubscriptions.addSubscription", sidebar)


if __name__ == "__main__":
    unittest.main()
