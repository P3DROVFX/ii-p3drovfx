pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/** A pomodoro or a stopwatch is running. */
ContinuousSource {
    id: source

    activityId: "timer"
    condition: TimerService.pomodoroRunning || TimerService.stopwatchRunning
    readonly property string kind: TimerService.pomodoroRunning ? "pomodoro" : "stopwatch"
    payload: source.kind

    // Switching between the two while one is running is a different thing to show.
    onKindChanged: if (source.active) source.revision += 1
}
