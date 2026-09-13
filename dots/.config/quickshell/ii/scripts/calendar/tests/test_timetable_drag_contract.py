#!/usr/bin/env python3
"""Regression contracts for timetable drag-to-create gestures."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CHEATSHEET = ROOT / "modules" / "ii" / "cheatsheet"
TIMETABLE = CHEATSHEET / "timetable"


class TimetableDragContractTests(unittest.TestCase):
    def test_day_grid_claims_the_pointer_and_locks_page_swiping(self) -> None:
        column = (TIMETABLE / "TimetableDayColumn.qml").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        host = (CHEATSHEET / "CheatsheetTimetable.qml").read_text(encoding="utf-8")
        cheatsheet = (CHEATSHEET / "Cheatsheet.qml").read_text(encoding="utf-8")

        self.assertIn("preventStealing: true", column)
        self.assertIn("acceptedButtons: Qt.LeftButton", column)
        self.assertIn("visible: isDragging && dragDayIndex === dayIdx", column)
        self.assertIn("property bool timetableDragActive: false", week)
        self.assertIn("function setTimetableDragActive(active)", week)
        self.assertIn("onDragRequestInteractivity: i => root.setTimetableDragActive(!i)", week)
        self.assertIn("onEventMoveStarted: (evt, x, y, offsetY) => {", week)
        self.assertIn("root.setTimetableDragActive(true);", week)
        self.assertIn("onEventMoveEnded: {", week)
        self.assertIn("root.setTimetableDragActive(false);", week)
        self.assertIn("readonly property bool timetableDragActive: root.activeViewItem?.timetableDragActive === true", host)
        self.assertIn("readonly property bool currentPageLocksHorizontalSwipe", cheatsheet)
        self.assertIn("interactive: !swipeView.currentPageLocksHorizontalSwipe", cheatsheet)

    def test_creation_preview_stays_visible_until_the_sidebar_closes(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        ghost_open = week.split("function openPopupForGhost()", 1)[1].split("function openPopupForEdit", 1)[0]

        self.assertIn("eventSidebar.startCreateAt(eventDate, topMin, botMin);", ghost_open)
        self.assertNotIn("root.ghostVisible = false;", ghost_open)
        self.assertIn("function clearGhostPreview()", week)
        self.assertIn("onCloseRequested: root.clearGhostPreview()", week)


if __name__ == "__main__":
    unittest.main()
