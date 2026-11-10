#!/usr/bin/env python3
"""Wiring contracts for the Clock app's Reminders tab (Samsung Reminder's model).

The logic has its own Node tests (test_reminders_logic.cjs) and the To Do bridge its
Python ones (scripts/outlook/tests/test_todo_sync.py). These pin the seams between
files, each of which failed silently while it was being built: a tab missing from the
app's id list, a notification action nobody forwarded, an island activity without a
source, a family that never loaded the alert.
"""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


class RemindersContractTests(unittest.TestCase):
    def test_the_tab_is_registered_everywhere_the_clock_lists_tabs(self) -> None:
        content = read("modules/ii/clock/ClockAppContent.qml")
        self.assertIn('{ id: "reminders", icon: "task_alt", label: Translation.tr("Reminders") }', content)
        self.assertIn("reminders: remindersComponent", content)
        self.assertIn("RemindersTab {", content)
        self.assertIn("onSettingsRequested: root.toggleSettings()", content)
        # Seven tabs: Ctrl+7 has to reach the last one.
        self.assertIn("event.key - Qt.Key_1 < root.tabIds.length", content)
        self.assertIn('"reminders"]', read("modules/ii/clock/ClockApp.qml"))
        self.assertIn('{ id: "reminders", label: Translation.tr("Reminders") }', read("modules/ii/clock/tabs/ClockSettingsPage.qml"))

    def test_service_is_touched_at_startup_and_owns_its_own_file(self) -> None:
        shell = read("shell.qml")
        self.assertIn("RemindersService.loaded;", shell)
        self.assertIn("RemindersSync.enabled;", shell)
        self.assertIn("remindersPath", read("modules/common/Directories.qml"))
        service = read("services/RemindersService.qml")
        self.assertIn("path: Qt.resolvedUrl(Directories.remindersPath)", service)
        self.assertNotIn("Todo.", service)

    def test_notification_actions_reach_the_service(self) -> None:
        notifications = read("services/Notifications.qml")
        self.assertIn('startsWith("__qs_reminder_")', notifications)
        service = read("services/RemindersService.qml")
        for action in ("__qs_reminder_complete", "__qs_reminder_snooze", "__qs_reminder_open"):
            self.assertIn(action, service)
        self.assertIn("function onInternalActionInvoked(identifier, notificationId, payload)", service)

    def test_alerts_never_poll_faster_than_a_minute(self) -> None:
        service = read("services/RemindersService.qml")
        self.assertIn("Math.min(next.at - Date.now(), 60000)", service)
        self.assertNotIn("interval: 1000\n        repeat: true", service)

    def test_every_family_loads_the_full_screen_alert(self) -> None:
        self.assertIn("reminderAlertPopup/ReminderAlertPopup.qml", read("panelFamilies/IllogicalImpulseFamily.qml"))
        for family in ("panelFamilies/TabletFamily.qml", "panelFamilies/WaffleFamily.qml"):
            text = read(family)
            self.assertIn("import qs.modules.ii.reminderAlertPopup", text)
            self.assertIn("component: ReminderAlertPopup {}", text)
        popup = read("modules/ii/reminderAlertPopup/ReminderAlertPopup.qml")
        self.assertIn("!GlobalStates.islandOwnsReminder", popup)

    def test_island_has_descriptor_source_presentation_and_ownership(self) -> None:
        registry = read("modules/ii/dynamicIsland/core/IslandRegistry.qml")
        self.assertIn('id: "reminder",', registry)
        self.assertIn('legacyContent: "FloatingNotchReminder.qml"', registry)
        self.assertIn('id: "reminderSoon",', registry)
        sources = read("modules/ii/dynamicIsland/core/sources/IslandSources.qml")
        self.assertIn("readonly property ReminderSource reminder: ReminderSource {}", sources)
        self.assertIn("readonly property ReminderSoonSource reminderSoon: ReminderSoonSource {}", sources)
        self.assertIn("alarm, reminder, fingerprint", sources)
        self.assertTrue((ROOT / "modules/ii/dynamicIsland/widgets/FloatingNotchReminder.qml").exists())
        self.assertIn('property: "islandOwnsReminder"', read("modules/ii/dynamicIsland/core/IslandPolicy.qml"))
        self.assertIn("property bool islandOwnsReminder: false", read("GlobalStates.qml"))
        face = read("modules/ii/dynamicIsland/styles/notch/NotchRestingFace.qml")
        self.assertIn('case "reminderSoon": return reminderGlance.implicitWidth;', face)
        self.assertIn('case "reminderSoon": return reminderSlot;', face)
        self.assertIn('"reminderSoon"', read("modules/ii/dynamicIsland/styles/notch/NotchIsland.qml"))

    def test_dashboard_widget_is_in_the_catalogue_and_the_chooser(self) -> None:
        catalog = read("modules/common/quickToggles/androidStyle/QuickToggleCatalog.js")
        self.assertIn('fullRemindersWidget: { kind: "fullDashboardWidget"', catalog)
        self.assertIn('roleValue: "fullRemindersWidget"', read("modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"))
        toggle = read("modules/common/quickToggles/androidStyle/AndroidFullDashboardWidgetToggle.qml")
        self.assertIn("RemindersDashboardWidget {", toggle)
        self.assertIn("fullRemindersWidget:", read("modules/common/quickToggles/androidStyle/QuickToggleTrayPreview.qml"))

    def test_timetable_shows_and_completes_reminders(self) -> None:
        month = read("modules/ii/cheatsheet/timetable/MonthView.qml")
        self.assertIn("RemindersService.timetableItems[H.dayKeyOf(date)]", month)
        for path in ("modules/ii/cheatsheet/timetable/MonthView.qml", "modules/ii/cheatsheet/timetable/WeekView.qml",
                     "modules/ii/cheatsheet/timetable/MonthUpcomingPanel.qml"):
            text = read(path)
            self.assertNotIn("=> Todo.markDone(task)\n", text.replace("RemindersService.completeTask(task) || Todo.markDone(task)", ""))
            self.assertIn("RemindersService.completeTask(task) || Todo.markDone(task)", text)
        self.assertIn("readonly property bool isReminder", read("modules/ii/cheatsheet/timetable/TaskChip.qml"))

    def test_todo_scope_is_only_requested_once_sync_is_on(self) -> None:
        outlook = read("services/OutlookService.qml")
        self.assertIn('root.baseScopes.concat(["Tasks.ReadWrite"])', outlook)
        # A refresh asking for a scope never consented to signs the calendar out.
        self.assertIn("scopes: root.refreshScopes", outlook)
        self.assertIn("root.wantsTasks && root.tasksConsented ? root.scopes : root.baseScopes", outlook)
        sync = read("services/RemindersSync.qml")
        self.assertIn('Directories.scriptPath + "/outlook/todo_sync.py"', sync)
        self.assertIn("OutlookService.tasksConsented", sync)

    def test_config_has_the_reminders_block(self) -> None:
        config = read("modules/common/Config.qml")
        self.assertIn("property JsonObject reminders: JsonObject {", config)
        self.assertIn('property string defaultAlert: "light"', config)
        self.assertIn("property JsonObject todoSync: JsonObject {", config)


if __name__ == "__main__":
    unittest.main()
