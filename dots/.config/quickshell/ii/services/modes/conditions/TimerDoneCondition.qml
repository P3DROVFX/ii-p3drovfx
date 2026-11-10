import QtQuick
import qs.services
import ".."

/**
 * Event: a countdown timer reaches zero.
 */
ModeCondition {
    id: root

    readonly property Connections link: Connections {
        target: TimerService
        function onCountdownFinished(countdown) {
            root.pulse(String(countdown?.label ?? "timer"));
        }
    }
}
