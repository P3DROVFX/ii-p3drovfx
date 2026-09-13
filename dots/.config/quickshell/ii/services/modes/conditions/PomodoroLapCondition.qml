import QtQuick
import qs.services
import ".."

/**
 * Event: a Pomodoro lap ends — a focus lap turning into a break
 * (`lap: focusEnd`), a break turning into focus (`breakEnd`), or either.
 */
ModeCondition {
    id: root
    readonly property string lap: ["focusEnd", "breakEnd", "any"].indexOf(root.params?.lap) !== -1
        ? root.params.lap : "any"
    readonly property bool onBreak: TimerService.pomodoroBreak
    readonly property bool running: TimerService.pomodoroRunning

    onOnBreakChanged: {
        if (!root.running)
            return;
        const ended = root.onBreak ? "focusEnd" : "breakEnd";
        if (root.lap === "any" || root.lap === ended)
            root.pulse(root.onBreak ? "focus lap ended" : "break ended");
    }
}
