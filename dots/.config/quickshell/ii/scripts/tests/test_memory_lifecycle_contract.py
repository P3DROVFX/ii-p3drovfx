"""Contracts for the dashboard/service memory lifecycle optimizations."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class MemoryLifecycleContractTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_notifications_release_wrappers_and_pending_entries(self):
        source = self.read("services/Notifications.qml")
        self.assertIn("property bool _releasing: false", source)
        self.assertIn("function releaseNotificationObject(notifObject)", source)
        self.assertIn("notifObject.destroy();", source)
        self.assertIn("root._pendingNotifications = root._pendingNotifications.filter", source)
        self.assertIn("maximumHistoryEntries: 200", source)

    def test_sound_pool_unloads_after_playback_stops(self):
        source = self.read("services/SoundService.qml")
        self.assertIn("onPlaybackStateChanged: root._handlePlayerStateChanged(eventPlayer)", source)
        self.assertIn("MediaPlayer.PlayingState", source)
        self.assertIn("playersUnloadTimer.stop();", source)
        self.assertIn("playersLoader.active = false;", source)

    def test_todo_only_loads_selected_task_list(self):
        source = self.read("modules/common/dashboardWidgets/todo/TodoWidget.qml")
        swipe = source.split("SwipeView {", 1)[1].split("// + FAB", 1)[0]
        self.assertEqual(swipe.count("Loader {"), 2)
        self.assertEqual(swipe.count("active: root.selectedTab ==="), 2)
        self.assertNotIn("TaskList {\n                dense:", swipe)

    def test_ticktick_has_one_selected_provider_refresh_owner(self):
        ticktick = self.read("services/TickTickService.qml")
        todo = self.read("services/Todo.qml")
        self.assertIn('selectedProvider: Config.options?.todo?.provider === "ticktick"', ticktick)
        self.assertIn("running: root.available && root.selectedProvider", ticktick)
        self.assertIn('running: root.provider === "googleTasks" && root.connected', todo)
        self.assertIn("hasDatedOpenTasks", todo)
        self.assertIn("running: root.hasDatedOpenTasks", todo)

    def test_calendar_reuses_shared_day_index_and_bounds_details(self):
        widget = self.read("modules/common/dashboardWidgets/calendar/CalendarWidget.qml")
        service = self.read("services/CalendarService.qml")
        self.assertIn("CalendarService.eventsByDay", widget)
        self.assertIn("CalendarService.eventsForDay", widget)
        self.assertIn("maximumEventDetailsEntries: 8", service)
        self.assertIn("eventDetailsTtlMs: 15 * 60 * 1000", service)
        self.assertIn("function pruneEventDetails", service)

    def test_sports_has_idle_gate_empty_selection_and_byte_cap(self):
        source = self.read("services/SportsService.qml")
        self.assertIn("GlobalStates?.lockLookActive", source)
        self.assertIn("dock?.enableSportsWidget ?? false", source)
        self.assertIn('monitored !== undefined && monitored !== null', source)
        self.assertIn("maximumDetailsCacheBytes: 2 * 1024 * 1024", source)
        self.assertIn("function prunedDetailsCache(values)", source)
        self.assertIn("delete nextCache[id];", source)


if __name__ == "__main__":
    unittest.main()
