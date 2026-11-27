pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * Slim AtAGlanceService stand-in for standalone apps: derives today's events
 * and next upcoming event directly from CalendarService + DateTime.
 */
Singleton {
    id: root

    readonly property var todayEvents: {
        const now = DateTime.clock.date;
        const key = CalendarService.dayKey(now);
        const list = CalendarService.eventsByDay?.[key] ?? [];
        return Array.isArray(list) ? list : [];
    }

    readonly property var nextEvent: {
        const nowMs = DateTime.clock.date.getTime();
        let best = null;
        let bestStart = Infinity;
        for (const ev of root.todayEvents) {
            if (!ev || ev.allDay)
                continue;
            const startMs = ev.startDate instanceof Date ? ev.startDate.getTime() : NaN;
            const endMs = ev.endDate instanceof Date ? ev.endDate.getTime() : startMs;
            if (isNaN(startMs))
                continue;
            if (endMs >= nowMs && startMs < bestStart) {
                best = ev;
                bestStart = startMs;
            }
        }
        return best;
    }
}
