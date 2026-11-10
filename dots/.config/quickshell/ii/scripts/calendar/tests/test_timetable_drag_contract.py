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
        self.assertIn('dayColumn.gesture.press("create"', column)
        self.assertIn("property bool timetableDragActive: false", week)
        self.assertIn("function setTimetableDragActive(active)", week)
        self.assertIn("function onBusyChanged()", week)
        self.assertIn("root.setTimetableDragActive(root.gesture.busy);", week)
        self.assertIn("onGestureFinished: result => root.handleGesture(result)", week)
        self.assertIn("readonly property bool timetableDragActive: root.activeViewItem?.timetableDragActive === true", host)
        self.assertIn("readonly property bool currentPageLocksHorizontalSwipe", cheatsheet)
        self.assertIn("interactive: !swipeView.currentPageLocksHorizontalSwipe", cheatsheet)

    def test_creation_preview_stays_visible_until_the_sidebar_closes(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        ghost_open = week.split("function openPopupForGhost()", 1)[1].split("function openPopupForEdit", 1)[0]

        self.assertIn("eventSidebar.startCreateAt(date, root.gesture.draftStart, root.gesture.draftEnd);", ghost_open)
        self.assertNotIn("clearDraft", ghost_open)
        self.assertIn("function clearGhostPreview()", week)
        self.assertIn("root.gesture.clearDraft();", week)
        self.assertIn("onCloseRequested: root.clearGhostPreview()", week)

    def test_moving_lifts_one_copy_instead_of_duplicating_the_event(self) -> None:
        block = (TIMETABLE / "EventBlock.qml").read_text(encoding="utf-8")
        layer = (TIMETABLE / "TimetableGestureLayer.qml").read_text(encoding="utf-8")

        # The source steps aside while the gesture is active; the lifted copy is the
        # only visible one, and it sits in the layer above every column.
        self.assertIn("opacity: eventBlock.manipulating ? 0 : 1", block)
        self.assertIn("manipulating: dayColumn.gesture !== null && dayColumn.gesture.active && eventData !== null && dayColumn.gesture.target === eventData", (TIMETABLE / "TimetableDayColumn.qml").read_text(encoding="utf-8"))
        self.assertIn("opacity: layer.eventMoving ? 1 : 0", layer)
        self.assertIn("StyledRectangularShadow {\n        target: movedCard", layer)

    def test_blocks_are_bound_by_position_so_a_commit_never_destroys_its_grab(self) -> None:
        column = (TIMETABLE / "TimetableDayColumn.qml").read_text(encoding="utf-8")

        # A commit runs inside the grab's own release handler; rebuilding the
        # Repeater there would destroy the MouseArea that is still executing.
        self.assertIn("model: dayColumn.layout.length", column)
        self.assertIn("readonly property var slot: dayColumn.layout[index] ?? null", column)
        self.assertNotIn("model: dayColumn.layout\n", column)

    def test_a_drop_that_changes_nothing_never_writes_the_calendar(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        commit = week.split("function commitTiming(result)", 1)[1].split("// The gesture reports", 1)[0]

        self.assertIn("result.start === result.originStart && result.end === result.originEnd", commit)
        self.assertIn("return;", commit)
        self.assertLess(commit.index("return;"), commit.index("dispatchFields"))

    def test_a_moved_event_stays_put_until_the_calendar_confirms_it(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")

        # Projection lives in WeekView, not in CalendarService, and is only
        # dropped when khal lists the event at the target range.
        self.assertIn("property var pendingMoves: ({})", week)
        self.assertIn("function pruneConfirmedMoves()", week)
        self.assertIn("root.pruneConfirmedMoves();", week)
        self.assertIn("evt.startDate?.getTime() === move.start && evt.endDate?.getTime() === move.end", week)
        self.assertIn("id: pendingMovesTimer", week)

    def test_gesture_keys_escape_and_auto_scroll_the_grid(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        escape = week.split("function handleEscape()", 1)[1].split("if (datePicker.opened)", 1)[0]

        self.assertIn("root.gesture.cancel();", escape)
        self.assertIn("root.gesture.scrollBy(applied);", week)
        self.assertIn("running: root.gesture.active", week)


if __name__ == "__main__":
    unittest.main()
