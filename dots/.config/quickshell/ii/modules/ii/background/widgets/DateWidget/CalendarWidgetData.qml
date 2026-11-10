import QtQuick
import qs.services
import qs.modules.common

/*
 * Date arithmetic shared by the Date Stack, Date Banner, Week Strip, Week
 * Agenda and Month Tall widgets: today, the user's week start
 * (Config.time.firstDayOfWeek, 0 = Monday … 6 = Sunday), the current week and
 * month as Date lists, and the khal events of a day from CalendarService.
 */
QtObject {
    id: root

    readonly property date today: DateTime.clock.date
    readonly property var locale: Qt.locale()
    // JS getDay() index of the first day of the week.
    readonly property int firstDay: ((Config.options?.time?.firstDayOfWeek ?? 6) + 1) % 7

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function isToday(date) {
        return root.sameDay(date, root.today);
    }

    function isWeekend(date) {
        const d = date.getDay();
        return d === 0 || d === 6;
    }

    function startOfWeek(date) {
        const start = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        start.setDate(start.getDate() - ((start.getDay() - root.firstDay + 7) % 7));
        return start;
    }

    // The seven days of the week holding `date`, in the user's order.
    function weekOf(date) {
        const start = root.startOfWeek(date);
        const days = [];
        for (let i = 0; i < 7; i++)
            days.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        return days;
    }

    readonly property var currentWeek: root.weekOf(root.today)

    // Whole weeks covering the month of `date`: 4 to 6 rows of seven.
    function monthCells(date) {
        const first = new Date(date.getFullYear(), date.getMonth(), 1);
        const last = new Date(date.getFullYear(), date.getMonth() + 1, 0);
        const start = root.startOfWeek(first);
        const cells = [];
        const cursor = new Date(start);
        while (cursor <= last || cells.length % 7 !== 0) {
            cells.push(new Date(cursor));
            cursor.setDate(cursor.getDate() + 1);
        }
        return cells;
    }

    readonly property var currentMonthCells: root.monthCells(root.today)

    // Narrow weekday names (M T W …) in the user's week order.
    readonly property var narrowDayNames: root.currentWeek.map(d => root.locale.dayName(d.getDay(), Locale.NarrowFormat))

    // ISO-8601 week number.
    function weekNumber(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const day = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
    }

    function dayOfYear(date) {
        const start = new Date(date.getFullYear(), 0, 1);
        return Math.round((new Date(date.getFullYear(), date.getMonth(), date.getDate()) - start) / 86400000) + 1;
    }

    function daysInYear(date) {
        const y = date.getFullYear();
        return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0 ? 366 : 365;
    }

    function eventsFor(date) {
        if (!CalendarService.khalAvailable)
            return [];
        return CalendarService.eventsForDay(date) ?? [];
    }

    function eventTime(event) {
        if (CalendarService.isAllDayEvent(event))
            return Translation.tr("All day");
        return Qt.locale().toString(event.startDate, Config.options?.time?.format ?? "hh:mm");
    }

    // The next event from now on, today or later this week; null when none.
    readonly property var nextEvent: {
        const now = DateTime.clock.date;
        for (let i = 0; i < 7; i++) {
            const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
            const events = root.eventsFor(day);
            for (const event of events) {
                if (event.endDate >= now)
                    return event;
            }
        }
        return null;
    }
}
