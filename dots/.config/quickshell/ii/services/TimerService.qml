pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common

import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Simple Pomodoro time manager.
 */
Singleton {
    id: root

    property int focusTime: Config.options.time.pomodoro.focus
    property int breakTime: Config.options.time.pomodoro.breakTime
    property int longBreakTime: Config.options.time.pomodoro.longBreak
    property int cyclesBeforeLongBreak: Config.options.time.pomodoro.cyclesBeforeLongBreak

    property bool pomodoroRunning: Persistent.states.timer.pomodoro.running
    property bool pomodoroBreak: Persistent.states.timer.pomodoro.isBreak
    property bool pomodoroLongBreak: Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak);
    property int pomodoroLapDuration: pomodoroLongBreak ? longBreakTime : pomodoroBreak ? breakTime : focusTime // This is a binding that's to be kept
    property int pomodoroSecondsLeft: pomodoroLapDuration // Reasonable init value, to be changed
    property int pomodoroCycle: Persistent.states.timer.pomodoro.cycle

    property bool stopwatchRunning: Persistent.states.timer.stopwatch.running
    property int stopwatchTime: 0
    property int stopwatchStart: Persistent.states.timer.stopwatch.start
    property var stopwatchLaps: Persistent.states.timer.stopwatch.laps
    readonly property var countdowns: Persistent.states.timer.countdowns
    // Monotonic suffix for timer ids: two timers created in the same
    // millisecond would otherwise share one id and be cancelled together.
    property int countdownSerial: 0

    // General
    Component.onCompleted: {
        if (!stopwatchRunning)
            stopwatchReset();
    }

    function getCurrentTimeInSeconds() {  // Pomodoro uses Seconds
        return Math.floor(Date.now() / 1000);
    }

    function getCurrentTimeIn10ms() {  // Stopwatch uses 10ms
        return Math.floor(Date.now() / 10);
    }

    function countdownSecondsLeft(countdown) {
        if (countdown?.paused)
            return Math.max(0, Math.ceil(Number(countdown?.remaining ?? 0) / 1000));
        return Math.max(0, Math.ceil((Number(countdown?.endsAt ?? 0) - Date.now()) / 1000));
    }

    function formatCountdownDuration(seconds) {
        const safe = Math.max(0, Math.floor(Number(seconds) || 0));
        const hours = Math.floor(safe / 3600);
        const minutes = Math.floor((safe % 3600) / 60);
        const secs = safe % 60;
        const padded = `${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
        return hours > 0 ? `${String(hours)}:${padded}` : padded;
    }

    function defaultCountdownLabel(seconds) {
        const safe = Math.max(1, Math.floor(Number(seconds) || 0));
        if (safe >= 60 && safe % 60 === 0)
            return Translation.tr("%1 minute timer").arg(String(safe / 60));
        return Translation.tr("%1 timer").arg(root.formatCountdownDuration(safe));
    }

    function findCountdown(countdownId) {
        const id = String(countdownId ?? "");
        return Array.from(Persistent.states.timer.countdowns ?? [])
            .find(countdown => String(countdown?.id ?? "") === id) ?? null;
    }

    // Timers are stored as a plain list, so every mutation rebuilds it: the
    // JsonAdapter only notifies on a new reference, never on an in-place edit.
    function updateCountdown(countdownId, changes) {
        const id = String(countdownId ?? "");
        let changed = false;
        const next = Array.from(Persistent.states.timer.countdowns ?? []).map(countdown => {
            if (String(countdown?.id ?? "") !== id)
                return countdown;
            changed = true;
            return Object.assign({}, countdown, changes);
        });
        if (changed)
            Persistent.states.timer.countdowns = next;
        return changed;
    }

    function addCountdownSeconds(seconds, label = "") {
        const durationSeconds = Math.max(1, Math.round(Number(seconds) || 0));
        const next = Array.from(Persistent.states.timer.countdowns ?? []);
        root.countdownSerial++;
        const countdown = {
            id: "countdown-" + Date.now().toString(36) + "-" + root.countdownSerial.toString(36),
            label: String(label ?? "").trim() || root.defaultCountdownLabel(durationSeconds),
            endsAt: Date.now() + durationSeconds * 1000,
            durationSeconds: durationSeconds,
            paused: false,
            remaining: 0,
            notified: false
        };
        next.unshift(countdown);
        Persistent.states.timer.countdowns = next;
        return countdown;
    }

    function addCountdown(minutes, label = "") {
        const durationMinutes = Math.max(1, Number(minutes) || 1);
        return root.addCountdownSeconds(durationMinutes * 60, String(label ?? "").trim()
            || Translation.tr("%1 minute timer").arg(String(durationMinutes)));
    }

    function pauseCountdown(countdownId) {
        const countdown = root.findCountdown(countdownId);
        if (!countdown || countdown.paused || countdown.notified)
            return;
        root.updateCountdown(countdownId, {
            paused: true,
            remaining: Math.max(0, Number(countdown.endsAt ?? 0) - Date.now())
        });
    }

    function resumeCountdown(countdownId) {
        const countdown = root.findCountdown(countdownId);
        if (!countdown || !countdown.paused || countdown.notified)
            return;
        root.updateCountdown(countdownId, {
            paused: false,
            endsAt: Date.now() + Math.max(0, Number(countdown.remaining ?? 0)),
            remaining: 0
        });
    }

    function toggleCountdown(countdownId) {
        const countdown = root.findCountdown(countdownId);
        if (!countdown)
            return;
        if (countdown.paused)
            root.resumeCountdown(countdownId);
        else
            root.pauseCountdown(countdownId);
    }

    function restartCountdown(countdownId) {
        const countdown = root.findCountdown(countdownId);
        if (!countdown)
            return;
        const durationSeconds = Math.max(1, Math.round(Number(countdown.durationSeconds ?? 0) || 60));
        root.updateCountdown(countdownId, {
            endsAt: Date.now() + durationSeconds * 1000,
            paused: false,
            remaining: 0,
            notified: false
        });
    }

    function removeCountdown(countdownId) {
        const next = Array.from(Persistent.states.timer.countdowns ?? [])
            .filter(countdown => String(countdown?.id ?? "") !== String(countdownId ?? ""));
        Persistent.states.timer.countdowns = next;
    }

    function clearFinishedCountdowns() {
        const next = Array.from(Persistent.states.timer.countdowns ?? []).filter(countdown => !countdown?.notified);
        Persistent.states.timer.countdowns = next;
    }

    // The sidebar's duration picker persists its dials here, so a keybind can
    // start the drafted timer without the tab being loaded.
    function draftCountdownSeconds() {
        const draft = Persistent.states.timer.countdownDraft;
        return Math.max(0, (Number(draft?.hours ?? 0) * 3600)
            + (Number(draft?.minutes ?? 0) * 60)
            + Number(draft?.seconds ?? 0));
    }

    function startDraftCountdown() {
        const seconds = root.draftCountdownSeconds();
        if (seconds <= 0)
            return null;
        return root.addCountdownSeconds(seconds);
    }

    function refreshCountdowns() {
        const current = Array.from(Persistent.states.timer.countdowns ?? []);
        let changed = false;
        const next = current.map(countdown => {
            if (countdown.paused || countdown.notified || root.countdownSecondsLeft(countdown) > 0)
                return countdown;
            changed = true;
            Quickshell.execDetached(["notify-send", String(countdown.label ?? Translation.tr("Timer")), Translation.tr("Timer finished"), "-a", "Shell", "-i", "alarm", "--hint=boolean:suppress-sound:true"]);
            SoundService.playEvent("pomodoro", "alarm-clock-elapsed");
            return Object.assign({}, countdown, { notified: true });
        });
        if (changed) {
            Persistent.states.timer.countdowns = next;
        }
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        running: root.countdowns.some(countdown => !countdown.notified && !countdown.paused)
        onTriggered: root.refreshCountdowns()
    }

    // Pomodoro
    function refreshPomodoro() {
        // Work <-> break ?
        if (getCurrentTimeInSeconds() >= Persistent.states.timer.pomodoro.start + pomodoroLapDuration) {
            // Reset counts
            Persistent.states.timer.pomodoro.isBreak = !Persistent.states.timer.pomodoro.isBreak;
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();

            // Send notification
            let notificationMessage;
            if (Persistent.states.timer.pomodoro.isBreak && (pomodoroCycle + 1 == cyclesBeforeLongBreak)) {
                notificationMessage = Translation.tr(`🌿 Long break: %1 minutes`).arg(Math.floor(longBreakTime / 60));
            } else if (Persistent.states.timer.pomodoro.isBreak) {
                notificationMessage = Translation.tr(`☕ Break: %1 minutes`).arg(Math.floor(breakTime / 60));
            } else {
                notificationMessage = Translation.tr(`🔴 Focus: %1 minutes`).arg(Math.floor(focusTime / 60));
            }

            Quickshell.execDetached(["notify-send", "Pomodoro", notificationMessage, "-a", "Shell", "--hint=boolean:suppress-sound:true"]);
            SoundService.playEvent("pomodoro", "alarm-clock-elapsed");

            if (!pomodoroBreak) {
                Persistent.states.timer.pomodoro.cycle = (Persistent.states.timer.pomodoro.cycle + 1) % root.cyclesBeforeLongBreak;
            }
        }

        pomodoroSecondsLeft = pomodoroLapDuration - (getCurrentTimeInSeconds() - Persistent.states.timer.pomodoro.start);
    }

    Timer {
        id: pomodoroTimer
        interval: 200
        running: root.pomodoroRunning
        repeat: true
        onTriggered: refreshPomodoro()
    }

    function togglePomodoro() {
        Persistent.states.timer.pomodoro.running = !pomodoroRunning;
        if (Persistent.states.timer.pomodoro.running) {
            // Start/Resume
            Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds() + pomodoroSecondsLeft - pomodoroLapDuration;
        }
    }

    function resetPomodoro() {
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.isBreak = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        Persistent.states.timer.pomodoro.cycle = 0;
        refreshPomodoro();
    }

    signal customTimeRequested(int currentHour, int currentMinute, string title)

    function requestCustomTime(hour, minute, title) {
        let currentSeconds = (hour !== undefined && minute !== undefined)
            ? (hour * 3600 + minute * 60)
            : (root.pomodoroSecondsLeft > 0 ? root.pomodoroSecondsLeft : root.pomodoroLapDuration);
        let h = Math.floor(currentSeconds / 3600);
        let m = Math.floor((currentSeconds % 3600) / 60);
        let t = title || (root.pomodoroLongBreak ? Translation.tr("Long break time") : root.pomodoroBreak ? Translation.tr("Break time") : Translation.tr("Focus time"));
        root.customTimeRequested(h, m, t);
    }

    function setPomodoroTime(hours, minutes) {
        const totalSeconds = Math.max(60, (hours * 3600) + (minutes * 60));
        if (pomodoroLongBreak) {
            Config.options.time.pomodoro.longBreak = totalSeconds;
        } else if (pomodoroBreak) {
            Config.options.time.pomodoro.breakTime = totalSeconds;
        } else {
            Config.options.time.pomodoro.focus = totalSeconds;
        }
        Persistent.states.timer.pomodoro.running = false;
        Persistent.states.timer.pomodoro.start = getCurrentTimeInSeconds();
        refreshPomodoro();
    }

    // Stopwatch
    function refreshStopwatch() {  // Stopwatch stores time in 10ms
        stopwatchTime = getCurrentTimeIn10ms() - stopwatchStart;
    }

    Timer {
        id: stopwatchTimer
        interval: 10
        running: root.stopwatchRunning
        repeat: true
        onTriggered: refreshStopwatch()
    }

    function toggleStopwatch() {
        if (root.stopwatchRunning)
            stopwatchPause();
        else
            stopwatchResume();
    }

    function stopwatchPause() {
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchResume() {
        if (stopwatchTime === 0) Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = true;
        Persistent.states.timer.stopwatch.start = getCurrentTimeIn10ms() - stopwatchTime;
    }

    function stopwatchReset() {
        stopwatchTime = 0;
        Persistent.states.timer.stopwatch.laps = [];
        Persistent.states.timer.stopwatch.running = false;
    }

    function stopwatchRecordLap() {
        Persistent.states.timer.stopwatch.laps.push(stopwatchTime);
    }
}
