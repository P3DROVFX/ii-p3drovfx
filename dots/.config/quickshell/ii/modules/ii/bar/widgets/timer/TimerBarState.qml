pragma ComponentBehavior: Bound

import QtQml
import qs.modules.common
import qs.services
import "TimerBarLogic.js" as TimerBarLogic

/**
 * Shared presentation state for every Timer bar style.
 *
 * Countdowns are owned by TimerService and may be created by the dashboard,
 * Search, calendar, or another integration.  The bar deliberately picks the
 * unfinished countdown that ends first: when several timers exist, the next
 * deadline is the one that belongs in the constrained bar surface.
 */
QtObject {
    id: root

    readonly property bool pomodoroRunning: TimerService.pomodoroRunning ?? false
    readonly property bool stopwatchRunning: TimerService.stopwatchRunning ?? false
    readonly property bool hasStopwatch: root.stopwatchRunning || TimerService.stopwatchTime > 0
    readonly property bool hasPomodoro: TimerService.pomodoroSecondsLeft > 0
        && (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration
            || root.pomodoroRunning)

    readonly property bool showPomodoro: Config.options.bar.timers.showPomodoro
    readonly property bool showStopwatch: Config.options.bar.timers.showStopwatch
    readonly property bool showCountdowns: Config.options.bar.timers.showCountdowns ?? true

    // Reading the shared tick makes the sort and remaining-time text reactive
    // without creating one Timer per visual host.
    readonly property int countdownTick: TimerService.countdownTick ?? 0
    readonly property var activeCountdowns: {
        root.countdownTick;
        return TimerBarLogic.prioritizedCountdowns(
            TimerService.countdowns,
            countdown => TimerService.countdownSecondsLeft(countdown)
        );
    }
    readonly property var primaryCountdown: root.activeCountdowns[0] ?? null
    readonly property int countdownCount: root.activeCountdowns.length
    readonly property int extraCountdownCount: Math.max(0, root.countdownCount - 1)
    readonly property bool hasCountdown: root.primaryCountdown !== null
    readonly property bool countdownPaused: root.primaryCountdown?.paused ?? false
    readonly property int countdownSecondsLeft: {
        root.countdownTick;
        return root.primaryCountdown
            ? TimerService.countdownSecondsLeft(root.primaryCountdown)
            : 0;
    }

    readonly property bool visible: (root.showStopwatch && root.hasStopwatch)
        || (root.showPomodoro && root.hasPomodoro)
        || (root.showCountdowns && root.hasCountdown)

    readonly property string stopwatchText: root.formatStopwatch(TimerService.stopwatchTime)
    readonly property string pomodoroText: root.formatClock(TimerService.pomodoroSecondsLeft)
    readonly property string countdownText: root.formatCountdown(
        root.countdownSecondsLeft,
        Number(root.primaryCountdown?.durationSeconds ?? 0)
    )
    readonly property string countdownLabel: String(
        root.primaryCountdown?.label ?? Translation.tr("Timer")
    )
    readonly property string countdownTooltip: root.extraCountdownCount > 0
        ? root.countdownLabel + " · "
            + Translation.tr("%1 more").arg(String(root.extraCountdownCount))
        : root.countdownLabel

    function formatClock(seconds) {
        return TimerBarLogic.formatClock(seconds);
    }

    function formatStopwatch(time) {
        return TimerBarLogic.formatStopwatch(time);
    }

    function formatCountdown(seconds, originalDuration) {
        return TimerBarLogic.formatCountdown(seconds, originalDuration);
    }

    function toggleCountdown() {
        if (root.primaryCountdown)
            TimerService.toggleCountdown(root.primaryCountdown.id);
    }
}
