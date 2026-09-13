#!/usr/bin/env python3
"""Static contracts for the timetable editor presentation."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
TIMETABLE = ROOT / "modules" / "ii" / "cheatsheet" / "timetable"


class TimetablePresentationContractTests(unittest.TestCase):
    def test_week_zoom_uses_persistent_discrete_slot_heights(self) -> None:
        persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")

        self.assertIn("property int timetableSlotHeight: 168", persistent)
        self.assertIn("property int timetableSlotHeightVersion: 0", persistent)
        self.assertIn("readonly property list<int> slotHeightSteps: [96, 120, 144, 168, 192]", week)
        self.assertIn("readonly property int comfortableSlotHeight: 168", week)
        self.assertIn("readonly property int slotHeightStateVersion: 1", week)
        self.assertIn("property int slotHeight: Persistent.states.cheatsheet.timetableSlotHeight", week)
        self.assertIn("function normalizeSlotHeight()", week)
        self.assertIn("Persistent.states.cheatsheet.timetableSlotHeight = root.comfortableSlotHeight", week)
        self.assertIn("Persistent.states.cheatsheet.timetableSlotHeightVersion = root.slotHeightStateVersion", week)
        self.assertIn("function zoomSlotHeight(direction, viewportY)", week)
        self.assertIn("acceptedModifiers: Qt.ControlModifier", week)
        self.assertIn("root.zoomSlotHeight(root.zoomWheelAccumulator > 0 ? 1 : -1, event.y)", week)
        self.assertNotIn("event.position.y", week)
        self.assertIn("Persistent.states.cheatsheet.timetableSlotHeight = nextHeight", week)
        self.assertIn("const focalMinutes = (styledFlickable.contentY + focalY) / oldPixelsPerMinute", week)

    def test_timed_blocks_never_outgrow_their_time_span(self) -> None:
        helper = (TIMETABLE / "TimetableHelpers.js").read_text(encoding="utf-8")
        block = (TIMETABLE / "EventBlock.qml").read_text(encoding="utf-8")
        column = (TIMETABLE / "TimetableDayColumn.qml").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")

        self.assertIn("function timedBlockHeight(startMinutes, endMinutes, pixelsPerMinute, gap)", helper)
        self.assertIn("return Math.max(1, (endMinutes - startMinutes) * pixelsPerMinute - gap);", helper)
        self.assertIn("height: H.timedBlockHeight(eventStartMinutes, eventEndMinutes, pixelsPerMinute, eventSpacing)", block)
        self.assertIn("eventSpacing: dayColumn.eventSpacing", column)
        self.assertIn("eventSpacing: root.spacing / 2", week)
        self.assertIn("height: H.timedBlockHeight(root.timedMutationStartMinutes, root.timedMutationEndMinutes, root.pixelsPerMinute, root.spacing / 2)", week)
        self.assertNotIn("Math.max((eventEndMinutes - eventStartMinutes) * pixelsPerMinute - 4, 48)", block)

    def test_dense_timed_block_geometry_stays_disjoint(self) -> None:
        helper_path = TIMETABLE / "TimetableHelpers.js"
        script = f"""
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync({json.dumps(str(helper_path))}, "utf8")
    .replace(/^\\.pragma library\\s*/, "");
const context = {{}};
vm.createContext(context);
vm.runInContext(source, context);
for (const slotHeight of [96, 120, 144, 168, 192]) {{
    const pixelsPerMinute = slotHeight / 60;
    const timeSpan = 30 * pixelsPerMinute;
    const blockHeight = context.timedBlockHeight(0, 30, pixelsPerMinute, 4);
    if (blockHeight !== timeSpan - 4 || blockHeight >= timeSpan)
        throw new Error(JSON.stringify({{slotHeight, timeSpan, blockHeight}}));
}}
const comfortablePixelsPerMinute = 168 / 60;
if (context.timedBlockHeight(0, 15, comfortablePixelsPerMinute, 4) < 38)
    throw new Error("15-minute title does not fit at comfortable zoom");
if (context.timedBlockHeight(0, 30, comfortablePixelsPerMinute, 4) <= 60)
    throw new Error("30-minute metadata does not fit at comfortable zoom");
"""
        subprocess.run(["node", "-e", script], check=True, capture_output=True, text=True)

    def test_week_grid_draws_one_shared_hour_ruler(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        time_column = (TIMETABLE / "TimetableTimeColumn.qml").read_text(encoding="utf-8")

        self.assertIn("property int timeColumnWidth: 56", week)
        self.assertEqual(week.count("id: gridLineLayer"), 1)
        self.assertIn("model: root.totalSlots", week)
        self.assertIn("y: parent.height / 2", week)
        self.assertIn("H.withOpacity(Appearance.colors.colOutlineVariant", week)
        self.assertIn("anchors.right: parent.right", time_column)
        self.assertIn("horizontalAlignment: Text.AlignRight", time_column)

    def test_week_gutter_identifies_timezone_and_iso_week(self) -> None:
        helper = (TIMETABLE / "TimetableHelpers.js").read_text(encoding="utf-8")
        header = (TIMETABLE / "TimetableHeader.qml").read_text(encoding="utf-8")
        current_time = (TIMETABLE / "TimetableCurrentTime.qml").read_text(encoding="utf-8")

        self.assertIn("function timezoneLabel(date)", helper)
        self.assertIn("function isoWeekNumber(date)", helper)
        self.assertIn("H.timezoneLabel(headerRow.referenceDate)", header)
        self.assertIn('text: "W" + String(H.isoWeekNumber(headerRow.referenceDate))', header)
        self.assertIn("text: DateTime.time", current_time)
        self.assertIn("anchors.verticalCenter: parent.verticalCenter", current_time)

    def test_week_header_reuses_daily_weather_forecast(self) -> None:
        header = (TIMETABLE / "TimetableHeader.qml").read_text(encoding="utf-8")

        self.assertIn("readonly property var forecast:", header)
        self.assertIn("(Weather.forecastData ?? []).find", header)
        self.assertIn("WeatherIcons.getWeatherIcon(dayDelegate.forecast?.code ?? 113, false)", header)
        self.assertIn("Weather.useUSCS ? dayDelegate.forecast?.maxF", header)
        self.assertIn("Weather.useUSCS ? dayDelegate.forecast?.minF", header)
        self.assertIn("dayDelegate.width > 104", header)

    def test_all_day_lane_caps_rows_and_expands_with_internal_scroll(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        header = (TIMETABLE / "TimetableHeader.qml").read_text(encoding="utf-8")

        self.assertIn("property bool allDayExpanded: false", week)
        self.assertIn("readonly property int collapsedAllDayRows: 2", week)
        self.assertIn("readonly property int expandedAllDayRows: 5", week)
        self.assertIn("readonly property int visibleAllDayRows", week)
        self.assertIn("Behavior on headerHeight", week)
        self.assertIn("visibleAllDayRows: root.visibleAllDayRows", week)
        self.assertIn("onAllDayExpansionRequested: expanded => root.allDayExpanded = expanded", week)
        self.assertIn("id: allDayArea", header)
        self.assertIn("interactive: headerRow.expanded && contentHeight > height", header)
        self.assertIn("Translation.tr(\"%1 more\").arg(String(dayDelegate.hiddenChipCount))", header)

    def test_week_day_columns_keep_a_uniform_background(self) -> None:
        day_column = (TIMETABLE / "TimetableDayColumn.qml").read_text(encoding="utf-8")

        self.assertNotIn("sunriseMinutes", day_column)
        self.assertNotIn("sunsetMinutes", day_column)
        self.assertNotIn("preDawnShade", day_column)
        self.assertNotIn("eveningShade", day_column)
        self.assertIn("color: isToday ? todayHighlightFill : dayIdx % 2 == 0 ? dayBackgroundFill : dayBackgroundFillVariant", day_column)

    def test_week_columns_keep_a_stable_calendar_background(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        day_column = (TIMETABLE / "TimetableDayColumn.qml").read_text(encoding="utf-8")

        self.assertNotIn("AppStats", week + day_column)
        self.assertNotIn("usageIntensity", day_column)
        self.assertNotIn("model: 24", day_column)
        self.assertIn("color: isToday ? todayHighlightFill : dayIdx % 2 == 0 ? dayBackgroundFill : dayBackgroundFillVariant", day_column)

    def test_month_density_modes_are_persistent_and_reduce_cell_chrome(self) -> None:
        persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")
        month = (TIMETABLE / "MonthView.qml").read_text(encoding="utf-8")
        cell = (TIMETABLE / "MonthDayCell.qml").read_text(encoding="utf-8")

        self.assertIn('property string timetableMonthDensity: "compact"', persistent)
        self.assertIn('readonly property var densityModes: ["comfortable", "compact", "dots"]', month)
        self.assertIn("Persistent.states.cheatsheet.timetableMonthDensity = root.densityModes[index]", month)
        self.assertIn("densityMode: root.densityMode", month)
        self.assertIn("readonly property real headerHeight: 22", cell)
        self.assertIn("readonly property real chipSpacing: 2", cell)
        self.assertIn('readonly property real chipHeight: root.densityMode === "comfortable" ? 24 : 16', cell)
        self.assertIn('visible: root.densityMode === "dots" && root.entryCount > 0', cell)
        self.assertIn("id: densityDots", cell)
        self.assertEqual(cell.count("root.isToday || root.isTomorrow || cellPointer.containsMouse"), 2)

    def test_month_recurring_series_collapse_into_stable_bands(self) -> None:
        persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")
        month = (TIMETABLE / "MonthView.qml").read_text(encoding="utf-8")
        cell = (TIMETABLE / "MonthDayCell.qml").read_text(encoding="utf-8")

        self.assertIn("property bool timetableCollapseRecurring: true", persistent)
        self.assertIn("function recurrenceSeriesKey(event)", month)
        self.assertIn("String(event?.uid ?? \"\")", month)
        self.assertIn("String(event.calendar ?? \"\")", month)
        self.assertIn("function buildRecurringProjection()", month)
        self.assertIn("root.recurringProjection.hiddenOccurrences", month)
        self.assertIn("id: recurringBand", month)
        self.assertIn("recurrenceLaneOffset:", month)
        self.assertIn("property real recurrenceLaneOffset: 0", cell)
        self.assertIn("root.recurrenceLaneOffset", cell)
        self.assertIn("Persistent.states.cheatsheet.timetableCollapseRecurring =", month)

    def test_week_navigation_uses_a_real_anchor_and_shared_picker(self) -> None:
        helper = (TIMETABLE / "TimetableHelpers.js").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")

        self.assertIn("function weekStartFor(date, firstDayOfWeek, todayFirst)", helper)
        self.assertIn("property date viewWeekStart", week)
        self.assertIn("function shiftWeek(delta)", week)
        self.assertIn("function goToday()", week)
        self.assertIn('datePicker.purpose = "navigate"', week)
        self.assertIn('if (datePicker.purpose === "navigate")', week)
        self.assertIn("const calendarEvents = CalendarService.eventsByDay", week)
        self.assertNotIn("CalendarService.eventsInWeek", week)
        self.assertIn("onRevealKeyChanged: dayColDelegate.replayEntrance()", week)

    def test_day_three_day_week_and_month_share_the_persisted_selector(self) -> None:
        persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")
        host = (ROOT / "modules" / "ii" / "cheatsheet" / "CheatsheetTimetable.qml").read_text(encoding="utf-8")
        selector = (TIMETABLE / "TimetableViewSwitch.qml").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")

        self.assertIn('// "day" | "threeDay" | "week" | "month"', persistent)
        self.assertIn('readonly property var supportedModes: ["day", "threeDay", "week", "month"]', host)
        self.assertIn('active: root.activeMode !== "month"', host)
        self.assertIn("viewMode: root.activeMode", host)
        self.assertIn('readonly property var modes: ["day", "threeDay", "week", "month"]', selector)
        self.assertEqual(selector.count('"icon":'), 4)
        self.assertIn("Persistent.states.cheatsheet.timetableView = root.modes[index]", selector)
        self.assertIn('readonly property int visibleDayCount: root.viewMode === "day" ? 1 : (root.viewMode === "threeDay" ? 3 : 7)', week)
        self.assertIn("for (let i = 0; i < root.visibleDayCount; i++)", week)
        self.assertIn("delta * root.visibleDayCount", week)
        self.assertIn("onViewModeChanged: {", week)

    def test_both_views_expose_keyboard_calendar_navigation(self) -> None:
        host = (ROOT / "modules" / "ii" / "cheatsheet" / "CheatsheetTimetable.qml").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        header = (TIMETABLE / "TimetableHeader.qml").read_text(encoding="utf-8")
        month = (TIMETABLE / "MonthView.qml").read_text(encoding="utf-8")
        cell = (TIMETABLE / "MonthDayCell.qml").read_text(encoding="utf-8")

        self.assertIn("Keys.priority: Keys.AfterItem", host)
        self.assertIn("root.activeViewItem.handleNavigationKey(event)", host)
        for source in (week, month):
            self.assertIn("function handleNavigationKey(event)", source)
            self.assertIn("Qt.Key_Left", source)
            self.assertIn("Qt.Key_PageUp", source)
            self.assertIn("Qt.Key_Home", source)
            self.assertIn("Qt.Key_Return", source)
        self.assertIn("function scrollKeyboardHours(delta)", week)
        self.assertIn("keyboardNavigationActive: root.keyboardNavigationActive", week)
        self.assertIn("toggled: headerRow.keyboardNavigationActive", header)
        self.assertIn("keyboardSelected: root.keyboardNavigationActive", month)
        self.assertIn("property bool keyboardSelected: false", cell)

    def test_week_and_month_share_semantic_event_colors(self) -> None:
        helper = (TIMETABLE / "TimetableHelpers.js").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        block = (TIMETABLE / "EventBlock.qml").read_text(encoding="utf-8")
        header = (TIMETABLE / "TimetableHeader.qml").read_text(encoding="utf-8")

        self.assertIn("function chipColor(event, palette", helper)
        self.assertIn("H.chipColor(eventData, Appearance.colors", block)
        self.assertIn("H.chipColor(modelData, Appearance.colors", header)
        self.assertIn("H.chipColor(root.timedMutationEvent, Appearance.colors", week)

    def test_proximity_gradient_is_opt_in_and_preserves_synced_colors(self) -> None:
        config = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
        settings = (ROOT / "modules" / "settings" / "configs" / "widgets" / "TimetableConfig.qml").read_text(encoding="utf-8")
        helper_path = TIMETABLE / "TimetableHelpers.js"
        helper = helper_path.read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        column = (TIMETABLE / "TimetableDayColumn.qml").read_text(encoding="utf-8")
        block = (TIMETABLE / "EventBlock.qml").read_text(encoding="utf-8")
        month = (TIMETABLE / "MonthView.qml").read_text(encoding="utf-8")

        self.assertIn("property bool proximityColorGradient: false", config)
        self.assertIn('text: Translation.tr("Proximity color gradient")', settings)
        self.assertIn("checked: Config.options.calendar.timetable.proximityColorGradient", settings)
        self.assertIn("function eventColorWithProximity(baseColor, enabled, dayIndex, startMinutes, nextEvtData, maxDist, colors)", helper)
        self.assertIn("if (!enabled || !nextEvtData)", helper)
        self.assertIn("return baseColor;", helper)
        self.assertIn("H.eventColorWithProximity(", block)
        self.assertIn("property real maxLogicalDistance: 1.0", week)
        self.assertIn("maxLogicalDistance: root.maxLogicalDistance", week)
        self.assertIn("maxLogicalDistance: dayColumn.maxLogicalDistance", column)
        self.assertNotIn("ColorUtils.mix(eventBlock.semanticColor", block)
        self.assertNotIn("eventColorWithProximity", month)

        script = f"""
const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync({json.dumps(str(helper_path))}, "utf8")
    .replace(/^\\.pragma library\\s*/, "");
const context = {{}};
vm.createContext(context);
vm.runInContext(source, context);
const syncedColor = "#a1b2c3";
const actual = context.eventColorWithProximity(syncedColor, false, 0, 600, {{dayIndex: 0, startMinutes: 600}}, 1, {{}});
if (actual !== syncedColor)
    throw new Error(`disabled proximity gradient changed ${{syncedColor}} to ${{actual}}`);
const palette = {{
    colPrimary: "#112233",
    colSecondary: "#445566",
    colTertiary: "#778899",
    colSurfaceContainerHighest: "#aabbcc"
}};
const highlighted = context.eventColorWithProximity(syncedColor, true, 0, 600, {{dayIndex: 0, startMinutes: 600}}, 1, palette);
if (highlighted !== palette.colPrimary)
    throw new Error(`enabled proximity gradient did not center on the next event: ${{highlighted}}`);
"""
        subprocess.run(["node", "-e", script], check=True, capture_output=True, text=True)

    def test_week_and_month_consume_the_same_calendar_event_dto(self) -> None:
        calendar = (ROOT / "services" / "CalendarService.qml").read_text(encoding="utf-8")
        helper = (TIMETABLE / "TimetableHelpers.js").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        block = (TIMETABLE / "EventBlock.qml").read_text(encoding="utf-8")
        header = (TIMETABLE / "TimetableHeader.qml").read_text(encoding="utf-8")
        column = (TIMETABLE / "TimetableDayColumn.qml").read_text(encoding="utf-8")

        self.assertIn("events: calendarEvents?.[H.dayKeyOf(date)] ?? []", week)
        self.assertIn("function eventStartMinutes(event)", helper)
        self.assertIn("function eventEndMinutes(event)", helper)
        self.assertIn("H.eventStartMinutes(eventData)", block)
        self.assertIn("CalendarService.isAllDayEvent(event)", week + header + column)
        self.assertNotIn("sourceEvent", week + block + header + column)
        self.assertNotIn("property var eventsInWeek", calendar)
        self.assertNotIn("function getEventsInWeek()", calendar)

    def test_week_surfaces_do_not_use_rectangle_borders(self) -> None:
        for name in ("EventBlock.qml", "TimetableDayColumn.qml", "TimetableHeader.qml", "TimetableNextEventFAB.qml"):
            source = (TIMETABLE / name).read_text(encoding="utf-8")
            self.assertNotIn("border.width", source, name)
            self.assertNotIn("border.color", source, name)

    def test_next_event_fab_does_not_override_button_final_spacing(self) -> None:
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        fab = (TIMETABLE / "TimetableNextEventFAB.qml").read_text(encoding="utf-8")

        self.assertNotIn("property real spacing", fab)
        self.assertIn("property real itemSpacing", fab)
        self.assertIn("itemSpacing: root.spacing", week)

    def test_tall_meeting_blocks_expose_a_direct_join_action(self) -> None:
        block = (TIMETABLE / "EventBlock.qml").read_text(encoding="utf-8")

        self.assertIn("readonly property string meetingUrl", block)
        self.assertIn("EmailDetections.detectAll(url).meetings[0]?.url", block)
        self.assertIn("eventBlock.height > 60 && eventBlock.meetingUrl.length > 0", block)
        self.assertIn('text: "videocam"', block)
        self.assertIn("Qt.openUrlExternally(eventBlock.meetingUrl)", block)

    def test_color_picker_uses_semantic_hover_tokens(self) -> None:
        helper = (TIMETABLE / "TimetableHelpers.js").read_text(encoding="utf-8")
        picker = (TIMETABLE / "ColorPickerRow.qml").read_text(encoding="utf-8")

        for token in ("primary", "secondary", "tertiary", "error", "primarycontainer", "secondarycontainer", "tertiarycontainer", "errorcontainer"):
            self.assertIn(f'case "{token}"', helper)
        self.assertIn("function themeHoverColorForToken", helper)
        self.assertIn("H.themeHoverColorForToken(modelData.token, Appearance.colors)", picker)
        self.assertNotIn("ColorUtils.mix(tokenColor, Appearance.colors.colOnSurface", picker)
        self.assertIn("import qs.modules.common.functions", picker)

    def test_color_tooltips_use_the_delegate_hover_state(self) -> None:
        picker = (TIMETABLE / "ColorPickerRow.qml").read_text(encoding="utf-8")

        self.assertIn("id: colorButton", picker)
        self.assertIn("extraVisibleCondition: colorButton.hovered", picker)
        self.assertNotIn("extraVisibleCondition: parent.hovered", picker)

    def test_task_tooltip_reads_the_hover_handler_state(self) -> None:
        task_chip = (TIMETABLE / "TaskChip.qml").read_text(encoding="utf-8")

        self.assertIn("extraVisibleCondition: taskPointer.hovered", task_chip)
        self.assertNotIn("taskPointer.containsMouse", task_chip)

    def test_time_fields_are_centered_over_the_dial(self) -> None:
        picker = (TIMETABLE / "TimePickerPopup.qml").read_text(encoding="utf-8")

        self.assertIn("id: timeFields", picker)
        self.assertIn("anchors.horizontalCenter: parent.horizontalCenter", picker)
        self.assertIn("width: Math.max(root.dialSize, timeFields.implicitWidth)", picker)

    def test_month_forecast_uses_google_weather_assets(self) -> None:
        day_cell = (TIMETABLE / "MonthDayCell.qml").read_text(encoding="utf-8")

        self.assertIn("Image {\n            id: weatherIcon", day_cell)
        self.assertIn("WeatherIcons.getWeatherIcon(root.forecast?.code ?? 113, false)", day_cell)
        self.assertNotIn("function weatherSymbol", day_cell)

    def test_month_events_leave_space_below_the_day_header(self) -> None:
        day_cell = (TIMETABLE / "MonthDayCell.qml").read_text(encoding="utf-8")

        self.assertIn("readonly property real headerEventSpacing: 2", day_cell)
        self.assertIn("topMargin: root.headerEventSpacing", day_cell)
        self.assertIn("root.headerHeight - root.headerEventSpacing - root.recurrenceLaneOffset - root.cellPadding", day_cell)

    def test_event_metadata_inputs_have_helpful_placeholders(self) -> None:
        sidebar = (TIMETABLE / "EventSidebar.qml").read_text(encoding="utf-8")

        for placeholder in ("Add a label", "Add meeting link", "Add location"):
            self.assertIn(f'Translation.tr("{placeholder}")', sidebar)
            self.assertNotIn(f'placeholderText: Translation.tr("{placeholder}")', sidebar)
        self.assertNotIn("placeholderTextColor", sidebar)

    def test_dashed_borders_render_as_geometry_without_a_canvas_texture(self) -> None:
        dashed_border = (ROOT / "modules" / "common" / "widgets" / "DashedBorder.qml").read_text(encoding="utf-8")
        sidebar = (TIMETABLE / "EventSidebar.qml").read_text(encoding="utf-8")
        secondary_action = sidebar.split("component SecondaryAction:", 1)[1].split("component DurationChip:", 1)[0]

        self.assertIn("import QtQuick.Shapes", dashed_border)
        self.assertIn("ShapePath {", dashed_border)
        self.assertIn("PathRectangle {", dashed_border)
        self.assertIn('fillColor: "transparent"', dashed_border)
        self.assertIn("strokeStyle: root.gapLength > 0 ? ShapePath.DashLine : ShapePath.SolidLine", dashed_border)
        self.assertIn("strokeAdjustment: dashedPath.strokeWidth", dashed_border)
        self.assertNotIn("Canvas {", dashed_border)
        self.assertNotIn('getContext("2d")', dashed_border)
        self.assertIn("DashedBorder {", secondary_action)

    def test_calendar_notifications_use_an_installed_calendar_icon(self) -> None:
        notifier = (ROOT / "services" / "CalendarNotifier.qml").read_text(encoding="utf-8")

        self.assertIn('appIcon: "x-office-calendar"', notifier)
        self.assertIn("Notifications.publishInternalNotification", notifier)
        self.assertNotIn("notify-send", notifier)

    def test_upcoming_rail_highlights_the_current_or_next_event(self) -> None:
        panel = (TIMETABLE / "MonthUpcomingPanel.qml").read_text(encoding="utf-8")

        self.assertIn("readonly property string featuredEventRowKey", panel)
        self.assertIn("const inProgress = allDayToday ||", panel)
        self.assertIn("return current?.rowKey ?? next?.rowKey ?? \"\"", panel)
        self.assertIn("colBackground: featured ? accent : Appearance.colors.colLayer1", panel)
        self.assertIn("ColorUtils.getContrastingTextColor(accent)", panel)

    def test_upcoming_rail_shares_filters_and_lists_overdue_tasks(self) -> None:
        month = (TIMETABLE / "MonthView.qml").read_text(encoding="utf-8")
        panel = (TIMETABLE / "MonthUpcomingPanel.qml").read_text(encoding="utf-8")

        self.assertEqual(panel.count("Todo.getOverdueTasks("), 1)
        self.assertIn('rowKey: "task:overdue:"', panel)
        self.assertIn("buckets.today.push({", panel)
        self.assertIn("property string categoryFilter", panel)
        self.assertIn("property var holidaysByDay", panel)
        self.assertNotIn("Config.options.calendar.holidays", panel)
        self.assertIn("categoryFilter: root.categoryFilter", month)
        self.assertIn("holidaysByDay: root.holidayMap", month)

    def test_upcoming_rail_uses_fixed_hero_and_persistent_horizon_groups(self) -> None:
        config = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
        persistent = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")
        panel = (TIMETABLE / "MonthUpcomingPanel.qml").read_text(encoding="utf-8")

        self.assertIn("property int upcomingHorizonDays: 14", config)
        self.assertIn("Config.options.calendar.timetable.upcomingHorizonDays ?? 14", panel)
        self.assertIn("Layout.preferredHeight: 128", panel)
        self.assertNotIn("model: root.todayTasks", panel)
        self.assertIn('for (const key of ["today", "tomorrow", "thisWeek", "later"])', panel)
        self.assertIn('rowType: "group"', panel)
        self.assertIn("function toggleGroup(key)", panel)
        self.assertIn("property list<string> timetableCollapsedUpcomingGroups: []", persistent)
        self.assertIn("Persistent.states.cheatsheet.timetableCollapsedUpcomingGroups =", panel)

    def test_cancelled_events_are_struck_in_both_sidebars(self) -> None:
        upcoming = (TIMETABLE / "MonthUpcomingPanel.qml").read_text(encoding="utf-8")
        day_row = (TIMETABLE / "MonthDayEventRow.qml").read_text(encoding="utf-8")

        self.assertIn("font.strikeout: eventButton.cancelled", upcoming)
        self.assertIn("font.strikeout: root.cancelled", day_row)

    def test_timetable_hot_paths_do_not_log_unconditionally(self) -> None:
        host = (ROOT / "modules" / "ii" / "cheatsheet" / "CheatsheetTimetable.qml").read_text(encoding="utf-8")
        week = (TIMETABLE / "WeekView.qml").read_text(encoding="utf-8")
        month = (TIMETABLE / "MonthView.qml").read_text(encoding="utf-8")

        self.assertNotIn('console.info("[Timetable', host + week + month)

    def test_lineups_use_a_valid_material_apparel_symbol(self) -> None:
        details = (TIMETABLE / "SportsEventDetails.qml").read_text(encoding="utf-8")

        self.assertIn('modelData.group === "starters" ? "apparel"', details)
        self.assertNotIn('"sports_jersey"', details)


if __name__ == "__main__":
    unittest.main()
