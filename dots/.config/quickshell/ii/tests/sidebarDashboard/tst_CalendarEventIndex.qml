import QtQuick
import QtTest
import "../../modules/ii/sidebarDashboard/calendar/CalendarEventIndex.js" as CalendarEventIndex

TestCase {
    name: "CalendarEventIndex"

    function test_groups_events_once_by_local_day() {
        const first = { id: 1, startDate: new Date(2026, 7, 27, 8, 30) };
        const second = { id: 2, startDate: new Date(2026, 7, 27, 18, 0) };
        const third = { id: 3, startDate: new Date(2026, 7, 28, 9, 0) };
        const grouped = CalendarEventIndex.groupEvents([first, second, third], true);

        compare(CalendarEventIndex.tasksForDate(grouped, 2026, 7, 27).length, 2);
        compare(CalendarEventIndex.tasksForDate(grouped, 2026, 7, 28).length, 1);
        compare(CalendarEventIndex.tasksForDate(grouped, 2026, 7, 29).length, 0);
    }

    function test_ignores_invalid_dates_and_disabled_service() {
        const invalid = { id: 1, startDate: "not-a-date" };
        compare(Object.keys(CalendarEventIndex.groupEvents([invalid], true)).length, 0);
        compare(Object.keys(CalendarEventIndex.groupEvents([
            { id: 2, startDate: new Date(2026, 7, 27) }
        ], false)).length, 0);
    }
}
