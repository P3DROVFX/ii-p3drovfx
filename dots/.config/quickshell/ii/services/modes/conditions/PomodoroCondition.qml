import QtQuick
import qs.services
import ".."

/**
 * The Pomodoro timer is running, in a focus lap (`phase: focus`), a
 * break (`break`) or either (`any`).
 */
ModeCondition {
    id: root
    readonly property string phase: ["focus", "break", "any"].indexOf(root.params?.phase) !== -1
        ? root.params.phase : "any"

    readonly property bool phaseOk: root.phase === "any"
        || (root.phase === "break") === TimerService.pomodoroBreak

    satisfied: TimerService.pomodoroRunning && root.phaseOk
    reason: !TimerService.pomodoroRunning ? "stopped" : (TimerService.pomodoroBreak ? "break" : "focus")
}
