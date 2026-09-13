#!/usr/bin/env python3
"""Static integration contracts for the read-only Outlook Timetable source."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]


class OutlookTimetableContractTests(unittest.TestCase):
    def test_outlook_source_is_opt_in_readonly_and_lives_in_the_sources_rail(self) -> None:
        config = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
        subscriptions = (ROOT / "services/CalendarSubscriptions.qml").read_text(encoding="utf-8")
        service = (ROOT / "services/OutlookCalendarImport.qml").read_text(encoding="utf-8")
        attachment_service = (ROOT / "services/OutlookIcsImport.qml").read_text(encoding="utf-8")
        persistent = (ROOT / "modules/common/Persistent.qml").read_text(encoding="utf-8")
        sidebar = (ROOT / "modules/ii/cheatsheet/timetable/EventSidebar.qml").read_text(encoding="utf-8")
        settings = (ROOT / "modules/settings/configs/widgets/TimetableConfig.qml").read_text(encoding="utf-8")
        shell = (ROOT / "shell.qml").read_text(encoding="utf-8")

        self.assertIn("property JsonObject outlook: JsonObject", config)
        self.assertIn("property bool enable: false", config)
        self.assertIn("readonly property bool outlookEnabled", subscriptions)
        self.assertIn('"outlookEnabled": root.outlookEnabled', subscriptions)
        self.assertIn("readonly property bool enabled", service)
        self.assertIn("CalendarSubscriptions.requestApply()", service)
        self.assertIn("CalendarService.loadCalendarList()", service)
        self.assertIn('text: Translation.tr("Sync Outlook calendar")', sidebar)
        self.assertIn("OutlookCalendarImport.syncNow()", sidebar)
        self.assertIn('title: Translation.tr("Outlook calendar")', settings)
        self.assertIn("Config.options.calendar.timetable.imports.outlook.enable", settings)
        self.assertIn("Microsoft application (client) ID", settings)
        self.assertIn("OutlookService.beginAuthorization(root.outlookClientIdDraft)", settings)
        self.assertIn("OutlookService.disconnect()", settings)
        self.assertIn("OutlookService.userCode", settings)
        self.assertIn("Qt.openUrlExternally(OutlookService.verificationUri)", settings)
        self.assertIn("Microsoft Entra admin center", settings)
        self.assertIn("Enable public client flows", settings)
        self.assertIn("property JsonObject icsAttachments: JsonObject", config)
        self.assertIn("property bool enable: false", config)
        self.assertIn("timetableOutlookIcsImports", persistent)
        self.assertIn("CalendarService.importIcsBase64", attachment_service)
        self.assertIn("Import ICS attachments from Outlook", sidebar)
        self.assertIn("OutlookIcsImport.scanNow()", sidebar)
        self.assertIn("Config.options.calendar.timetable.imports.outlook.icsAttachments.enable", settings)
        self.assertIn("Check Outlook attachments", settings)
        self.assertIn("OutlookCalendarImport.enabled", shell)
        self.assertIn("OutlookIcsImport.enabled", shell)


if __name__ == "__main__":
    unittest.main()
