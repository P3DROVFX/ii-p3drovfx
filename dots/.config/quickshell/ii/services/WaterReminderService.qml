pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import qs
import qs.modules.common

// Water Reminder background widget service.
// Tracks daily glasses drunk and periodically sends a system notification
// every `intervalHours` until the daily goal is reached. The counter resets
// each day and persists across restarts via Persistent.state.
Singleton {
    id: root

    readonly property bool configured: Config.ready
    readonly property bool enabled: configured && (Config.options.background.widgets.water_reminder.enable ?? false)
    readonly property int dailyGoal: configured ? (Config.options.background.widgets.water_reminder.dailyGoal || 8) : 8
    readonly property int intervalHours: configured ? (Config.options.background.widgets.water_reminder.intervalHours || 2) : 2

    // Current glasses drunk this day (0..dailyGoal), reactive for the widget UI.
    property int glassesDrunk: 0
    property bool goalReached: dailyGoal > 0 && glassesDrunk >= dailyGoal
    property string _lastDate: ""
    property real _lastNotify: 0
    // Glasses per day, last 14 days, today included.
    property var history: ({})

    function _todayKey() {
        const d = new Date();
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }

    function _keyFor(date) {
        return date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate();
    }

    function _save() {
        if (!Persistent.ready) return;
        const w = Persistent.states.water;
        w.glassesDrunk = root.glassesDrunk;
        w.lastDate = root._lastDate;
        w.lastNotify = root._lastNotify;
        // Today's count into the history, keeping two weeks.
        const next = {};
        const oldest = new Date();
        oldest.setDate(oldest.getDate() - 13);
        const keep = {};
        for (let d = new Date(oldest); d <= new Date(); d.setDate(d.getDate() + 1))
            keep[root._keyFor(d)] = true;
        for (const key in root.history) {
            if (keep[key])
                next[key] = root.history[key];
        }
        if (root._lastDate.length > 0)
            next[root._lastDate] = root.glassesDrunk;
        root.history = next;
        w.historyJson = JSON.stringify(next);
    }

    /** The last seven days, oldest first: [{ date, glasses }]. */
    function week() {
        const out = [];
        for (let i = 6; i >= 0; i--) {
            const d = new Date();
            d.setDate(d.getDate() - i);
            const key = root._keyFor(d);
            out.push({ date: d, glasses: key === root._lastDate ? root.glassesDrunk : Number(root.history[key] ?? 0) });
        }
        return out;
    }

    /** A new day starts the count again, whether or not reminders are on. */
    function ensureToday() {
        if (root._lastDate !== root._todayKey()) {
            root.glassesDrunk = 0;
            root._lastDate = root._todayKey();
            root._save();
        }
    }

    /** Add (or take back) glasses, uncapped: the dock widget's counter. */
    function drink(delta) {
        root.ensureToday();
        const before = root.glassesDrunk;
        root.glassesDrunk = Math.max(0, root.glassesDrunk + delta);
        root._save();
        if (delta > 0 && before < root.dailyGoal && root.glassesDrunk >= root.dailyGoal) {
            Quickshell.execDetached([
                "notify-send",
                "-a", "Water Reminder",
                Translation.tr("Daily water goal reached!"),
                Translation.tr("You drank %1 glasses today.").arg(String(root.dailyGoal))
            ]);
        }
    }

    function _load() {
        if (!Persistent.ready) return;
        const w = Persistent.states.water || {};
        try {
            root.history = JSON.parse(w.historyJson || "{}") || {};
        } catch (e) {
            root.history = {};
        }
        root._lastDate = w.lastDate || "";
        root._lastNotify = w.lastNotify || 0;
        if (root._lastDate !== root._todayKey()) {
            // New day: reset counter.
            root.glassesDrunk = 0;
            root._lastDate = root._todayKey();
            root._save();
        } else {
            root.glassesDrunk = Math.max(0, w.glassesDrunk || 0);
        }
    }

    // Called by the widget action button.
    function addGlass() {
        const goal = root.dailyGoal;
        if (goal <= 0) return;
        if (root.glassesDrunk >= goal) {
            root.resetCounter();
            return;
        }
        root.glassesDrunk = Math.min(goal, root.glassesDrunk + 1);
        root._save();
        if (root.goalReached) {
            Quickshell.execDetached([
                "notify-send",
                "-a", "Water Reminder",
                Translation.tr("Daily water goal reached!"),
                Translation.tr("You drank %1 glasses today.").arg(String(goal))
            ]);
        }
    }

    // Reset the current day's counter (used from the settings page).
    function resetCounter() {
        root.glassesDrunk = 0;
        root._save();
    }

    function _notify() {
        const note = Config.options.background.widgets.water_reminder.reminderText || "Time to hydrate! 💧";
        Quickshell.execDetached([
            "notify-send",
            "-a", "Water Reminder",
            "-i", "water_drop",
            note
        ]);
    }

    function _check() {
        // Day rollover reset (also covered by _load on boot), for the dock
        // widget too, so it runs before the reminder gate.
        if (Persistent.ready)
            root.ensureToday();
        if (!root.enabled) return;
        if (root.dailyGoal > 0 && root.glassesDrunk >= root.dailyGoal) return;

        const intervalMs = Math.max(1, root.intervalHours) * 3600 * 1000;
        const now = Date.now();
        if (root._lastNotify <= 0 || (now - root._lastNotify) >= intervalMs) {
            root._lastNotify = now;
            root._save();
            root._notify();
        }
    }

    Timer {
        id: checkTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: root._check()
    }

    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) root._load(); }
    }
    Connections {
        target: Persistent
        function onReadyChanged() { if (Persistent.ready) root._load(); }
    }

    Component.onCompleted: {
        if (Config.ready && Persistent.ready) root._load();
    }
}
