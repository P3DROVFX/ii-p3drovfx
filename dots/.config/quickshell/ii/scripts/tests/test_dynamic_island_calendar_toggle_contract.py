import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
CATALOG_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleCatalog.js"
CHOOSER_PATH = ROOT / "modules/common/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
TRAY_PREVIEW_PATH = ROOT / "modules/common/quickToggles/androidStyle/QuickToggleTrayPreview.qml"
TILE_PATH = ROOT / "modules/common/quickToggles/androidStyle/calendar/AndroidCalendarMinimalToggle.qml"
GRID_TILE_PATH = ROOT / "modules/common/quickToggles/androidStyle/calendar/AndroidCalendarMonthGridToggle.qml"
UPCOMING_TILE_PATH = ROOT / "modules/common/quickToggles/androidStyle/calendar/AndroidCalendarUpcomingToggle.qml"
MONTH_CARD_PATH = ROOT / "modules/common/quickToggles/androidStyle/calendar/AndroidCalendarMonthAgendaToggle.qml"
ROWS_PATH = ROOT / "modules/common/quickToggles/androidStyle/calendar/CalendarEventRows.qml"


class DynamicIslandCalendarToggleContractTest(unittest.TestCase):
    def catalog_definition(self, type_name):
        catalog_text = CATALOG_PATH.read_text(encoding="utf-8")
        self.assertIn(f"{type_name}: {{", catalog_text, f"{type_name} missing in catalog")
        return catalog_text.split(f"{type_name}: {{")[1].split("}")[0]

    def test_both_calendar_designs_are_one_variant_group(self):
        # The ported designs are one entry in the tray with the complete dashboard
        # calendar: one variantGroup on every design is what makes the arrows appear.
        self.assertIn('variantGroup: "calendar"', self.catalog_definition("fullCalendarWidget"))
        ported = self.catalog_definition("calendarMinimalWidget")
        self.assertIn('variantGroup: "calendar"', ported)
        self.assertIn('"island"', ported, "the ported design is offered to the island")

    def test_ported_designs_are_freeform(self):
        for type_name in ["calendarMinimalWidget", "calendarUpcomingWidget", "calendarMonthAgendaWidget"]:
            ported = self.catalog_definition(type_name)
            self.assertIn('variantGroup: "calendar"', ported)
            self.assertIn('"island"', ported)
            self.assertIn("maxHeight: 8", ported)
            self.assertNotIn("allowedSizes", ported, "the tile re-lays out for any footprint")

    def test_month_grid_is_horizontal_only(self):
        ported = self.catalog_definition("calendarMonthGridWidget")
        self.assertIn('variantGroup: "calendar"', ported)
        self.assertIn('"island"', ported)
        self.assertNotIn("maxHeight", ported, "the month grid has a closed size list")
        sizes = re.findall(r"\[(\d+), ?(\d+)\]", ported)
        self.assertGreaterEqual(len(sizes), 4, "the design is offered at several widths")
        for width, height in sizes:
            self.assertGreater(int(width), int(height),
                f"{width}x{height} is not a horizontal footprint")

    def test_month_grid_lays_itself_out_from_the_calendar(self):
        self.assertTrue(GRID_TILE_PATH.exists())
        tile_text = GRID_TILE_PATH.read_text(encoding="utf-8")
        self.assertIn("AndroidWidgetTileBase {", tile_text)
        # The grid follows the real month: first weekday, days in month, today.
        self.assertIn("DateTime.clock.date", tile_text)
        self.assertIn("firstDayOfWeek", tile_text)
        self.assertIn("daysInMonth", tile_text)
        self.assertIn("todayCircleColor: Appearance.colors.colPrimary", tile_text)
        # Both sections are sized from the surface, never from a stored footprint.
        self.assertIn("root.contentWidth", tile_text)
        self.assertIn("root.contentHeight", tile_text)
        self.assertNotIn("effectiveSizeW", tile_text)
        self.assertNotIn("effectiveSizeH", tile_text)
        # Qt5Compat graphics can pin the island's window, and the background's colour
        # scheme is not this theme.
        self.assertNotIn("Qt5Compat", tile_text)
        self.assertNotIn("WidgetColorScheme", tile_text)

    def test_the_event_rows_are_one_shared_piece(self):
        self.assertTrue(ROWS_PATH.exists())
        rows_text = ROWS_PATH.read_text(encoding="utf-8")
        # It draws what it is given: the caller owns the days and the service owns their
        # order, so the list itself has no idea what a tile or a calendar service is.
        self.assertNotIn("CalendarService.", rows_text, "it must not reach for the service itself")
        self.assertNotIn("root.surface", rows_text, "its box comes from whoever places it")
        self.assertNotIn("AndroidWidgetTileBase", rows_text)
        # The widget's content and its empty state.
        self.assertIn('Translation.tr("All Day")', rows_text)
        self.assertIn('Translation.tr("No Events")', rows_text)
        self.assertIn("Config.options?.time?.format", rows_text, "the hours read as the shell reads them")
        # The round (+) is the widget's, but it opens the timetable through the shell
        # instead of spawning the `qs ipc` process the desktop widget runs.
        self.assertIn('GlobalStates.openCheatsheet("timetable")', rows_text)
        self.assertNotIn("Quickshell.Io", rows_text)
        self.assertNotIn("Process {", rows_text)
        self.assertIn("enabled: !root.editMode", rows_text)
        self.assertNotIn("Qt5Compat", rows_text)
        self.assertNotIn("WidgetColorScheme", rows_text)

        # Both tiles that show events draw them through it, not through their own copy.
        for path in [UPCOMING_TILE_PATH, MONTH_CARD_PATH]:
            self.assertTrue(path.exists())
            tile_text = path.read_text(encoding="utf-8")
            self.assertIn("CalendarEventRows {", tile_text)

    def test_upcoming_tile_is_the_widget_plus_a_one_line_footprint(self):
        tile_text = UPCOMING_TILE_PATH.read_text(encoding="utf-8")
        self.assertIn("AndroidWidgetTileBase {", tile_text)
        # Three days out of the service's own index, and the widget's round (+) on today.
        self.assertIn("CalendarService.eventsForDay(", tile_text)
        self.assertIn("withCreateButton: true", tile_text)
        # The one line, for the footprints with no room for a row.
        self.assertIn("oneLine", tile_text)
        # Rows are laid out from the surface, never from a stored footprint.
        self.assertIn("root.contentWidth", tile_text)
        self.assertIn("root.contentHeight", tile_text)
        self.assertNotIn("effectiveSizeW", tile_text)
        self.assertNotIn("effectiveSizeH", tile_text)
        self.assertNotIn("Qt5Compat", tile_text)
        self.assertNotIn("WidgetColorScheme", tile_text)

    def test_the_month_card_bottoms_out_at_two_cells(self):
        ported = self.catalog_definition("calendarMonthAgendaWidget")
        # A 1x1 leaves the days 12 x 7 px, so the floor is two cells each way and the
        # design only has to work from there up.
        self.assertIn("defaultSize: [2, 2]", ported)
        self.assertIn("minWidth: 2", ported)
        self.assertIn("minHeight: 2", ported)

    def test_neither_list_builds_rows_it_does_not_draw(self):
        # `visible` does not stop a Repeater from materialising its delegates: a hidden
        # list would still build a button, a card and three texts per row. Both lists say
        # whether they are drawn, and the row model is a count so a resize re-places the
        # rows instead of rebuilding them.
        rows_text = ROWS_PATH.read_text(encoding="utf-8")
        self.assertIn("property bool show: true", rows_text)
        self.assertIn("model: root.show ? root.shownRows.length : 0", rows_text)
        self.assertIn("active: rowItem.row.isToday && root.showCreateButton", rows_text,
            "the (+) is loaded, not hidden: a control per row is the heaviest thing here")

        upcoming_text = UPCOMING_TILE_PATH.read_text(encoding="utf-8")
        self.assertIn("show: !root.oneLine", upcoming_text)
        card_text = MONTH_CARD_PATH.read_text(encoding="utf-8")
        self.assertIn("active: root.showAgenda", card_text,
            "a tile that is only a month never builds the agenda")

    def test_month_card_is_a_month_grid_that_grows_an_agenda(self):
        self.assertTrue(MONTH_CARD_PATH.exists())
        tile_text = MONTH_CARD_PATH.read_text(encoding="utf-8")
        self.assertIn("AndroidWidgetTileBase {", tile_text)
        # The grid follows the real month, and marks today.
        self.assertIn("DateTime.clock.date", tile_text)
        self.assertIn("firstDayOfWeek", tile_text)
        self.assertIn("daysInMonth", tile_text)
        self.assertIn("todayCircleColor: Appearance.colors.colPrimary", tile_text)
        # It is built for 1x1: the month name and the weekday letters cost height the days
        # need there, and the agenda only exists once the tile is tall enough for one.
        self.assertIn("showChrome", tile_text)
        self.assertIn("showAgenda", tile_text)
        self.assertIn("withAgenda", tile_text)
        self.assertIn("CalendarEventRows {", tile_text)
        self.assertIn("days: root.agendaDays", tile_text)
        # Rows and cells are laid out from the surface, never from a stored footprint.
        self.assertIn("root.surface.width", tile_text)
        self.assertIn("root.surface.height", tile_text)
        self.assertNotIn("effectiveSizeW", tile_text)
        self.assertNotIn("effectiveSizeH", tile_text)
        self.assertNotIn("Qt5Compat", tile_text)
        self.assertNotIn("WidgetColorScheme", tile_text)

    def test_tray_preview_metadata(self):
        tray_text = TRAY_PREVIEW_PATH.read_text(encoding="utf-8")
        for type_name in ["calendarMinimalWidget", "calendarMonthGridWidget", "calendarUpcomingWidget",
                          "calendarMonthAgendaWidget"]:
            self.assertIn(f"{type_name}: {{", tray_text, f"{type_name} missing in tray preview meta")

    def test_chooser_contains_the_delegates(self):
        chooser_text = CHOOSER_PATH.read_text(encoding="utf-8")
        self.assertIn("qs.modules.common.quickToggles.androidStyle.calendar", chooser_text)
        for role, component in [("calendarMinimalWidget", "AndroidCalendarMinimalToggle"),
                                ("calendarMonthGridWidget", "AndroidCalendarMonthGridToggle"),
                                ("calendarUpcomingWidget", "AndroidCalendarUpcomingToggle"),
                                ("calendarMonthAgendaWidget", "AndroidCalendarMonthAgendaToggle")]:
            self.assertIn(f'roleValue: "{role}"', chooser_text)
            self.assertIn(f"{component} {{", chooser_text)

    def test_tile_adapts_to_the_surface_it_is_given(self):
        self.assertTrue(TILE_PATH.exists())
        tile_text = TILE_PATH.read_text(encoding="utf-8")
        self.assertIn("AndroidWidgetTileBase {", tile_text)
        # Nothing in the file may take its size from a stored footprint, and every text
        # has to shrink rather than run past its margin.
        self.assertIn("root.surface.width", tile_text)
        self.assertIn("root.surface.height", tile_text)
        labels = tile_text.split("component DateLabel:")[1].split("component HeroDay:")[0]
        hero = tile_text.split("component HeroDay:")[1].split("// ── Stage 1")[0]
        self.assertIn("fontSizeMode: Text.Fit", labels, "the names shrink instead of spilling")
        self.assertIn("fontSizeMode: Text.Fit", hero, "the day shrinks instead of spilling")
        self.assertNotIn("effectiveSizeW", tile_text)
        self.assertNotIn("effectiveSizeH", tile_text)
        # The desktop widget's own theme and effects stay behind: Qt5Compat graphics can
        # pin the island's window, and the background's colour scheme is not this theme.
        self.assertNotIn("Qt5Compat", tile_text)
        self.assertNotIn("WidgetColorScheme", tile_text)


if __name__ == "__main__":
    unittest.main()
