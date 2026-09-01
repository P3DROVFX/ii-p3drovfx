pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services

// Calendar alarms deliberately live outside AlarmService: calendar events have
// per-occurrence timing and can arrive from read-only synced calendars.
Singleton {
    id: root

    readonly property bool configured: Config.ready && Persistent.ready
    readonly property var options: Config.options.calendar.timetable.notifications
    readonly property bool enabled: configured && (root.options.enable ?? true)
    readonly property bool notifyAllDay: root.options.notifyAllDay ?? true
    readonly property bool dailySummary: root.options.dailySummary ?? false
    readonly property string dailySummaryTime: root.options.dailySummaryTime ?? "08:00"
    readonly property var defaultOffsets: root.options.offsets ?? ["-15m"]
    readonly property int shortSnoozeMinutes: 5
    readonly property int longSnoozeMinutes: 60

    // A lookup is keyed by UID and occurrence start so a 60-second timer does
    // not queue the same read request while khal is still answering it.
    property var pendingLookups: ({})

    function _occurrenceKey(event) {
        if (!event?.startDate)
            return "";
        return String(event.uid ?? "") + "|" + String(event.startDate.getTime());
    }

    function _notificationKey(event, offsetMinutes) {
        if (!event?.startDate)
            return "";
        return String(event.startDate.getTime()) + "|" + String(event.uid ?? "") + "|" + String(offsetMinutes);
    }

    function _remembered() {
        return Persistent.states.cheatsheet.timetableNotified ?? [];
    }

    function _remember(key) {
        const known = root._remembered();
        if (known.includes(key))
            return;
        Persistent.states.cheatsheet.timetableNotified = known.concat([key]);
    }

    function _prune(now) {
        const cutoff = now.getTime() - 48 * 60 * 60 * 1000;
        const next = root._remembered().filter(key => {
            const parts = String(key).split("|");
            const timestamp = parts[0] === "summary"
                ? new Date(String(parts[1] ?? "") + "T00:00:00").getTime()
                : Number(parts[0]);
            return Number.isFinite(timestamp) && timestamp >= cutoff;
        });
        if (next.length !== root._remembered().length)
            Persistent.states.cheatsheet.timetableNotified = next;
        const snoozes = root._snoozes();
        const remainingSnoozes = snoozes.filter(entry => Number(entry?.dueAt ?? 0) >= cutoff);
        if (remainingSnoozes.length !== snoozes.length)
            Persistent.states.cheatsheet.timetableSnoozes = remainingSnoozes;
    }

    function _minutesFromOffset(offset) {
        const match = String(offset ?? "").trim().match(/^-?(\d+)(m|h|d)$/i);
        if (!match)
            return null;
        const multiplier = match[2].toLowerCase() === "d" ? 1440 : (match[2].toLowerCase() === "h" ? 60 : 1);
        return Number(match[1]) * multiplier;
    }

    function _offsetsFor(details) {
        const alarms = details?.alarms ?? [];
        if (alarms.length > 0)
            return alarms.map(alarm => Number(alarm.minutesBefore)).filter(minutes => Number.isFinite(minutes) && minutes >= 0);
        return root.defaultOffsets.map(root._minutesFromOffset).filter(minutes => minutes !== null);
    }

    function _snapshotEvent(event) {
        if (!event?.startDate)
            return null;
        return {
            uid: String(event.uid ?? ""),
            content: String(event.content ?? ""),
            allDay: event.allDay === true,
            start: Qt.formatDateTime(event.startDate, "yyyy-MM-ddTHH:mm:ss"),
            end: event.endDate ? Qt.formatDateTime(event.endDate, "yyyy-MM-ddTHH:mm:ss") : "",
            description: String(event.description ?? ""),
            location: String(event.location ?? ""),
            url: String(event.url ?? "")
        };
    }

    function _eventFromSnapshot(snapshot) {
        const match = String(snapshot?.start ?? "").match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/);
        if (!match)
            return null;
        const startDate = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), Number(match[4]), Number(match[5]), Number(match[6] ?? 0));
        if (isNaN(startDate.getTime()))
            return null;
        return {
            uid: String(snapshot.uid ?? ""),
            content: String(snapshot.content ?? ""),
            allDay: snapshot.allDay === true,
            startDate: startDate,
            description: String(snapshot.description ?? ""),
            location: String(snapshot.location ?? ""),
            url: String(snapshot.url ?? "")
        };
    }

    function _meetingUrl(event) {
        const details = [String(event?.url ?? ""), String(event?.description ?? "")].filter(value => value.length > 0).join("\n");
        return String(EmailDetections.detectAll(details).meetings[0]?.url ?? "");
    }

    function _notificationActions(event) {
        const actions = [{ identifier: "__qs_calendar_open", text: Translation.tr("Open") }];
        if (root._meetingUrl(event).length > 0)
            actions.push({ identifier: "__qs_calendar_join", text: Translation.tr("Join") });
        actions.push(
            { identifier: "__qs_calendar_snooze_5m", text: Translation.tr("Snooze 5m") },
            { identifier: "__qs_calendar_snooze_1h", text: Translation.tr("Snooze 1h") }
        );
        return actions;
    }

    function _notify(event, offsetMinutes, sourceKey = "") {
        const when = offsetMinutes === 0
            ? Translation.tr("now")
            : Translation.tr("in %1 minutes").arg(String(offsetMinutes));
        let body = event.allDay
            ? Translation.tr("All-day event")
            : Translation.tr("Starts %1").arg(when);
        if (event.location)
            body += " · " + event.location;
        if (event.url)
            body += "\n" + event.url;
        const snapshot = root._snapshotEvent(event);
        if (!snapshot)
            return;
        Notifications.publishInternalNotification({
            appName: "Timetable",
            appIcon: "x-office-calendar",
            summary: event.content ?? Translation.tr("Calendar event"),
            body: body,
            actions: root._notificationActions(event),
            actionPayload: {
                sourceKey: sourceKey || root._notificationKey(event, offsetMinutes),
                event: snapshot,
                date: Qt.formatDate(event.startDate, "yyyy-MM-dd"),
                meetingUrl: root._meetingUrl(event)
            },
            sound: root.options.sound ?? false
        });
    }

    function _checkEvent(event, details, now) {
        if (!event?.startDate || (event.allDay && !root.notifyAllDay))
            return;
        const offsets = root._offsetsFor(details);
        for (const offsetMinutes of offsets) {
            const key = root._notificationKey(event, offsetMinutes);
            if (root._remembered().includes(key))
                continue;
            const trigger = event.startDate.getTime() - offsetMinutes * 60 * 1000;
            const elapsed = now.getTime() - trigger;
            // The timer is intentionally forgiving of a short compositor stall,
            // but never catches up stale alerts after a long suspend.
            if (elapsed >= 0 && elapsed < 90 * 1000) {
                root._remember(key);
                root._notify(event, offsetMinutes, key);
            }
        }
    }

    function _snoozes() {
        return Array.from(Persistent.states.cheatsheet.timetableSnoozes ?? []);
    }

    function _scheduleSnooze(payload, minutes, now = new Date()) {
        const event = root._eventFromSnapshot(payload?.event);
        const sourceKey = String(payload?.sourceKey ?? "");
        if (!event || sourceKey.length === 0 || !Number.isFinite(minutes) || minutes <= 0)
            return;
        const snoozes = root._snoozes().filter(entry => String(entry?.sourceKey ?? "") !== sourceKey);
        snoozes.push({
            sourceKey: sourceKey,
            dueAt: now.getTime() + minutes * 60 * 1000,
            event: root._snapshotEvent(event)
        });
        Persistent.states.cheatsheet.timetableSnoozes = snoozes;
    }

    function _checkSnoozes(now) {
        const pending = [];
        for (const entry of root._snoozes()) {
            if (Number(entry?.dueAt ?? 0) > now.getTime()) {
                pending.push(entry);
                continue;
            }
            const event = root._eventFromSnapshot(entry?.event);
            if (event)
                root._notify(event, 0, String(entry?.sourceKey ?? ""));
        }
        if (pending.length !== root._snoozes().length)
            Persistent.states.cheatsheet.timetableSnoozes = pending;
    }

    function _eventsInNextDay(now) {
        const end = new Date(now.getTime() + 24 * 60 * 60 * 1000);
        const days = [now, new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)];
        const seen = new Set();
        const events = [];
        for (const day of days) {
            const key = Qt.formatDate(day, "yyyy-MM-dd");
            for (const event of (CalendarService.eventsByDay[key] ?? [])) {
                const eventKey = root._occurrenceKey(event);
                if (seen.has(eventKey) || !event.startDate || event.startDate < now || event.startDate > end)
                    continue;
                seen.add(eventKey);
                events.push(event);
            }
        }
        return events;
    }

    function _checkDailySummary(now) {
        if (!root.dailySummary || Qt.formatTime(now, "hh:mm") !== root.dailySummaryTime)
            return;
        const dateKey = Qt.formatDate(now, "yyyy-MM-dd");
        const key = "summary|" + dateKey;
        if (root._remembered().includes(key))
            return;
        const events = CalendarService.eventsByDay[dateKey] ?? [];
        const body = events.length === 0
            ? Translation.tr("No events scheduled today.")
            : events.map(event => {
                const time = event.allDay ? Translation.tr("All day") : Qt.formatTime(event.startDate, "hh:mm");
                return time + " · " + String(event.content ?? "");
            }).join("\n");
        root._remember(key);
        Notifications.publishInternalNotification({
            appName: "Timetable",
            appIcon: "x-office-calendar",
            summary: Translation.tr("Today in your calendar"),
            body: body,
            actions: [{ identifier: "__qs_calendar_open", text: Translation.tr("Open calendar") }],
            actionPayload: { date: dateKey },
            sound: root.options.sound ?? false
        });
    }

    function checkNow(now = new Date()) {
        if (!root.enabled)
            return;
        root._prune(now);
        root._checkSnoozes(now);
        if (!CalendarService.khalAvailable)
            return;
        root._checkDailySummary(now);
        for (const event of root._eventsInNextDay(now)) {
            if (!event.uid) {
                root._checkEvent(event, null, now);
                continue;
            }
            const lookupKey = root._occurrenceKey(event);
            if (root.pendingLookups[lookupKey])
                continue;
            root.pendingLookups = Object.assign({}, root.pendingLookups, { [lookupKey]: true });
            CalendarService.readEvent(event.uid, reply => {
                const pending = Object.assign({}, root.pendingLookups);
                delete pending[lookupKey];
                root.pendingLookups = pending;
                root._checkEvent(event, reply?.ok ? reply.event : null, now);
            });
        }
    }

    Connections {
        target: Notifications
        function onInternalActionInvoked(identifier, notificationId, payload) {
            if (!String(identifier).startsWith("__qs_calendar_"))
                return;
            if (identifier === "__qs_calendar_open") {
                GlobalStates.openTimetableAt(String(payload?.date ?? ""));
            } else if (identifier === "__qs_calendar_join") {
                const meeting = root._meetingUrl(payload?.event ?? ({ }));
                if (meeting.length > 0)
                    Qt.openUrlExternally(meeting);
            } else if (identifier === "__qs_calendar_snooze_5m") {
                root._scheduleSnooze(payload, root.shortSnoozeMinutes);
            } else if (identifier === "__qs_calendar_snooze_1h") {
                root._scheduleSnooze(payload, root.longSnoozeMinutes);
            }
            Notifications.discardNotification(notificationId);
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.checkNow()
    }
}
