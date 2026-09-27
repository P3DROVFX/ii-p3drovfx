pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Alarms: the list, when each rings next, and ringing them.
 *
 * Ringing is a window, not a minute. Every tick compares the alarms against the span
 * since the previous check (persisted, so a crash or a restart is covered too): an
 * alarm whose moment fell in that span rings if it is at most `catchUpMinutes` late
 * — a suspend that ended just after 07:00 still wakes you — and is reported as missed
 * when it is older. Alarms due at once queue instead of dropping each other, and a
 * systemd user timer with WakeSystem=true wakes a suspended machine shortly before
 * the next one.
 */
Singleton {
    id: root

    property list<var> alarms: Persistent.ready ? Persistent.states.alarms : []
    property int ringingAlarmIndex: -1
    property var ringingAlarm: (ringingAlarmIndex >= 0 && alarms && ringingAlarmIndex < alarms.length) ? alarms[ringingAlarmIndex] : null

    readonly property int snoozeMinutes: Math.max(1, Config.options?.time?.alarms?.snoozeMinutes ?? 9)
    readonly property int autoSilenceMinutes: Math.max(0, Config.options?.time?.alarms?.autoSilenceMinutes ?? 5)
    readonly property int catchUpMinutes: Math.max(0, Config.options?.time?.alarms?.catchUpMinutes ?? 10)
    readonly property bool wakeFromSuspend: Config.options?.time?.alarms?.wakeFromSuspend ?? true
    readonly property int wakeLeadSeconds: Math.max(0, Config.options?.time?.alarms?.wakeLeadSeconds ?? 90)
    readonly property int upcomingMinutes: Math.max(1, Config.options?.time?.alarms?.upcomingMinutes ?? 60)
    readonly property bool showUpcoming: Config.options?.time?.alarms?.showUpcoming ?? true

    /// Alarms too late to ring when the shell next looked: [{ time, label, at }].
    readonly property var missedAlarms: Persistent.ready ? Array.from(Persistent.states.alarmState?.missed ?? []) : []
    /// Alarms due while another was ringing, rung one after the other: [{ time, label, date }].
    property var ringQueue: []
    /// The next enabled alarm within `upcomingMinutes`, refreshed each minute: { index, alarm, at } or null.
    property var upcomingAlarm: null
    /// When the wake timer is set to fire, or null.
    property var wakeScheduledFor: null

    signal alarmRang(var alarm)
    signal alarmDismissed(var alarm)
    signal alarmSnoozed(var alarm)
    signal alarmMissed(var alarm, var at)

    function saveAlarms(newAlarms) {
        Persistent.states.alarms = newAlarms;
        root.alarms = Persistent.states.alarms;
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) {
                root.alarms = Persistent.states.alarms;
                root.refreshUpcoming();
                wakeDebounce.restart();
            }
        }
    }

    onAlarmsChanged: {
        root.refreshUpcoming();
        wakeDebounce.restart();
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

    function findIndex(predicate) {
        return Array.from(Persistent.states.alarms ?? []).findIndex(predicate);
    }

    // ── Timetable events ────────────────────────────────────────────────
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
        const index = root.findIndex(alarm => alarm.time === time && String(alarm.date ?? "") === date && alarm.label === label);
        if (index >= 0)
            root.updateAlarm(index, { eventUid: String(event.uid ?? ""), leadMinutes: Math.max(0, leadMinutes) });
        return true;
    }

    /** Index of the enabled alarm tied to this event's occurrence, or -1. */
    function alarmIndexForEvent(event) {
        const uid = String(event?.uid ?? "");
        const start = event?.startDate ? Qt.formatDate(event.startDate, "yyyy-MM-dd") : "";
        if (uid.length === 0)
            return -1;
        return Array.from(root.alarms).findIndex(alarm => String(alarm.eventUid ?? "") === uid
            && String(alarm.date ?? "").length > 0 && String(alarm.date) <= start);
    }

    function hasAlarmForEvent(event) {
        const index = root.alarmIndexForEvent(event);
        return index >= 0 && Boolean(root.alarms[index]?.enabled);
    }

    function removeAlarmForEvent(event) {
        const index = root.alarmIndexForEvent(event);
        if (index >= 0)
            root.deleteAlarm(index);
    }

    // ── Tasks ───────────────────────────────────────────────────────────
    function taskKey(task) {
        return String(task?.id ?? "");
    }

    /** Index of the alarm tied to a task (by id, else by its text), or -1. */
    function alarmIndexForTask(task) {
        const id = root.taskKey(task);
        const content = String(task?.content ?? "");
        return Array.from(root.alarms).findIndex(alarm => {
            const linkedId = String(alarm.taskId ?? "");
            if (linkedId.length === 0 && String(alarm.taskContent ?? "").length === 0)
                return false;
            return (id.length > 0 && linkedId === id) || (content.length > 0 && String(alarm.taskContent ?? "") === content);
        });
    }

    /**
     * Ties a one-off alarm to a task: it rings at `time` on `date` (the task's due day,
     * or the next time that clock time comes round) and goes away with the task.
     */
    function setAlarmForTask(task, time, date) {
        if (!task || !time)
            return false;
        const existing = root.alarmIndexForTask(task);
        const content = String(task.content ?? "").trim() || Translation.tr("Task");
        let day = date ? String(date) : "";
        if (day.length === 0) {
            const now = new Date();
            const parts = String(time).split(":").map(Number);
            const at = new Date(now.getFullYear(), now.getMonth(), now.getDate(), parts[0] || 0, parts[1] || 0);
            if (at.getTime() <= now.getTime())
                at.setDate(at.getDate() + 1);
            day = Qt.formatDate(at, "yyyy-MM-dd");
        }
        const fields = {
            time: time,
            label: content,
            days: [false, false, false, false, false, false, false],
            date: day,
            enabled: true,
            taskId: root.taskKey(task),
            taskContent: content
        };
        if (existing >= 0) {
            root.updateAlarm(existing, fields);
            return true;
        }
        if (!root.addAlarm(time, content, fields.days, day))
            return false;
        const index = root.findIndex(alarm => alarm.time === time && String(alarm.date ?? "") === day
            && alarm.label === content && String(alarm.taskContent ?? "").length === 0);
        if (index >= 0)
            root.updateAlarm(index, { taskId: fields.taskId, taskContent: content });
        return true;
    }

    function removeAlarmForTask(task) {
        const index = root.alarmIndexForTask(task);
        if (index >= 0)
            root.deleteAlarm(index);
    }

    // A finished task no longer needs its alarm. A task that vanished only counts as
    // deleted on the local provider; a remote list can be momentarily empty mid-sync.
    Connections {
        target: Todo
        function onListChanged() {
            if (!Persistent.ready || Todo.syncing)
                return;
            const tasks = Array.from(Todo.list ?? []);
            const linked = Array.from(root.alarms).filter(alarm => String(alarm.taskId ?? "").length > 0
                || String(alarm.taskContent ?? "").length > 0);
            if (linked.length === 0)
                return;
            const stale = linked.filter(alarm => {
                const task = tasks.find(t => (String(alarm.taskId ?? "").length > 0 && String(t?.id ?? "") === String(alarm.taskId))
                    || String(t?.content ?? "") === String(alarm.taskContent ?? ""));
                if (task)
                    return task.done === true;
                return Todo.provider === "local" && tasks.length > 0;
            });
            if (stale.length === 0)
                return;
            const keep = Array.from(Persistent.states.alarms).filter(alarm => !stale.some(s => s.time === alarm.time
                && s.label === alarm.label && String(s.date ?? "") === String(alarm.date ?? "")));
            root.saveAlarms(JSON.parse(JSON.stringify(keep)));
        }
    }

    // ── When ────────────────────────────────────────────────────────────
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

    /**
     * Every moment the alarm was due in (fromMs, toMs], oldest first, and whether each
     * was the skipped one. Skips are reported so the caller can consume them.
     */
    function occurrencesBetween(alarm, fromMs, toMs) {
        const out = [];
        if (!alarm || !alarm.enabled)
            return out;
        const dated = String(alarm.date ?? "");
        const repeats = (alarm.days ?? []).includes(true);
        const skip = String(alarm.skipDate ?? "");
        const start = new Date(fromMs);
        const days = Math.min(8, Math.ceil((toMs - fromMs) / 86400000) + 1);
        for (let i = 0; i <= days; i++) {
            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            const at = root.alarmDateAt(alarm, day);
            const t = at.getTime();
            if (t <= fromMs || t > toMs)
                continue;
            const key = Qt.formatDate(day, "yyyy-MM-dd");
            if (dated.length > 0 && dated !== key)
                continue;
            if (dated.length === 0 && repeats && !alarm.days[day.getDay()])
                continue;
            out.push({ at: at, skipped: key === skip });
        }
        return out;
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

    function refreshUpcoming() {
        const next = root.nextAlarm(new Date());
        const within = next && next.at.getTime() - Date.now() <= root.upcomingMinutes * 60000;
        const value = within ? next : null;
        const same = (value === null && root.upcomingAlarm === null)
            || (value && root.upcomingAlarm && value.at.getTime() === root.upcomingAlarm.at.getTime()
                && value.alarm.label === root.upcomingAlarm.alarm.label);
        if (!same)
            root.upcomingAlarm = value;
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
        const copy = Object.assign({}, cloned[index], { skipDate: "" });
        delete copy.taskId;
        delete copy.taskContent;
        delete copy.eventUid;
        cloned.splice(index + 1, 0, copy);
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

    // ── Ringing ─────────────────────────────────────────────────────────
    function keyOf(alarm) {
        return { time: String(alarm?.time ?? ""), label: String(alarm?.label ?? ""), date: String(alarm?.date ?? "") };
    }

    function indexOfKey(key) {
        return Array.from(root.alarms).findIndex(alarm => alarm.time === key.time
            && String(alarm.label ?? "") === key.label && String(alarm.date ?? "") === key.date);
    }

    function triggerAlarm(index) {
        if (index < 0 || index >= alarms.length) return;
        if (ringingAlarmIndex !== -1 && ringingAlarmIndex !== index) {
            root.enqueue(alarms[index]);
            return;
        }

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
        root.alarmRang(alarm);
    }

    function enqueue(alarm) {
        const key = root.keyOf(alarm);
        if (root.ringQueue.some(k => k.time === key.time && k.label === key.label && k.date === key.date))
            return;
        root.ringQueue = root.ringQueue.concat([key]);
    }

    /** Rings whatever queued up behind the alarm that just stopped. */
    function ringNextQueued() {
        if (root.ringingAlarmIndex !== -1)
            return;
        while (root.ringQueue.length > 0) {
            const key = root.ringQueue[0];
            root.ringQueue = root.ringQueue.slice(1);
            const index = root.indexOfKey(key);
            if (index >= 0) {
                root.triggerAlarm(index);
                return;
            }
        }
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
        root.alarmSnoozed(alarm);
        Qt.callLater(root.ringNextQueued);
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
        root.alarmDismissed(alarm);
        Qt.callLater(root.ringNextQueued);
    }

    // ── Missed ──────────────────────────────────────────────────────────
    function recordMissed(alarm, at) {
        const entry = { time: String(alarm.time ?? ""), label: String(alarm.label ?? ""), at: at.getTime() };
        const list = Array.from(Persistent.states.alarmState.missed ?? []).concat([entry]).slice(-10);
        Persistent.states.alarmState.missed = list;
        const label = String(alarm.label ?? "").length > 0 ? alarm.label : Translation.tr("Alarm");
        Quickshell.execDetached(["notify-send", Translation.tr("Missed alarm at %1").arg(Qt.formatTime(at, "HH:mm")), label,
            "-a", "Alarm", "-i", "appointment-missed", "--urgency=normal"]);
        root.alarmMissed(alarm, at);
    }

    function dismissMissed(index: int): void {
        const list = Array.from(Persistent.states.alarmState.missed ?? []);
        list.splice(index, 1);
        Persistent.states.alarmState.missed = list;
    }

    function clearMissed(): void {
        Persistent.states.alarmState.missed = [];
    }

    // ── The check ───────────────────────────────────────────────────────
    /// In-memory copy of the last check; written to disk once a minute and whenever an
    /// alarm is handled, so a crash replays at most a minute and never re-rings one.
    property real lastCheckMs: 0
    property int lastPersistedMinute: -1

    function persistLastCheck(ms) {
        Persistent.states.alarmState.lastCheck = ms;
        root.lastPersistedMinute = Math.floor(ms / 60000);
    }

    function checkAlarms() {
        if (!Persistent.ready)
            return;
        const now = Date.now();
        if (root.lastCheckMs <= 0)
            root.lastCheckMs = Persistent.states.alarmState.lastCheck > 0 ? Persistent.states.alarmState.lastCheck : now - 1000;
        let from = root.lastCheckMs;
        // Clock moved backwards (NTP, manual change): start over from now.
        if (from > now)
            from = now - 1000;
        // Very long gaps (days switched off) only need the last week.
        from = Math.max(from, now - 7 * 86400000);
        const gap = now - from;

        if (root.alarms && root.alarms.length > 0) {
            const due = [];
            const skipsToClear = [];
            for (let i = 0; i < root.alarms.length; i++) {
                const alarm = root.alarms[i];
                for (const hit of root.occurrencesBetween(alarm, from, now)) {
                    if (hit.skipped)
                        skipsToClear.push(root.keyOf(alarm));
                    else
                        due.push({ alarm: alarm, at: hit.at });
                }
            }
            due.sort((a, b) => a.at.getTime() - b.at.getTime());
            let handled = false;
            const disableOneOffs = [];
            for (const item of due) {
                handled = true;
                const late = now - item.at.getTime();
                if (late <= root.catchUpMinutes * 60000) {
                    if (root.ringingAlarmIndex === -1) {
                        const index = root.indexOfKey(root.keyOf(item.alarm));
                        if (index >= 0)
                            root.triggerAlarm(index);
                    } else {
                        root.enqueue(item.alarm);
                    }
                } else {
                    root.recordMissed(item.alarm, item.at);
                    if (!(item.alarm.days ?? []).includes(true))
                        disableOneOffs.push(root.keyOf(item.alarm));
                }
            }
            if (skipsToClear.length > 0 || disableOneOffs.length > 0) {
                const cloned = JSON.parse(JSON.stringify(Persistent.states.alarms));
                for (const alarm of cloned) {
                    const key = root.keyOf(alarm);
                    const match = k => k.time === key.time && k.label === key.label && k.date === key.date;
                    if (skipsToClear.some(match))
                        alarm.skipDate = "";
                    if (disableOneOffs.some(match))
                        alarm.enabled = false;
                }
                root.saveAlarms(cloned);
            }
            root.lastCheckMs = now;
            if (handled)
                root.persistLastCheck(now);
        } else {
            root.lastCheckMs = now;
        }

        const minute = Math.floor(now / 60000);
        if (minute !== root.lastPersistedMinute) {
            root.persistLastCheck(now);
            root.refreshUpcoming();
        }
        // Back from a suspend (or a long stall): the wake timer fired or was bypassed;
        // point it at whatever comes next.
        if (gap > 120000)
            wakeDebounce.restart();
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

    // ── Wake from suspend ───────────────────────────────────────────────
    // A transient systemd *user* timer: the user manager holds CAP_WAKE_ALARM, so
    // WakeSystem=true programs the RTC without root. It only wakes the machine; the
    // check above is what rings, catching the alarm up the moment the shell runs again.
    readonly property string wakeUnit: "ii-alarm-wake"
    // Not "" (which means "no wake"): the first sync must always run, or a timer left
    // over from a previous session would survive a list that no longer needs it.
    property string scheduledWakeKey: "#unsynced"

    function scheduleWake(): void {
        const next = root.wakeFromSuspend ? root.nextAlarm(new Date()) : null;
        let wakeAt = next ? new Date(next.at.getTime() - root.wakeLeadSeconds * 1000) : null;
        if (wakeAt && wakeAt.getTime() <= Date.now() + 30000)
            wakeAt = null;
        const key = wakeAt ? Qt.formatDateTime(wakeAt, "yyyy-MM-dd HH:mm:ss") : "";
        if (key === root.scheduledWakeKey)
            return;
        root.scheduledWakeKey = key;
        root.wakeScheduledFor = wakeAt;
        const unit = root.wakeUnit;
        let script = `systemctl --user stop ${unit}.timer 2>/dev/null; systemctl --user reset-failed ${unit}.timer ${unit}.service 2>/dev/null;`;
        if (key.length > 0)
            script += ` systemd-run --user --quiet --unit=${unit} --on-calendar='${key}' --timer-property=WakeSystem=true --timer-property=AccuracySec=1s /bin/true`;
        wakeProc.command = ["sh", "-c", script];
        wakeProc.running = false;
        wakeProc.running = true;
    }

    Process {
        id: wakeProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0)
                    console.warn("[AlarmService] wake timer:", this.text.trim());
            }
        }
    }

    Timer {
        id: wakeDebounce
        interval: 2000
        onTriggered: root.scheduleWake()
    }

    // The timer is absolute, but a DST change or an edited clock is caught hourly.
    Timer {
        interval: 3600000
        repeat: true
        running: true
        onTriggered: {
            root.scheduledWakeKey = "#";
            root.scheduleWake();
        }
    }

    onWakeFromSuspendChanged: wakeDebounce.restart()
    onWakeLeadSecondsChanged: wakeDebounce.restart()
    onUpcomingMinutesChanged: root.refreshUpcoming()

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
        function next(): string {
            const upcoming = root.nextAlarm(new Date());
            return upcoming ? Qt.formatDateTime(upcoming.at, "yyyy-MM-dd HH:mm") + " " + upcoming.alarm.label : "";
        }
        /// Re-run the check as if the last one was `minutes` ago — what a suspend or a
        /// crash of that length looks like. For testing the catch-up and missed paths.
        function replaySince(minutes: int): void {
            root.lastCheckMs = Date.now() - Math.max(1, minutes) * 60000;
            root.checkAlarms();
        }
        function clearMissed(): void {
            root.clearMissed();
        }
        /// What is ringing and how many wait behind it, for tests.
        function ringing(): string {
            const alarm = root.ringingAlarm;
            return (alarm ? String(alarm.label ?? "") : "-") + " | queued " + root.ringQueue.length;
        }
        function wake(): string {
            return root.wakeScheduledFor ? Qt.formatDateTime(root.wakeScheduledFor, "yyyy-MM-dd HH:mm:ss") : "";
        }
    }

    Component.onCompleted: {
        if (Persistent.ready) {
            root.alarms = Persistent.states.alarms;
            root.refreshUpcoming();
            wakeDebounce.restart();
        }
    }
}
