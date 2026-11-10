pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.core
import qs.services

/**
 * Sculpt timer & pomodoro — three type-led readouts, chosen in the widget's
 * page (`bar.timers.sculptVariant`):
 *
 *   squeeze   tall digits that condense on the width axis as the time runs out
 *             — a full timer is set wide, the last seconds narrow. A break is
 *             set slanted, a paused timer light.
 *   fill      the capsule is the progress bar: the vivid tone fills it as the
 *             time goes, and the digits change colour exactly where the fill
 *             edge crosses them
 *   phases    a display label (FOCUS, BREAK, the countdown's name) over a
 *             segmented indicator — one segment per pomodoro of the cycle, the
 *             current one wider and filling — beside the time
 *
 * Every active timer (stopwatch, pomodoro, countdown, next alarm) gets one
 * readout; a click toggles it. The variants are drawn horizontally and turned
 * as a whole on a vertical bar.
 */
Item {
    id: root

    property bool vertical: false

    readonly property string variant: Config.options.bar.timers.sculptVariant ?? "squeeze"
    readonly property bool bubbled: IslandGeometry.bubbled("timer")
    readonly property bool compVisible: timerState.visible && !root.bubbled
    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8
    readonly property int contentRotation: root.vertical
        ? (Config.options.bar.bottom ? 90 : -90)
        : 0

    TimerBarState {
        id: timerState
    }

    BarWidgetPalette {
        id: timerTones
        colorMode: Config.options.bar.timers.colorMode ?? "primary"
    }

    // ── The readouts ─────────────────────────────────────────────────────────
    // `keys` only changes when a timer appears or goes away, so the readouts
    // are not rebuilt on every tick (the stopwatch ticks every 10 ms); each
    // readout reads its live values through `entryFor`.
    // Plain rather than readonly so a preview can hand in readouts.
    property var keys: {
        const list = [];
        if (timerState.showStopwatch && timerState.hasStopwatch)
            list.push("stopwatch");
        if (timerState.showPomodoro && timerState.hasPomodoro)
            list.push("pomodoro");
        if (timerState.showCountdowns && timerState.hasCountdown)
            list.push("countdown");
        if (timerState.hasUpcomingAlarm)
            list.push("alarm");
        return list;
    }

    // remaining: 1 → 0 while the time runs out; -1 when there is no total.
    // A preview overrides this with its own function.
    property var entryFor: function (key) {
        if (key === "stopwatch") {
            const text = timerState.stopwatchText;
            const seconds = Math.floor(Number(TimerService.stopwatchTime) / 100);
            return {
                icon: timerState.stopwatchRunning ? "timer" : "timer_pause",
                label: Translation.tr("Stopwatch"),
                text: text.split(".")[0],
                minor: "." + (text.split(".")[1] ?? "00"),
                remaining: -1,
                elapsed: (seconds % 60) / 60,
                paused: !timerState.stopwatchRunning,
                relaxed: false,
                cycle: 0,
                cycles: 0
            };
        }
        if (key === "pomodoro") {
            const lap = Math.max(1, TimerService.pomodoroLapDuration);
            const remaining = TimerService.pomodoroSecondsLeft / lap;
            const cycles = Math.max(1, TimerService.cyclesBeforeLongBreak);
            return {
                icon: TimerService.pomodoroBreak ? "coffee" : "self_improvement",
                label: TimerService.pomodoroLongBreak
                    ? Translation.tr("Long break")
                    : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus"),
                text: timerState.pomodoroText,
                minor: "",
                remaining: remaining,
                elapsed: 1 - remaining,
                paused: !timerState.pomodoroRunning,
                relaxed: TimerService.pomodoroBreak,
                cycle: TimerService.pomodoroCycle % cycles,
                cycles: cycles
            };
        }
        if (key === "countdown") {
            const duration = Math.max(1, Number(timerState.primaryCountdown?.durationSeconds ?? 1));
            const remaining = timerState.countdownSecondsLeft / duration;
            return {
                icon: timerState.countdownPaused ? "pause_circle" : "hourglass_top",
                label: timerState.countdownLabel,
                text: timerState.countdownText,
                minor: timerState.extraCountdownCount > 0 ? " +" + timerState.extraCountdownCount : "",
                remaining: remaining,
                elapsed: 1 - remaining,
                paused: timerState.countdownPaused,
                relaxed: false,
                cycle: 0,
                cycles: 0
            };
        }
        const window = Math.max(1, AlarmService.upcomingMinutes);
        return {
            icon: timerState.upcomingAlarm?.phone ? "phone_android" : "alarm",
            label: timerState.upcomingAlarm?.label ?? Translation.tr("Alarm"),
            text: timerState.upcomingAlarmText,
            minor: "",
            remaining: -1,
            elapsed: 1 - Math.min(1, timerState.upcomingAlarmMinutes / window),
            paused: false,
            relaxed: false,
            cycle: 0,
            cycles: 0
        };
    }

    function trigger(key: string): void {
        if (key === "stopwatch")
            TimerService.toggleStopwatch();
        else if (key === "pomodoro")
            TimerService.togglePomodoro();
        else if (key === "countdown")
            timerState.toggleCountdown();
        else if (key === "alarm")
            timerState.openUpcomingAlarm();
    }

    readonly property real flatLength: variantLoader.item?.implicitWidth ?? 0
    property real animatedLength: root.flatLength
    Behavior on animatedLength {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    visible: root.compVisible
    implicitWidth: !root.compVisible ? 0 : root.vertical ? Appearance.sizes.verticalBarWidth : root.animatedLength
    implicitHeight: !root.compVisible ? 0 : root.vertical ? root.animatedLength : Appearance.sizes.baseBarHeight

    function syncBarVisibility() {
        if (typeof rootItem !== "undefined" && rootItem?.toggleVisible)
            rootItem.toggleVisible(root.compVisible);
    }
    onCompVisibleChanged: root.syncBarVisibility()
    Component.onCompleted: root.syncBarVisibility()

    Loader {
        id: variantLoader
        anchors.centerIn: parent
        rotation: root.contentRotation
        active: root.keys.length > 0
        sourceComponent: root.variant === "fill"
            ? fillVariant
            : root.variant === "phases" ? phasesVariant : squeezeVariant
    }

    Component {
        id: squeezeVariant
        SculptTimerSqueeze {
            thickness: root.thickness
            tones: timerTones
            keys: root.keys
            entryFor: root.entryFor
            onTriggered: key => root.trigger(key)
        }
    }

    Component {
        id: fillVariant
        SculptTimerFill {
            thickness: root.thickness
            tones: timerTones
            keys: root.keys
            entryFor: root.entryFor
            onTriggered: key => root.trigger(key)
        }
    }

    Component {
        id: phasesVariant
        SculptTimerPhases {
            thickness: root.thickness
            tones: timerTones
            keys: root.keys
            entryFor: root.entryFor
            onTriggered: key => root.trigger(key)
        }
    }
}
