pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

/**
 * Bedtime: a target time to stop using the computer, reminders around it, and a record
 * of when each night you actually did.
 *
 * A "night" is named after its evening and runs until `nightEndsHour` the next
 * morning, so 01:10 still belongs to yesterday's night. While the screen is unlocked
 * and there has been input in the last two minutes you count as up; the last such
 * moment of a night is its `lastActive`, and every minute up after the target adds to
 * `lateSeconds`. Nights before tracking started, or a night the shell missed, are
 * estimated from AppStats' hourly screen time instead (hour precision, marked so).
 *
 * Reminders: one when wind-down starts, one at bedtime, then a nudge every
 * `remindEveryMinutes` while you are still up.
 *
 * Intrusive mode (`intrusive`): past the target a full-screen modal (BedtimeOverlay)
 * covers every output. It can be snoozed `maxSnoozes` times for `snoozeMinutes` each;
 * once they are spent it counts `shutdownGraceSeconds` down — time to save and close —
 * and powers the computer off. Snoozes are persisted per night@target, so a reload or
 * a reboot does not hand them back.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.clockApp?.bedtime ?? null
    readonly property bool enabled: Config.ready && Persistent.ready && (root.opts?.enable ?? false)
    readonly property string targetTime: String(root.opts?.time ?? "23:30")
    readonly property int windDownMinutes: Math.max(0, root.opts?.windDownMinutes ?? 30)
    readonly property int remindEveryMinutes: Math.max(0, root.opts?.remindEveryMinutes ?? 15)
    readonly property int nightEndsHour: Math.max(0, Math.min(12, root.opts?.nightEndsHour ?? 5))
    readonly property var days: Array.from(root.opts?.days ?? [true, true, true, true, true, true, true])
    readonly property int onTimeGraceMinutes: 15

    /// "none" | "windDown" | "bedtime" — where tonight stands right now.
    property string phase: "none"
    property date now: new Date()
    property bool active: false
    /// Minutes past tonight's target while in the bedtime phase.
    readonly property int minutesLate: root.phase === "bedtime" && root.tonightTarget
        ? Math.max(0, Math.floor((root.now.getTime() - root.tonightTarget.getTime()) / 60000)) : 0

    readonly property string tonightKey: root.nightKey(root.now)
    readonly property var tonightTarget: root.targetFor(root.tonightKey)
    readonly property bool appliesTonight: root.appliesTo(root.tonightKey)

    // ── Intrusive mode ──────────────────────────────────────────────────
    readonly property bool intrusive: root.enabled && (root.opts?.intrusive ?? false)
    readonly property int snoozeMinutes: Math.max(1, root.opts?.snoozeMinutes ?? 5)
    readonly property int maxSnoozes: Math.max(0, root.opts?.maxSnoozes ?? 3)
    readonly property int shutdownGraceSeconds: Math.max(10, root.opts?.shutdownGraceSeconds ?? 30)
    readonly property string intrusiveMark: `${root.tonightKey}@${root.targetTime}`
    readonly property bool intrusiveTonight: Persistent.ready && Persistent.states.bedtime.intrusiveMark === root.intrusiveMark
    readonly property int snoozesUsed: root.intrusiveTonight ? Persistent.states.bedtime.snoozeCount : 0
    readonly property int snoozesLeft: Math.max(0, root.maxSnoozes - root.snoozesUsed)
    readonly property real snoozedUntil: root.intrusiveTonight ? Persistent.states.bedtime.snoozedUntil : 0
    /// The modal is up: intrusive, past bedtime, not snoozed, screen unlocked.
    readonly property bool intrusiveDue: root.intrusive && root.phase === "bedtime"
        && root.now.getTime() >= root.snoozedUntil && !GlobalStates.screenLocked
    /// Out of snoozes: the countdown to the shutdown runs (and keeps running if locked).
    readonly property bool shutdownArmed: root.intrusive && root.phase === "bedtime"
        && root.now.getTime() >= root.snoozedUntil && root.snoozesLeft <= 0
    /// Epoch ms of the forced shutdown while armed, else 0.
    property real shutdownAt: 0
    /// The countdown card was closed to save work: the overlay shrinks to a pill, the
    /// countdown keeps running. Reset each time the countdown re-arms.
    property bool countdownMinimized: false

    function snooze(): bool {
        if (!root.intrusiveDue || root.snoozesLeft <= 0)
            return false;
        const state = Persistent.states.bedtime;
        const count = root.snoozesUsed + 1;
        state.intrusiveMark = root.intrusiveMark;
        state.snoozeCount = count;
        state.snoozedUntil = Date.now() + root.snoozeMinutes * 60000;
        root.refresh();
        return true;
    }

    function shutdownNow(): void {
        root.shutdownAt = 0;
        // Plain poweroff needs no password for the active session; a block inhibitor only
        // stops it, so then ask to ignore inhibitors (polkit may prompt for that one).
        Quickshell.execDetached(["bash", "-c", "systemctl poweroff || systemctl poweroff --ignore-inhibitors || loginctl poweroff"]);
    }

    onShutdownArmedChanged: {
        root.shutdownAt = root.shutdownArmed ? Date.now() + root.shutdownGraceSeconds * 1000 : 0;
        root.countdownMinimized = false;
        if (root.shutdownArmed)
            Quickshell.execDetached(["notify-send", Translation.tr("Shutting down in %1 s").arg(root.shutdownGraceSeconds),
                Translation.tr("No snoozes left. Save your work and close your apps."),
                "-a", "Bedtime", "-i", "power_settings_new", "--urgency=critical"]);
    }

    // Wakes the modal right when a snooze ends, instead of on the next 30 s tick.
    Timer {
        running: root.intrusive && root.snoozedUntil > root.now.getTime()
        interval: Math.max(1000, root.snoozedUntil - root.now.getTime() + 250)
        onTriggered: root.refresh()
    }

    Timer {
        running: root.shutdownAt > 0
        interval: 1000
        repeat: true
        onTriggered: {
            if (Date.now() >= root.shutdownAt)
                root.shutdownNow();
        }
    }

    // ── Nights ──────────────────────────────────────────────────────────
    function pad(n) {
        return (n < 10 ? "0" : "") + n;
    }

    function dayKey(d): string {
        return `${d.getFullYear()}-${root.pad(d.getMonth() + 1)}-${root.pad(d.getDate())}`;
    }

    function parseKey(key) {
        const p = String(key).split("-").map(Number);
        return new Date(p[0], p[1] - 1, p[2]);
    }

    /** The evening a moment belongs to: before `nightEndsHour`, it is still last night. */
    function nightKey(d): string {
        const base = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        if (d.getHours() < root.nightEndsHour)
            base.setDate(base.getDate() - 1);
        return root.dayKey(base);
    }

    function appliesTo(key): bool {
        return Boolean(root.days[root.parseKey(key).getDay()] ?? true);
    }

    /** The target moment of a night: its evening at `time`, or the next morning past midnight. */
    function targetFor(key, time) {
        const t = String(time ?? root.targetTime).split(":").map(Number);
        const at = root.parseKey(key);
        at.setHours(t[0] || 0, t[1] || 0, 0, 0);
        if ((t[0] || 0) < root.nightEndsHour)
            at.setDate(at.getDate() + 1);
        return at;
    }

    function nightEnd(key) {
        const end = root.parseKey(key);
        end.setDate(end.getDate() + 1);
        end.setHours(root.nightEndsHour, 0, 0, 0);
        return end;
    }

    function phaseAt(d): string {
        const key = root.nightKey(d);
        if (!root.appliesTo(key))
            return "none";
        const target = root.targetFor(key);
        const t = d.getTime();
        if (t >= target.getTime() && t < root.nightEnd(key).getTime())
            return "bedtime";
        if (root.windDownMinutes > 0 && t >= target.getTime() - root.windDownMinutes * 60000 && t < target.getTime())
            return "windDown";
        return "none";
    }

    /** Recorded nights, newest last: [{ night, target, lastActive, lateSeconds }]. */
    readonly property var nights: Persistent.ready ? Array.from(Persistent.states.bedtime?.nights ?? []) : []

    function recordFor(key) {
        return root.nights.find(n => n.night === key) ?? null;
    }

    function writeRecord(key, changes): void {
        const list = Array.from(Persistent.states.bedtime.nights ?? []).map(n => Object.assign({}, n));
        let record = list.find(n => n.night === key);
        if (!record) {
            record = { night: key, target: root.targetTime, lastActive: 0, lateSeconds: 0 };
            list.push(record);
        }
        Object.assign(record, changes);
        list.sort((a, b) => a.night.localeCompare(b.night));
        Persistent.states.bedtime.nights = list.slice(-60);
    }

    // ── Usage history ───────────────────────────────────────────────────
    /**
     * The last hour of a night with real screen time, from AppStats: { lastActive, estimated }
     * or null when its days are not loaded or nothing was used after the evening began.
     */
    function estimateFromUsage(key) {
        const evening = root.parseKey(key);
        const morning = new Date(evening.getTime());
        morning.setDate(morning.getDate() + 1);
        const target = root.targetFor(key);
        const fromHour = Math.max(0, target.getHours() - 4);
        const history = AppStats.history ?? {};
        const system = AppStats.systemKey;
        const fg = AppStats.field.fg;
        const hoursOf = date => history[root.dayKey(date)]?.apps?.[system]?.h ?? null;
        let last = 0;
        const eveningHours = hoursOf(evening);
        const morningHours = hoursOf(morning);
        if (!eveningHours && !morningHours)
            return null;
        const consider = (date, hours, from, to) => {
            if (!hours)
                return;
            for (let h = from; h <= to; h++) {
                const tuple = hours[String(h)] ?? hours[h];
                const seconds = Number(tuple?.[fg] ?? 0);
                if (seconds >= 60) {
                    const at = new Date(date.getFullYear(), date.getMonth(), date.getDate(), h, 0, 0);
                    // Somewhere inside that hour: its minutes of use, counted from the top.
                    last = Math.max(last, at.getTime() + Math.min(3600, seconds) * 1000);
                }
            }
        };
        if (target.getDate() === evening.getDate())
            consider(evening, eveningHours, fromHour, 23);
        consider(morning, morningHours, 0, root.nightEndsHour - 1);
        return last > 0 ? { lastActive: last, estimated: true } : null;
    }

    /**
     * The last `count` nights, oldest first, recorded or estimated:
     * [{ night, target (Date), lastActive (ms, 0 unknown), lateMinutes, estimated, onTime, applies }].
     */
    function history(count) {
        const out = [];
        const today = root.parseKey(root.tonightKey);
        for (let i = count; i >= 1; i--) {
            const day = new Date(today.getFullYear(), today.getMonth(), today.getDate() - i);
            const key = root.dayKey(day);
            const record = root.recordFor(key);
            const target = root.targetFor(key, record?.target);
            let lastActive = record?.lastActive ?? 0;
            let estimated = false;
            if (!lastActive) {
                const guess = root.estimateFromUsage(key);
                if (guess) {
                    lastActive = guess.lastActive;
                    estimated = true;
                }
            }
            const lateMinutes = lastActive ? Math.round((lastActive - target.getTime()) / 60000) : 0;
            out.push({
                night: key,
                target: target,
                lastActive: lastActive,
                lateMinutes: lateMinutes,
                estimated: estimated,
                onTime: lastActive > 0 && lateMinutes <= root.onTimeGraceMinutes,
                applies: root.appliesTo(key)
            });
        }
        return out;
    }

    /** Nights in a row, ending last night, that ended on time. */
    function streak(list) {
        let n = 0;
        for (let i = list.length - 1; i >= 0; i--) {
            const night = list[i];
            if (!night.applies)
                continue;
            if (!night.onTime)
                break;
            n++;
        }
        return n;
    }

    function loadUsage(count): void {
        const dates = [];
        const today = root.parseKey(root.tonightKey);
        for (let i = count + 1; i >= 0; i--)
            dates.push(root.dayKey(new Date(today.getFullYear(), today.getMonth(), today.getDate() - i)));
        if (typeof AppStats.ensureDates === "function")
            AppStats.ensureDates(dates);
    }

    // ── Tracking ────────────────────────────────────────────────────────
    IdleMonitor {
        id: idle
        enabled: root.enabled
        timeout: 120
        respectInhibitors: false
    }

    function notify(title, body): void {
        Quickshell.execDetached(["notify-send", title, body, "-a", "Bedtime", "-i", "bedtime", "--urgency=normal"]);
    }

    function formatLate(minutes): string {
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return h > 0 ? Translation.tr("%1 h %2 min").arg(h).arg(m) : Translation.tr("%1 min").arg(m);
    }

    /// Where tonight stands, without recording anything (safe to call any time).
    function refresh(): void {
        root.now = new Date();
        const nextPhase = root.enabled ? root.phaseAt(root.now) : "none";
        if (root.phase !== nextPhase)
            root.phase = nextPhase;
        root.active = root.enabled && !idle.isIdle && !GlobalStates.screenLocked;
    }

    /// One tracking step: refresh, extend tonight's record, send what is due. Runs on the
    /// 30 s timer only, since each call counts as 30 s of the night.
    function tick(): void {
        root.refresh();
        if (!root.enabled)
            return;
        const key = root.tonightKey;
        const state = Persistent.states.bedtime;
        const target = root.tonightTarget;
        const t = root.now.getTime();

        // The night's record: last moment up, from four hours before the target on.
        if (root.appliesTonight && root.active && t >= target.getTime() - 4 * 3600000) {
            const record = root.recordFor(key);
            const late = root.phase === "bedtime" ? (record?.lateSeconds ?? 0) + tickTimer.interval / 1000 : (record?.lateSeconds ?? 0);
            root.writeRecord(key, { target: root.targetTime, lastActive: t, lateSeconds: Math.round(late) });
        }

        // Keyed by night *and* target, so moving the target re-arms tonight's reminders.
        const mark = `${key}@${root.targetTime}`;
        if (root.phase === "windDown" && state.windDownNotified !== mark) {
            state.windDownNotified = mark;
            root.notify(Translation.tr("Bedtime in %1 min").arg(Math.max(1, Math.round((target.getTime() - t) / 60000))),
                Translation.tr("Time to start winding down."));
        } else if (root.phase === "bedtime" && state.bedtimeNotified !== mark && root.active) {
            state.bedtimeNotified = mark;
            state.lastNudge = t;
            root.notify(Translation.tr("It's bedtime"), Translation.tr("You planned to stop at %1.").arg(Qt.formatTime(target, "HH:mm")));
        } else if (root.phase === "bedtime" && root.active && root.remindEveryMinutes > 0
                && t - state.lastNudge >= root.remindEveryMinutes * 60000) {
            state.lastNudge = t;
            root.notify(Translation.tr("Still up"), Translation.tr("%1 past your bedtime.").arg(root.formatLate(root.minutesLate)));
        }
    }

    Timer {
        id: tickTimer
        interval: 30000
        repeat: true
        running: Config.ready && Persistent.ready
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    IpcHandler {
        target: "bedtime"
        function enable(): void {
            Config.options.clockApp.bedtime.enable = true;
        }
        function disable(): void {
            Config.options.clockApp.bedtime.enable = false;
        }
        /// "HH:mm"
        function setTime(time: string): void {
            if (/^\d{1,2}:\d{2}$/.test(time))
                Config.options.clockApp.bedtime.time = time;
        }
        /// Drops one night's record ("yyyy-MM-dd", the evening's date).
        function forget(night: string): void {
            Persistent.states.bedtime.nights = Array.from(Persistent.states.bedtime.nights ?? []).filter(n => n.night !== night);
        }
        function snooze(): string {
            return root.snooze() ? `snoozed, ${root.snoozesLeft} left` : "not snoozable";
        }
        function intrusiveStatus(): string {
            root.refresh();
            return `${root.intrusive ? "on" : "off"} | due ${root.intrusiveDue} | snoozes ${root.snoozesUsed}/${root.maxSnoozes}`
                + ` | until ${root.snoozedUntil > 0 ? Qt.formatTime(new Date(root.snoozedUntil), "HH:mm:ss") : "-"}`
                + ` | shutdown ${root.shutdownAt > 0 ? Math.ceil((root.shutdownAt - Date.now()) / 1000) + " s" : "-"}`;
        }
        function status(): string {
            root.refresh();
            const last = root.recordFor(root.tonightKey);
            return `${root.enabled ? "on" : "off"} | ${root.phase} | target ${Qt.formatDateTime(root.tonightTarget, "yyyy-MM-dd HH:mm")}`
                + ` | active ${root.active} | tonight ${last ? Qt.formatTime(new Date(last.lastActive), "HH:mm") + " late " + last.lateSeconds + "s" : "-"}`;
        }
    }

    onEnabledChanged: root.refresh()
    onTargetTimeChanged: root.refresh()
    onWindDownMinutesChanged: root.refresh()
}
