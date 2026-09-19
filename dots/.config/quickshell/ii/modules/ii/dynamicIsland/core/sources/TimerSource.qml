pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/** A pomodoro, a stopwatch or a countdown is running. */
ContinuousSource {
    id: source

    activityId: "timer"

    /** A countdown still ticking; a paused or already-announced one is not activity. */
    readonly property bool countdownRunning: Array.from(TimerService.countdowns ?? [])
        .some(countdown => countdown && !countdown.notified && !countdown.paused)

    condition: TimerService.pomodoroRunning || TimerService.stopwatchRunning || source.countdownRunning
    readonly property string kind: TimerService.pomodoroRunning ? "pomodoro"
        : (source.countdownRunning ? "countdown" : "stopwatch")
    payload: source.kind

    // Switching between them while one is running is a different thing to show.
    onKindChanged: if (source.active) source.revision += 1
}
