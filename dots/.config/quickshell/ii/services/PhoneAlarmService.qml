pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The phone's next alarm, mirrored read-only.
 *
 * Android keeps no public list of the Clock app's alarms, but the system does know
 * every alarm-clock alarm: `dumpsys alarm` prints each with an "Alarm clock:" block under
 * its owner's entry. Any app may use that API — Samsung Routines schedules its time
 * triggers with it — so the status bar's single "next alarm clock" can be an automation;
 * instead every one is listed with its package and ignored packages are dropped. This
 * polls over the ADB link the Phone sidebar already sets up — only while ADB is
 * installed and a device answers — and filters on the device, so a poll moves a few
 * lines instead of the whole dump.
 *
 * Ringing is inferred from the same poll: when the mirrored time passes and the phone
 * moves on to its next alarm, that alarm rang (a dismissal ahead of time changes the
 * time before it passes, so it does not count). The Clock's own notification, when KDE
 * Connect mirrors it, is a second signal — many phones keep the ringing notification
 * "ongoing", which KDE Connect does not forward, so it cannot be the only one.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.clockApp?.phoneAlarm ?? null
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? true) && KdeConnectService.adbPresent
    readonly property int pollMs: Math.max(1, root.opts?.pollMinutes ?? 10) * 60000
    readonly property var clockApps: Array.from(root.opts?.clockApps ?? []).map(app => String(app).toLowerCase())
    readonly property var ignorePackages: Array.from(root.opts?.ignorePackages ?? []).map(pkg => String(pkg))

    /// The phone's next alarm, or null when there is none or the phone is unreachable.
    property var nextAt: null
    /// A device answered the last poll.
    property bool reachable: false
    property real checkedAt: 0
    /// True for a few minutes after the phone's alarm was seen ringing.
    property bool ringing: false

    signal phoneAlarmRang(string summary)

    readonly property var pcNext: {
        AlarmService.alarms;
        AlarmService.upcomingAlarm;
        return AlarmService.nextAlarm(new Date());
    }
    /// Both ring within the next 12 h at different times: worth a word in the app.
    readonly property bool mismatch: {
        if (!root.nextAt || !root.pcNext)
            return false;
        const horizon = Date.now() + 12 * 3600000;
        const phone = root.nextAt.getTime();
        const pc = root.pcNext.at.getTime();
        return phone < horizon && pc < horizon && Math.abs(phone - pc) >= 60000;
    }

    // One "<package> <epoch ms>" line per alarm-clock alarm (the "next wake from idle" copy
    // repeats one, harmless under min), then "ok" so an empty list still reads as reachable.
    readonly property string listCommand: "dumpsys alarm | awk '"
        + "/Alarm\\{[0-9a-f]+ type / { pkg = $NF; sub(/\\}$/, \"\", pkg); when = \"\";"
        + " if (match($0, /origWhen [0-9]+/)) when = substr($0, RSTART + 9, RLENGTH - 9) }"
        + " /^ *Alarm clock:/ { print pkg, when } END { print \"ok\" }'"

    function refresh(): void {
        if (!root.enabled || pollProc.running)
            return;
        pollProc.command = ["adb"].concat(KdeConnectService.adbTargetArgs())
            .concat(["shell", root.listCommand]);
        pollProc.running = true;
    }

    /// The alarm time already announced as rung, so a second poll does not repeat it.
    property real announcedAt: 0

    function parse(text: string): void {
        const now = Date.now();
        root.checkedAt = now;
        root.reachable = /^ok$/m.test(text);
        const times = text.split("\n")
            .map(line => line.trim().split(/\s+/))
            .filter(f => f.length === 2 && /^\d{11,}$/.test(f[1]) && root.ignorePackages.indexOf(f[0]) === -1)
            .map(f => Number(f[1]))
            .filter(ms => ms > now);
        const value = times.length > 0 ? new Date(Math.min(...times)) : null;
        const previous = root.nextAt;
        // The mirrored time came and went, and the phone moved on to its next alarm: it
        // rang. A dismissal ahead of time moves the time before it passes, so it does not
        // count; a poll long after (the PC was asleep) is too stale to act on.
        if (root.reachable && previous && previous.getTime() <= now && now - previous.getTime() <= 15 * 60000
                && (value?.getTime() ?? 0) !== previous.getTime() && root.announcedAt !== previous.getTime()) {
            root.announcedAt = previous.getTime();
            root.markRang(Translation.tr("Alarm at %1").arg(Qt.formatTime(previous, "HH:mm")));
        }
        if ((value?.getTime() ?? 0) !== (previous?.getTime() ?? 0))
            root.nextAt = value;
    }

    function markRang(summary: string): void {
        root.ringing = true;
        ringingReset.restart();
        root.phoneAlarmRang(summary);
    }

    Process {
        id: pollProc
        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
        onExited: code => {
            if (code !== 0) {
                root.reachable = false;
                root.checkedAt = Date.now();
            }
        }
    }

    Timer {
        interval: root.pollMs
        repeat: true
        running: root.enabled
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Once the alarm time passes, the phone has moved on to its next one — and that
    // move is how the ring is noticed, so look soon after.
    Timer {
        interval: Math.max(30000, (root.nextAt?.getTime() ?? 0) - Date.now() + 45000)
        running: root.enabled && root.nextAt !== null
        onTriggered: root.refresh()
    }

    // ── Ringing, from KDE Connect ───────────────────────────────────────
    property var seenIds: ({})
    /// Notifications already on the phone when the shell started are history, not news.
    property bool primed: false

    function prime(): void {
        const seen = {};
        for (const n of Array.from(KdeConnectService.notifications ?? []))
            seen[String(n?.id ?? "")] = true;
        root.seenIds = seen;
        root.primed = true;
    }

    Component.onCompleted: root.prime()

    function isClockApp(name: string): bool {
        const lower = String(name ?? "").toLowerCase();
        return lower.length > 0 && root.clockApps.some(app => lower === app || lower.indexOf(app) !== -1);
    }

    Connections {
        target: KdeConnectService
        function onNotificationsChanged() {
            if (!Config.ready || !(root.opts?.enable ?? true))
                return;
            if (!root.primed) {
                root.prime();
                return;
            }
            const seen = Object.assign({}, root.seenIds);
            let rang = "";
            for (const n of Array.from(KdeConnectService.notifications ?? [])) {
                const id = String(n?.id ?? "");
                if (id.length === 0 || seen[id])
                    continue;
                seen[id] = true;
                if (!root.isClockApp(n.appName))
                    continue;
                const text = `${n.summary ?? ""} ${n.body ?? ""}`;
                const near = root.nextAt && Math.abs(Date.now() - root.nextAt.getTime()) <= 10 * 60000;
                if (near || /alarm|alarme|despertador/i.test(text))
                    rang = String(n.summary ?? n.appName ?? "");
            }
            root.seenIds = seen;
            if (rang.length > 0 && !root.ringing) {
                if (root.nextAt)
                    root.announcedAt = root.nextAt.getTime();
                root.markRang(rang);
            }
        }
    }

    Timer {
        id: ringingReset
        interval: 5 * 60000
        onTriggered: root.ringing = false
    }

    IpcHandler {
        target: "phoneAlarm"
        function refresh(): void {
            root.refresh();
        }
        function next(): string {
            return root.nextAt ? Qt.formatDateTime(root.nextAt, "yyyy-MM-dd HH:mm") : "";
        }
        function status(): string {
            return `next ${root.nextAt ? Qt.formatDateTime(root.nextAt, "HH:mm") : "-"} | reachable ${root.reachable}`
                + ` | ringing ${root.ringing} | mismatch ${root.mismatch} | notifications ${KdeConnectService.notificationCount}`
                + ` | newest ${Array.from(KdeConnectService.notifications ?? []).slice().sort((a, b) => (b.time || 0) - (a.time || 0))
                    .slice(0, 3).map(n => `[${n.appName}: ${n.summary}]`).join(" ")}`;
        }
    }
}
