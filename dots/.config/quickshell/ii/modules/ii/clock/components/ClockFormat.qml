pragma Singleton

import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions

/** Every string the clock app derives from a time, a duration or a set of days. */
Singleton {
    id: root

    readonly property bool use12Hour: DateUtils.is12HourTimeFormat(Config.options?.time?.format ?? "hh:mm")

    function pad(value): string {
        return String(Math.floor(Math.abs(value))).padStart(2, "0");
    }

    /** "HH:mm" → { hours, minutes, meridiem } in the user's clock format. */
    function alarmParts(time): var {
        const parts = String(time ?? "00:00").split(":");
        const hours = parseInt(parts[0]) || 0;
        const minutes = root.pad(parseInt(parts[1]) || 0);
        if (!root.use12Hour)
            return { hours: root.pad(hours), minutes: minutes, meridiem: "" };
        return {
            hours: root.pad(hours % 12 || 12),
            minutes: minutes,
            meridiem: hours >= 12 ? Qt.locale().pmText : Qt.locale().amText
        };
    }

    function alarmTime(time): string {
        const parts = root.alarmParts(time);
        return `${parts.hours}:${parts.minutes}${parts.meridiem.length > 0 ? " " + parts.meridiem : ""}`;
    }

    function dateTime(date): string {
        return Qt.locale().toString(date, Config.options?.time?.format ?? "hh:mm");
    }

    /** "Every day", "Weekdays", "Mon, Wed" or, for a one-off alarm, the day it rings. */
    function repeatSummary(alarm, now): string {
        const days = alarm?.days ?? [];
        const dated = String(alarm?.date ?? "");
        if (dated.length > 0) {
            return root.relativeDay(root.parseDay(dated), now);
        }
        const count = days.filter(Boolean).length;
        if (count === 0) {
            const next = AlarmService.nextOccurrence(Object.assign({}, alarm, { enabled: true }), now);
            return next ? root.relativeDay(next, now) : Translation.tr("Once");
        }
        if (count === 7)
            return Translation.tr("Every day");
        if (count === 5 && days[1] && days[2] && days[3] && days[4] && days[5])
            return Translation.tr("Weekdays");
        if (count === 2 && days[0] && days[6])
            return Translation.tr("Weekends");
        const first = ((Config.options?.time?.firstDayOfWeek ?? 6) + 1) % 7;
        const names = [];
        for (let i = 0; i < 7; i++) {
            const day = (first + i) % 7;
            if (days[day])
                names.push(Qt.locale().dayName(day, Locale.ShortFormat));
        }
        return names.join(", ");
    }

    /** "yyyy-MM-dd" → local midnight of that day. */
    function parseDay(text): var {
        const parts = String(text ?? "").split("-").map(Number);
        return parts.length === 3 ? new Date(parts[0], parts[1] - 1, parts[2]) : new Date();
    }

    /** "Today", "Tomorrow" or "Fri, 26 Sep". */
    function relativeDay(date, now): string {
        const base = now ?? new Date();
        const today = new Date(base.getFullYear(), base.getMonth(), base.getDate());
        const day = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        const diff = Math.round((day.getTime() - today.getTime()) / 86400000);
        if (diff === 0)
            return Translation.tr("Today");
        if (diff === 1)
            return Translation.tr("Tomorrow");
        return Qt.locale().toString(date, "ddd, d MMM");
    }

    /** Seconds → "1:05:09" or "05:09". */
    function duration(seconds): string {
        const safe = Math.max(0, Math.floor(Number(seconds) || 0));
        const hours = Math.floor(safe / 3600);
        const minutes = Math.floor((safe % 3600) / 60);
        const secs = safe % 60;
        return hours > 0 ? `${hours}:${root.pad(minutes)}:${root.pad(secs)}` : `${root.pad(minutes)}:${root.pad(secs)}`;
    }

    /** Seconds → "1h 30m", "5m", "45s". */
    function shortDuration(seconds): string {
        const safe = Math.max(0, Math.round(Number(seconds) || 0));
        const hours = Math.floor(safe / 3600);
        const minutes = Math.floor((safe % 3600) / 60);
        const secs = safe % 60;
        const parts = [];
        if (hours > 0)
            parts.push(hours + Translation.tr("h"));
        if (minutes > 0)
            parts.push(minutes + Translation.tr("m"));
        if (secs > 0 || parts.length === 0)
            parts.push(secs + Translation.tr("s"));
        return parts.join(" ");
    }

    /** Stopwatch centiseconds → { main: "01:05", fraction: "42" }, hours folded in when needed. */
    function stopwatch(centiseconds): var {
        const safe = Math.max(0, Math.floor(Number(centiseconds) || 0));
        const totalSeconds = Math.floor(safe / 100);
        const hours = Math.floor(totalSeconds / 3600);
        const minutes = Math.floor((totalSeconds % 3600) / 60);
        const secs = totalSeconds % 60;
        const main = hours > 0 ? `${hours}:${root.pad(minutes)}:${root.pad(secs)}` : `${root.pad(minutes)}:${root.pad(secs)}`;
        return { main: main, fraction: root.pad(safe % 100) };
    }
}
