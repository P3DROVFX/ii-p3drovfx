import QtQuick
import QtTest
import "../../modules/ii/dock/utilities/CalendarAgenda.js" as Agenda

TestCase {
    name: "CalendarAgenda"

    readonly property date now: new Date(2026, 9, 5, 10, 0)

    function ev(title, start, end, allDay) {
        return { content: title, startDate: start, endDate: end, allDay: allDay === true };
    }

    function test_upcomingSkipsPastAndAllDay() {
        const list = [
            ev("past", new Date(2026, 9, 5, 8), new Date(2026, 9, 5, 9)),
            ev("now", new Date(2026, 9, 5, 9, 30), new Date(2026, 9, 5, 10, 30)),
            ev("later", new Date(2026, 9, 5, 14), new Date(2026, 9, 5, 15)),
            ev("holiday", new Date(2026, 9, 5), new Date(2026, 9, 6), true),
            ev("far", new Date(2026, 9, 20, 9), new Date(2026, 9, 20, 10))
        ];
        const out = Agenda.upcoming(list, now, 5, 7).map(i => i.event.content);
        compare(out, ["now", "later"]);
        compare(Agenda.upcoming(list, now, 1, 7).length, 1);
    }

    function test_dayEventsAllDayFirst() {
        const list = [
            ev("b", new Date(2026, 9, 5, 14), new Date(2026, 9, 5, 15)),
            ev("a", new Date(2026, 9, 5), new Date(2026, 9, 6), true),
            ev("tomorrow", new Date(2026, 9, 6, 9), new Date(2026, 9, 6, 10))
        ];
        compare(Agenda.dayEvents(list, now).map(i => i.event.content), ["a", "b"]);
    }

    function test_relative() {
        const soon = { start: new Date(2026, 9, 5, 10, 25), end: new Date(2026, 9, 5, 11) };
        compare(Agenda.relative(soon, now), "In 25 min");
        const happening = { start: new Date(2026, 9, 5, 9), end: new Date(2026, 9, 5, 11) };
        compare(Agenda.relative(happening, now), "Now");
        const tomorrow = { start: new Date(2026, 9, 6, 9), end: new Date(2026, 9, 6, 10) };
        compare(Agenda.relative(tomorrow, now), "Tomorrow");
    }

    function test_nextDaysOnlyDaysWithEvents() {
        const list = [ev("x", new Date(2026, 9, 7, 9), new Date(2026, 9, 7, 10))];
        const days = Agenda.nextDays(list, now, 3);
        compare(days.length, 1);
        compare(days[0].day.getDate(), 7);
    }

    function test_badDatesIgnored() {
        compare(Agenda.upcoming([{ content: "x", startDate: "nope" }, null], now, 3, 7).length, 0);
    }
}
