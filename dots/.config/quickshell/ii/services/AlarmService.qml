pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property list<var> alarms: Persistent.ready ? Persistent.states.alarms : []
    property int ringingAlarmIndex: -1
    property var ringingAlarm: (ringingAlarmIndex >= 0 && alarms && ringingAlarmIndex < alarms.length) ? alarms[ringingAlarmIndex] : null

    property string lastTriggeredMinute: ""

    readonly property int snoozeMinutes: Math.max(1, Config.options?.time?.alarms?.snoozeMinutes ?? 9)
    readonly property int autoSilenceMinutes: Math.max(0, Config.options?.time?.alarms?.autoSilenceMinutes ?? 5)

    function saveAlarms(newAlarms) {
        Persistent.states.alarms = newAlarms;
        root.alarms = Persistent.states.alarms;
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) {
                root.alarms = Persistent.states.alarms;
            }
        }
    }

    function toggleAlarm(index) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            cloned[index].enabled = !cloned[index].enabled;
            if (!cloned[index].enabled && ringingAlarmIndex === index) {
                stopRinging();
            }
            saveAlarms(cloned);
        }
    }

    function addAlarm(time, label, days, date = "") {
        if (!Persistent.ready) return false;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms || []));
        cloned.push({
            time: time || "08:00",
            label: label || Translation.tr("Alarm"),
            days: days || [false, false, false, false, false, false, false],
            // Empty means the original recurring/one-shot behaviour. A
            // YYYY-MM-DD value makes this a reminder for that local date and
            // avoids an alarm requested for tomorrow firing today at the same
            // time.
            date: date || "",
            enabled: true
        });
        cloned.sort((a, b) => a.time.localeCompare(b.time));
        saveAlarms(cloned);
        return true;
    }

    /** Merges `changes` into one alarm and keeps the list sorted by time. */
    function updateAlarm(index, changes) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index < 0 || index >= cloned.length) return;
        cloned[index] = Object.assign({}, cloned[index], changes);
        cloned.sort((a, b) => a.time.localeCompare(b.time));
        saveAlarms(cloned);
    }

    /** A dated alarm `leadMinutes` before a timetable event, labelled with its title. */
    function addAlarmForEvent(event, leadMinutes) {
        if (!event || !event.startDate) return false;
        const at = new Date(event.startDate.getTime() - Math.max(0, leadMinutes) * 60000);
        if (at.getTime() <= Date.now()) return false;
        const time = Qt.formatTime(at, "HH:mm");
        const date = Qt.formatDate(at, "yyyy-MM-dd");
        const label = String(event.content ?? event.title ?? "").trim() || Translation.tr("Event");
        if (root.alarms.some(alarm => alarm.time === time && String(alarm.date ?? "") === date && alarm.label === label))
            return false;
        if (!root.addAlarm(time, label, [false, false, false, false, false, false, false], date))
            return false;
        const index = Persistent.states.alarms.findIndex(alarm => alarm.time === time && String(alarm.date ?? "") === date && alarm.label === label);
        if (index >= 0)
            root.updateAlarm(index, { eventUid: String(event.uid ?? ""), leadMinutes: Math.max(0, leadMinutes) });
        return true;
    }

    function hasAlarmForEvent(event) {
        const uid = String(event?.uid ?? "");
        const start = event?.startDate ? Qt.formatDate(event.startDate, "yyyy-MM-dd") : "";
        return uid.length > 0 && root.alarms.some(alarm => String(alarm.eventUid ?? "") === uid
            && String(alarm.date ?? "").length > 0 && alarm.enabled && String(alarm.date) <= start);
    }

    function alarmDateAt(alarm, day) {
        const parts = String(alarm?.time ?? "00:00").split(":");
        return new Date(day.getFullYear(), day.getMonth(), day.getDate(), parseInt(parts[0]) || 0, parseInt(parts[1]) || 0, 0);
    }

    /** When the alarm rings next after `from`, honouring repeat days, its date and a skip. */
    function nextOccurrence(alarm, from) {
        if (!alarm || !alarm.enabled) return null;
        const now = from ?? new Date();
        const dated = String(alarm.date ?? "");
        if (dated.length > 0) {
            const parts = dated.split("-").map(Number);
            const at = root.alarmDateAt(alarm, new Date(parts[0], parts[1] - 1, parts[2]));
            return at.getTime() > now.getTime() ? at : null;
        }
        const repeats = (alarm.days ?? []).includes(true);
        const skip = String(alarm.skipDate ?? "");
        for (let i = 0; i <= 14; i++) {
            const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
            const at = root.alarmDateAt(alarm, day);
            if (at.getTime() <= now.getTime()) continue;
            if (repeats && !alarm.days[day.getDay()]) continue;
            if (Qt.formatDate(day, "yyyy-MM-dd") === skip) continue;
            return at;
        }
        return null;
    }

    /** "In 7h 12m" style countdown to the next ring, or "" when the alarm is off. */
    function untilText(alarm, from) {
        const next = root.nextOccurrence(alarm, from);
        if (!next) return "";
        const now = from ?? new Date();
        const minutes = Math.max(1, Math.ceil((next.getTime() - now.getTime()) / 60000));
        const d = Math.floor(minutes / 1440);
        const h = Math.floor((minutes % 1440) / 60);
        const m = minutes % 60;
        let parts = [];
        if (d > 0) parts.push(d + Translation.tr("d"));
        if (h > 0) parts.push(h + Translation.tr("h"));
        if (m > 0 && d === 0) parts.push(m + Translation.tr("m"));
        return Translation.tr("In %1").arg(parts.join(" "));
    }

    /** The enabled alarm that rings soonest, with its time: { index, alarm, at } or null. */
    function nextAlarm(from) {
        let best = null;
        for (let i = 0; i < root.alarms.length; i++) {
            const at = root.nextOccurrence(root.alarms[i], from);
            if (at && (!best || at.getTime() < best.at.getTime()))
                best = { index: i, alarm: root.alarms[i], at: at };
        }
        return best;
    }

    function isSkipped(alarm) {
        return String(alarm?.skipDate ?? "").length > 0;
    }

    /** Dismisses only the next ring of a repeating alarm, like Android's "Skip once". */
    function skipNext(index) {
        const alarm = root.alarms[index];
        if (!alarm) return;
        const hasRepeat = (alarm.days ?? []).includes(true);
        if (!hasRepeat) {
            root.updateAlarm(index, { enabled: false });
            return;
        }
        const next = root.nextOccurrence(alarm, new Date());
        if (next)
            root.updateAlarm(index, { skipDate: Qt.formatDate(next, "yyyy-MM-dd") });
    }

    function unskip(index) {
        if (root.alarms[index])
            root.updateAlarm(index, { skipDate: "" });
    }

    function duplicateAlarm(index) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index < 0 || index >= cloned.length) return;
        cloned.splice(index + 1, 0, Object.assign({}, cloned[index], { skipDate: "" }));
        saveAlarms(cloned);
    }

    function editAlarm(index, time, label, days) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            cloned[index].time = time;
            cloned[index].label = label;
            cloned[index].days = days;
            cloned[index].enabled = true;
            cloned.sort((a, b) => a.time.localeCompare(b.time));
            saveAlarms(cloned);
        }
    }

    function deleteAlarm(index) {
        if (!Persistent.ready) return;
        let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
        if (index >= 0 && index < cloned.length) {
            if (ringingAlarmIndex === index) {
                stopRinging();
            }
            cloned.splice(index, 1);
            saveAlarms(cloned);
        }
    }

    function triggerAlarm(index) {
        if (index < 0 || index >= alarms.length) return;

        let now = new Date();
        let currentHour = now.getHours().toString().padStart(2, '0');
        let currentMin = now.getMinutes().toString().padStart(2, '0');
        lastTriggeredMinute = currentHour + ":" + currentMin;

        ringingAlarmIndex = index;
        let alarm = alarms[index];

        // Play sound in loop if enabled
        SoundService.stopLoop();
        if (Config.options.sounds.alarm) {
            const fadeSeconds = Config.options.sounds.alarmFadeIn ? Config.options.sounds.alarmFadeInSeconds : 0;
            SoundService.startLoop("alarm", "alarm-clock-elapsed", fadeSeconds);
        }

        // Send a system notification if neither the fullscreen popup nor the island
        // is going to show it.
        if (!Config.options.time.alarms.useFullscreenPopup && !GlobalStates.islandOwnsAlarm) {
            let labelStr = alarm.label ? alarm.label : Translation.tr("Alarm");
            Quickshell.execDetached(["notify-send", labelStr, alarm.time, "-a", "Alarm", "-i", "alarm", "--urgency=critical", "--hint=boolean:suppress-sound:true"]);
        }

        GlobalStates.alarmRinging = true;
    }

    /** The alarm a snooze will ring again, and when; null while nothing is snoozed. */
    property var snoozedAlarm: null
    property double snoozedUntil: 0

    /**
     * Quiet the ringing alarm and ring it again in `minutes`.
     *
     * Unlike stopping, a one-shot alarm stays enabled: it has not been dealt with yet.
     * The alarm is found again by time and label when the snooze ends, since its index
     * can move if the list is edited in between.
     */
    function snooze(minutes) {
        if (ringingAlarmIndex === -1)
            return;
        const alarm = alarms[ringingAlarmIndex];
        const length = Math.max(1, Math.round(minutes || root.snoozeMinutes));
        snoozedAlarm = alarm ? { time: alarm.time, label: alarm.label ?? "" } : null;
        snoozedUntil = Date.now() + length * 60000;
        ringingAlarmIndex = -1;
        SoundService.stopLoop();
        GlobalStates.alarmRinging = false;
        snoozeTimer.interval = length * 60000;
        snoozeTimer.restart();
    }

    function cancelSnooze() {
        snoozeTimer.stop();
        snoozedAlarm = null;
        snoozedUntil = 0;
    }

    Timer {
        id: snoozeTimer
        repeat: false
        onTriggered: {
            const wanted = root.snoozedAlarm;
            root.snoozedAlarm = null;
            root.snoozedUntil = 0;
            if (!wanted)
                return;
            for (let i = 0; i < root.alarms.length; i++) {
                const alarm = root.alarms[i];
                // Switched off or deleted while snoozed: that was the answer.
                if (alarm.enabled && alarm.time === wanted.time && (alarm.label ?? "") === wanted.label) {
                    root.triggerAlarm(i);
                    return;
                }
            }
        }
    }

    function stopRinging() {
        if (ringingAlarmIndex === -1) return;

        let alarm = alarms[ringingAlarmIndex];
        if (alarm && !alarm.days.includes(true)) {
            let cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
            for (let i = 0; i < cloned.length; i++) {
                if (cloned[i].time === alarm.time && cloned[i].label === alarm.label
                        && String(cloned[i].date ?? "") === String(alarm.date ?? "")) {
                    cloned[i].enabled = false;
                    break;
                }
            }
            saveAlarms(cloned);
        }

        ringingAlarmIndex = -1;
        SoundService.stopLoop();
        GlobalStates.alarmRinging = false;
    }

    function checkAlarms() {
        if (!Persistent.ready || !alarms || alarms.length === 0) return;
        
        let now = new Date();
        let currentHour = now.getHours().toString().padStart(2, '0');
        let currentMin = now.getMinutes().toString().padStart(2, '0');
        let timeStr = currentHour + ":" + currentMin;
        
        if (timeStr === lastTriggeredMinute) {
            return;
        }

        if (ringingAlarmIndex !== -1) {
            return;
        }

        let dayOfWeek = now.getDay(); // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
        let dateString = Qt.formatDate(now, "yyyy-MM-dd");

        for (let i = 0; i < alarms.length; i++) {
            let alarm = alarms[i];
            if (alarm.enabled && alarm.time === timeStr
                    && (String(alarm.date ?? "").length === 0 || String(alarm.date) === dateString)) {
                let hasRepeatDays = alarm.days.includes(true);
                let dayMatches = !hasRepeatDays || alarm.days[dayOfWeek];

                if (dayMatches && String(alarm.skipDate ?? "") === dateString) {
                    lastTriggeredMinute = timeStr;
                    root.updateAlarm(i, { skipDate: "" });
                    break;
                }
                if (dayMatches) {
                    triggerAlarm(i);
                    break;
                }
            }
        }
    }

    Timer {
        id: alarmCheckTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: checkAlarms()
    }

    Timer {
        id: autoStopTimer
        interval: Math.max(1, root.autoSilenceMinutes) * 60000
        running: ringingAlarmIndex !== -1 && root.autoSilenceMinutes > 0
        repeat: false
        onTriggered: stopRinging()
    }

    IpcHandler {
        target: "alarmService"
        function trigger(index: int): void {
            root.triggerAlarm(index);
        }
        function add(time: string, label: string): void {
            root.addAlarm(time, label, [true, true, true, true, true, true, true]);
        }
        function stop(): void {
            root.stopRinging();
        }
        function snooze(minutes: int): void {
            root.snooze(minutes);
        }
        function cancelSnooze(): void {
            root.cancelSnooze();
        }
        function remove(index: int): void {
            root.deleteAlarm(index);
        }
    }

    Component.onCompleted: {
        if (Persistent.ready) {
            root.alarms = Persistent.states.alarms;
        }
    }
}
