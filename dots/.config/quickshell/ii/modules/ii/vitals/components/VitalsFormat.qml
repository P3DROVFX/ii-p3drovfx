pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * How ii Vitals says when something happened: "as of" labels on tiles and sheets, and
 * "synced N min ago". Dates are the store's local "yyyy-MM-dd" days; times are epoch ms.
 */
Singleton {
    id: root

    function dateOf(ms: real): string {
        return Qt.formatDate(new Date(ms), "yyyy-MM-dd");
    }

    /// Whole days from `from` to `to` ("yyyy-MM-dd"); NaN if either is not a date.
    function daysBetween(from: string, to: string): real {
        const a = Date.UTC(Number(from.slice(0, 4)), Number(from.slice(5, 7)) - 1, Number(from.slice(8, 10)));
        const b = Date.UTC(Number(to.slice(0, 4)), Number(to.slice(5, 7)) - 1, Number(to.slice(8, 10)));
        return Math.round((b - a) / 86400000);
    }

    function addDays(date: string, n: int): string {
        const d = new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)) + n);
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function clock(ms: real): string {
        return Qt.formatTime(new Date(ms), "HH:mm");
    }

    /// "Today", "Yesterday", "Tue" within the week, else "13 Jul" ("13 Jul 2025" in another year).
    function dayLabel(date: string, now: real): string {
        const today = root.dateOf(now);
        const age = root.daysBetween(date, today);
        if (age === 0)
            return Translation.tr("Today");
        if (age === 1)
            return Translation.tr("Yesterday");
        const d = new Date(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)));
        if (age > 1 && age < 7)
            return Qt.locale().toString(d, "dddd");
        return Qt.locale().toString(d, date.slice(0, 4) === today.slice(0, 4) ? "d MMM" : "d MMM yyyy");
    }

    /**
     * When a value is from: its time today ("13:05"), the day and time this week
     * ("Yesterday 18:51"), else the date. A value without a time (totals, scores) gives
     * its day.
     */
    function asOf(time, date, now: real): string {
        const day = date ?? (time ? root.dateOf(time) : "");
        if (day === "")
            return "";
        const age = root.daysBetween(day, root.dateOf(now));
        if (!time || age >= 7)
            return root.dayLabel(day, now);
        if (age === 0)
            return root.clock(time);
        return Translation.tr("%1 %2").arg(root.dayLabel(day, now)).arg(root.clock(time));
    }

    /// "just now", "4 min ago", "2 h ago", "3 days ago".
    function ago(ms: real, now: real): string {
        const min = Math.max(0, Math.floor((now - ms) / 60000));
        if (min < 1)
            return Translation.tr("just now");
        if (min < 60)
            return Translation.tr("%1 min ago").arg(min);
        if (min < 48 * 60)
            return Translation.tr("%1 h ago").arg(Math.floor(min / 60));
        return Translation.tr("%1 days ago").arg(Math.floor(min / 1440));
    }
}
