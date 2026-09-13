#!/usr/bin/env python3
"""Static contracts for progressive timetable and ESPN loading."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CHEATSHEET = ROOT / "modules" / "ii" / "cheatsheet"
TIMETABLE = CHEATSHEET / "timetable"


class TimetableLazyLoadingContractTests(unittest.TestCase):
    def test_timetable_tab_and_selected_view_incubate_across_frames(self) -> None:
        cheatsheet = (CHEATSHEET / "Cheatsheet.qml").read_text(encoding="utf-8")
        host = (CHEATSHEET / "CheatsheetTimetable.qml").read_text(encoding="utf-8")

        self.assertIn('asynchronous: modelData.icon === "calendar_month"', cheatsheet)
        self.assertGreaterEqual(host.count("asynchronous: true"), 2)

    def test_sports_start_only_after_the_base_view_is_ready(self) -> None:
        host = (CHEATSHEET / "CheatsheetTimetable.qml").read_text(encoding="utf-8")

        self.assertIn("readonly property bool activeViewReady", host)
        self.assertIn("id: sportsActivationTimer", host)
        self.assertIn("sportsEnabled: root.sportsReady", host)
        self.assertIn("SportsService.acquireTimetableSubscriber()", host)
        self.assertNotIn("Component.onCompleted: SportsService.acquireTimetableSubscriber()", host)

    def test_timetable_sports_are_explicitly_opt_in(self) -> None:
        config = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
        settings = (ROOT / "modules" / "settings" / "configs" / "widgets" / "TimetableConfig.qml").read_text(encoding="utf-8")
        host = (CHEATSHEET / "CheatsheetTimetable.qml").read_text(encoding="utf-8")

        self.assertIn("property bool sportsEvents: false", config)
        self.assertIn('text: Translation.tr("Show sports events")', settings)
        self.assertIn("checked: Config.options.calendar.timetable.sportsEvents", settings)
        self.assertIn("readonly property bool sportsRequested: Config.options.calendar.timetable.sportsEvents", host)
        self.assertIn("if (!root.sportsRequested)", host)
        self.assertIn("SportsService.releaseTimetableSubscriber()", host)

    def test_month_cells_are_materialized_progressively(self) -> None:
        month = (TIMETABLE / "MonthView.qml").read_text(encoding="utf-8")
        cell = (TIMETABLE / "MonthDayCell.qml").read_text(encoding="utf-8")

        self.assertIn("property bool sportsEnabled: false", month)
        self.assertIn("property int loadedCellCount: 0", month)
        self.assertIn("readonly property int cellCount: root.cells?.length ?? 0", month)
        self.assertIn("readonly property bool initialLoadComplete", month)
        self.assertNotIn("id: cellLoadTimer", month)
        self.assertIn("model: root.cells ?? []", month)
        self.assertIn("id: cellLoader", month)
        self.assertIn("active: index <= root.loadedCellCount", month)
        self.assertIn("asynchronous: true", month)
        self.assertIn("onLoaded: root.advanceCellLoading(index)", month)
        self.assertIn("sportsEnabled: root.sportsEnabled", month)
        self.assertIn("property bool sportsEnabled: false", cell)
        self.assertIn("root.sportsEnabled ? SportsService.gamesForDate", cell)

    def test_week_columns_are_materialized_progressively(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")

        self.assertIn("property bool sportsEnabled: false", week)
        self.assertIn("property int loadedDayCount: 0", week)
        self.assertIn("readonly property int dayCount: root.days?.length ?? 0", week)
        self.assertIn("readonly property bool initialLoadComplete", week)
        self.assertNotIn("id: dayLoadTimer", week)
        self.assertIn("days: (root.days ?? []).slice(0, Math.max(0, root.loadedDayCount))", week)
        self.assertIn("model: root.days ?? []", week)
        self.assertIn("id: dayLoader", week)
        self.assertIn("active: index <= root.loadedDayCount", week)
        self.assertIn("asynchronous: true", week)
        self.assertIn("onLoaded: root.advanceDayLoading(index)", week)

    def test_week_initial_scroll_stops_retrying_after_it_is_applied(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        initial_scroll = week.split("function maybeApplyInitialScroll()", 1)[1].split("function toggleSportsDay", 1)[0]

        self.assertIn("if (root.initialScrollApplied)\n            return;", initial_scroll)
        self.assertIn("initialScrollRetryTimer.restart()", initial_scroll)
        self.assertNotIn("Qt.callLater(root.maybeApplyInitialScroll);", initial_scroll)
        self.assertIn("id: initialScrollRetryTimer", week)

    def test_week_preferences_refresh_without_replaying_column_stagger(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        calendar = (ROOT / "services" / "CalendarService.qml").read_text(encoding="utf-8")

        preferences = week.split("target: Config.options.cheatsheet", 1)[1].split("onViewModeChanged:", 1)[0]
        self.assertNotIn("root.restartDayLoading();", preferences)
        self.assertEqual(week.count("root.restartDayLoading();"), 2)
        self.assertGreaterEqual(week.count("root.refreshVisibleRange();"), 2)
        self.assertNotIn("property var eventsInWeek", calendar)
        self.assertNotIn("function getEventsInWeek()", calendar)

    def test_week_view_excludes_task_projection(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        header = (TIMETABLE / "TimetableHeader.qml").read_text(encoding="utf-8")

        self.assertNotIn("tasksForDay", week)
        self.assertNotIn("taskCount", week)
        self.assertNotIn("taskCompletionRequested", week)
        self.assertNotIn("modelData.tasks", header)
        self.assertNotIn("TaskChip", header)
        self.assertNotIn("taskCompletionRequested", header)

    def test_espn_projection_has_a_per_frame_time_budget(self) -> None:
        sports = (ROOT / "services" / "SportsService.qml").read_text(encoding="utf-8")

        self.assertIn("readonly property int timetableProjectionBudgetMs", sports)
        self.assertIn("id: timetableProjectionTimer", sports)
        self.assertIn("id: timetableProjectionTimer\n        interval: 16", sports)
        self.assertIn("Date.now() - startedAt < root.timetableProjectionBudgetMs", sports)
        self.assertIn("if (!root.timetableActive)", sports)
        self.assertIn("function cachedRangeSources()", sports)
        self.assertNotIn("root.timetableProjectionSource = root.cachedRangeEvents()", sports)
        self.assertIn("timetableProjectionCompactEvents", sports)
        self.assertNotIn("const rawEvents = root.timetableProjectionRawEvents", sports)


if __name__ == "__main__":
    unittest.main()
