import QtQuick
import QtTest
import "../../modules/common/quickToggles/androidStyle/QuickToggleCatalog.js" as Catalog

TestCase {
    name: "QuickToggleCatalog"

    function test_catalog_contains_current_types() {
        var types = Catalog.allTypes();
        compare(types.length, Object.keys(Catalog.TOGGLE_TYPES).length);
        verify(Catalog.hasType("network"));
        verify(Catalog.hasType("volumeSlider"));
        verify(Catalog.hasType("mediaWidget"));
        verify(Catalog.hasType("calendarWidget"));
        verify(Catalog.hasType("tasksWidget"));
        verify(Catalog.hasType("timerWidget"));
        verify(Catalog.hasType("countdownWidget"));
        verify(Catalog.hasType("pomodoroWidget"));
        verify(Catalog.hasType("laptopKeyboard"));
        verify(!Catalog.hasType("doesNotExist"));
    }

    function test_defaults_are_centralized() {
        compare(Catalog.defaultSize("network"), [1, 1]);
        compare(Catalog.defaultSize("volumeSlider"), [4, 1]);
        compare(Catalog.defaultSize("mediaWidget"), [2, 2]);
        compare(Catalog.kind("unknown"), "unknown");
    }

    function test_calendar_designs_share_one_variant_group() {
        // One entry in the tray, five designs behind its arrows: the complete dashboard
        // calendar, the ported desktop date, the ported month grid, the ported list of the
        // next three days, and the month card that grows into one.
        const designs = ["fullCalendarWidget", "calendarMinimalWidget", "calendarMonthGridWidget",
            "calendarUpcomingWidget", "calendarMonthAgendaWidget"];
        for (let index = 0; index < designs.length; index++) {
            compare(Catalog.variantGroup(designs[index]), "calendar", designs[index] + " is in the group");
            verify(Catalog.availableForFamily(designs[index], "island"), designs[index] + " is on the island");
        }
        compare(JSON.stringify(Catalog.variantsOf("calendar")), JSON.stringify(designs));

        // The month card is free-form from 2x2 up: a 1x1 leaves its days 12 x 7 px, which
        // is not a month anyone reads, so the floor is two cells each way.
        compare(Catalog.defaultSize("calendarMonthAgendaWidget"), [2, 2]);
        verify(!Catalog.isSizeAllowed("calendarMonthAgendaWidget", 1, 1, 6));
        verify(!Catalog.isSizeAllowed("calendarMonthAgendaWidget", 1, 2, 6));
        verify(!Catalog.isSizeAllowed("calendarMonthAgendaWidget", 2, 1, 6));
        verify(Catalog.isSizeAllowed("calendarMonthAgendaWidget", 2, 2, 6));
        compare(Catalog.normalizeSize("calendarMonthAgendaWidget", 1, 1, 6), [2, 2]);
        compare(Catalog.normalizeSize("calendarMonthAgendaWidget", 2, 4, 6), [2, 4]);
        compare(Catalog.normalizeSize("calendarMonthAgendaWidget", 6, 9, 6), [6, 8]);

        // The ported date and the ported event list are free-form, so every proportion the
        // user drags to gets a real footprint instead of collapsing onto a smaller one.
        compare(Catalog.normalizeSize("calendarMinimalWidget", 1, 1, 6), [1, 1]);
        compare(Catalog.normalizeSize("calendarMinimalWidget", 1, 2, 6), [1, 2]);
        compare(Catalog.normalizeSize("calendarMinimalWidget", 4, 2, 6), [4, 2]);
        compare(Catalog.normalizeSize("calendarMinimalWidget", 4, 4, 6), [4, 4]);
        compare(Catalog.normalizeSize("calendarMinimalWidget", 4, 9, 6), [4, 8]);
        compare(Catalog.normalizeSize("calendarUpcomingWidget", 1, 1, 6), [1, 1]);
        compare(Catalog.normalizeSize("calendarUpcomingWidget", 6, 2, 6), [6, 2]);
        compare(Catalog.normalizeSize("calendarUpcomingWidget", 1, 8, 6), [1, 8]);
        compare(Catalog.normalizeSize("calendarUpcomingWidget", 6, 9, 6), [6, 8]);

        // The ported month grid has a closed list of horizontal footprints: a 2x2 is a
        // different design, so it snaps to the narrowest horizontal size instead.
        verify(Catalog.isSizeAllowed("calendarMonthGridWidget", 4, 3, 6));
        verify(Catalog.isSizeAllowed("calendarMonthGridWidget", 6, 2, 6));
        verify(Catalog.isSizeAllowed("calendarMonthGridWidget", 5, 4, 6));
        compare(Catalog.normalizeSize("calendarMonthGridWidget", 2, 2, 6), [3, 2]);
        compare(Catalog.normalizeSize("calendarMonthGridWidget", 1, 1, 6), [3, 2]);
        compare(Catalog.normalizeSize("calendarMonthGridWidget", 4, 3, 6), [4, 3]);
        // A grid too narrow for any of them falls back to the catalog's packable size;
        // the edit controller refuses to shrink a grid below what its tiles need, so the
        // tile is never placed at it.
        compare(Catalog.normalizeSize("calendarMonthGridWidget", 4, 3, 2), [2, 1]);
    }

    function test_slider_vertical_and_horizontal_sizes() {
        compare(Catalog.normalizeSize("volumeSlider", 1, 2, 4), [1, 2]);
        compare(Catalog.normalizeSize("volumeSlider", 1, 3, 4), [1, 3]);
        compare(Catalog.normalizeSize("volumeSlider", 4, 1, 4), [4, 1]);
        compare(Catalog.normalizeSize("volumeSlider", 4, 2, 4), [4, 2]);
        compare(Catalog.normalizeSize("volumeSlider", 4, 3, 4), [4, 3]);
        verify(Catalog.isSizeAllowed("volumeSlider", 1, 2, 4));
        verify(Catalog.isSizeAllowed("volumeSlider", 4, 1, 4));
        verify(Catalog.isSizeAllowed("volumeSlider", 4, 2, 4));
        verify(Catalog.isSizeAllowed("volumeSlider", 4, 3, 4));
    }

    function test_media_allowed_sizes_and_column_clamp() {
        compare(Catalog.normalizeSize("mediaWidget", 4, 1, 4), [4, 2]);
        compare(Catalog.normalizeSize("mediaWidget", 2, 1, 4), [2, 1]);
        // A three-column grid has its own wide footprint rather than collapsing
        // to the two-column square.
        compare(Catalog.normalizeSize("mediaWidget", 4, 2, 3), [3, 2]);
        compare(Catalog.normalizeSize("mediaWidget", 2, 2, 1), [1, 1]);
        compare(Catalog.normalizeSize("mediaWidget", 2, 8, 4), [2, 8]);
        compare(Catalog.normalizeSize("mediaWidget", 2, 9, 4), [2, 8]);
        verify(Catalog.isSizeAllowed("mediaWidget", 4, 2, 4));
        verify(Catalog.isSizeAllowed("mediaWidget", 2, 4, 4));
        verify(Catalog.isSizeAllowed("mediaWidget", 2, 8, 4));
        verify(Catalog.isSizeAllowed("mediaWidget", 4, 4, 4));
        verify(Catalog.isSizeAllowed("mediaWidget", 2, 6, 6));
        verify(Catalog.isSizeAllowed("mediaWidget", 6, 3, 6));
        verify(!Catalog.isSizeAllowed("mediaWidget", 2, 3, 4));
        verify(!Catalog.isSizeAllowed("mediaWidget", 4, 1, 4));
    }

    function test_dashboard_widgets_have_a_fixed_tablet_square_footprint() {
        var types = ["calendarWidget", "tasksWidget", "timerWidget", "countdownWidget", "pomodoroWidget"];
        for (var index = 0; index < types.length; index++) {
            var type = types[index];
            compare(Catalog.defaultSize(type), [1, 2]);
            compare(Catalog.normalizeSize(type, 4, 7, 4), [1, 2]);
            verify(Catalog.isSizeAllowed(type, 1, 2, 4));
            verify(!Catalog.isSizeAllowed(type, 2, 2, 4));
            verify(!Catalog.isResizable(type, 4));
            verify(Catalog.availableForFamily(type, "tablet"));
            verify(!Catalog.availableForFamily(type, "ii"));
        }
        verify(Catalog.availableForFamily("network", "ii"));
        verify(Catalog.isResizable("network", 4));
    }

    function test_island_widgets_are_offered_to_the_sidebar() {
        // The sidebar's dashboard is the island's grid with pages: the same tiles, the
        // same drawer and the same persistence. Every design the island offers is
        // therefore on the sidebar's list too - the sidebar is the "ii" host - so the
        // only tile the two hosts do not share is the island's own toolbar.
        const designs = [
            "mediaWidget", "mediaCircleWidget", "expressiveMediaWidget", "cdMediaWidget",
            "compactMediaWidget", "nothingRingMediaWidget",
            "bluetoothBatteryWidget", "mobileBatteryWidget", "bluetoothHeadphoneCookieWidget",
            "pcBatteryBarsWidget", "pcBatteryCableWidget", "devicesBatteryListWidget",
            "bluetoothEarbudsStemWidget", "laptopBatteryWidget",
            "systemResourcesWidget", "cpuResourceWidget", "ramResourceWidget",
            "diskResourceWidget", "gpuResourceWidget",
            "sportsWidget", "sportsCard", "photoWidget", "trayWidget", "notificationListWidget",
            "fullCalendarWidget", "calendarMinimalWidget", "calendarMonthGridWidget",
            "calendarUpcomingWidget", "calendarMonthAgendaWidget",
            "fullTasksWidget", "fullTimerWidget", "fullCountdownWidget", "fullPomodoroWidget",
            "fullNotesWidget",
            "clockWidget", "iosClockWidget", "digitalClockWidget",
            "weatherIconShape", "weatherCard", "weatherWidget", "weatherCircle",
            "weatherTypography", "weatherForecast"
        ];
        for (let index = 0; index < designs.length; index++) {
            verify(Catalog.availableForFamily(designs[index], "island"), designs[index] + " is on the island");
            verify(Catalog.availableForFamily(designs[index], "ii"), designs[index] + " is in the sidebar tray");
        }

        // The island's frame stays the island's: its toolbar is the only way into that
        // grid's edit mode, and the sidebar edits from its header.
        verify(Catalog.availableForFamily("dashboardToolbar", "island"));
        verify(!Catalog.availableForFamily("dashboardToolbar", "ii"));
    }

    function test_normalize_pages_migrates_legacy_shape() {
        var warnings = [];
        var raw = [{ type: "network", size: 2 }, { type: "mediaWidget", size: 4, sizeH: 1 }];
        var pages = Catalog.normalizePages(raw, 4, { warn: function(message) { warnings.push(message); } });
        compare(pages.length, 1);
        compare(pages[0].length, 2);
        compare(JSON.stringify(pages[0][0]), JSON.stringify({ id: "network", type: "network", sizeW: 2, sizeH: 1 }));
        compare(JSON.stringify(pages[0][1]), JSON.stringify({ id: "mediaWidget", type: "mediaWidget", sizeW: 4, sizeH: 2 }));
        compare(warnings.length, 0);
    }

    function test_normalize_pages_removes_duplicate_ids_deterministically() {
        var warnings = [];
        var pages = Catalog.normalizePages([
            [{ id: "same", type: "network" }],
            [{ id: "same", type: "bluetooth" }, { type: "vpn" }]
        ], 4, { warn: function(message) { warnings.push(message); } });
        compare(pages.length, 2);
        compare(pages[0].length, 1);
        compare(pages[1].length, 1);
        compare(pages[1][0].id, "vpn");
        compare(warnings.length, 1);
    }

    function test_square_toggle_size_allowed_and_normalized() {
        compare(Catalog.normalizeSize("bluetooth", 0, 1, 4), [0, 1]);
        verify(Catalog.isSizeAllowed("bluetooth", 0, 1, 4));

        // Height > 1 cannot have width 0
        compare(Catalog.normalizeSize("bluetooth", 0, 2, 4), [1, 2]);
        verify(!Catalog.isSizeAllowed("bluetooth", 0, 2, 4));

        // Sliders cannot be square
        compare(Catalog.normalizeSize("volumeSlider", 0, 1, 4), [1, 1]);
        verify(!Catalog.isSizeAllowed("volumeSlider", 0, 1, 4));

        // Normalize pages preserves sizeW: 0
        var pages = Catalog.normalizePages([[{ id: "sq", type: "bluetooth", sizeW: 0, sizeH: 1 }]], 4);
        compare(pages[0][0].sizeW, 0);
        compare(pages[0][0].sizeH, 1);
    }
}
