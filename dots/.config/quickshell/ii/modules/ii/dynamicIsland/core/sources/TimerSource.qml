pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.ii.bar.widgets.timer

/** A pomodoro, a stopwatch or a countdown is running, or an alarm is coming up. */
ContinuousSource {
    id: source

    activityId: "timer"

    /** A countdown still ticking; a paused or already-announced one is not activity. */
    readonly property bool countdownRunning: Array.from(TimerService.countdowns ?? [])
        .some(countdown => countdown && !countdown.notified && !countdown.paused)

    /** The next alarm within the "show the next alarm" window (this PC's or the phone's). */
    readonly property TimerBarState barState: TimerBarState {}
    readonly property bool alarmSoon: source.barState.hasUpcomingAlarm

    condition: TimerService.pomodoroRunning || TimerService.stopwatchRunning || source.countdownRunning || source.alarmSoon
    readonly property string kind: TimerService.pomodoroRunning ? "pomodoro"
        : (source.countdownRunning ? "countdown" : (TimerService.stopwatchRunning ? "stopwatch" : "alarm"))
    payload: source.kind

    // Switching between them while one is running is a different thing to show.
    onKindChanged: if (source.active) source.revision += 1
}
