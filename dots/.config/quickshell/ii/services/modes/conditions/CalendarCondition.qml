import QtQuick
import qs.services
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * A calendar event (khal) is going on right now; `match` narrows it to
 * events whose title or calendar contains the text.
 */
ModeCondition {
    id: root
    readonly property string match: String(root.params?.match ?? "").toLowerCase()
    readonly property var now: DateTime.clock.date

    readonly property var current: {
        const t = root.now.getTime();
        return ModeSchema.toArray(CalendarService.events).filter(e => {
            const start = new Date(e.startDate).getTime();
            const end = new Date(e.endDate).getTime();
            if (!(start <= t && t < end))
                return false;
            if (!root.match.length)
                return true;
            return `${e.content ?? ""} ${e.calendar ?? ""}`.toLowerCase().indexOf(root.match) !== -1;
        });
    }

    satisfied: CalendarService.khalAvailable && root.current.length > 0
    reason: root.current[0]?.content ?? (CalendarService.khalAvailable ? "" : "khal not installed")
}
