import QtQuick
import qs
import ".."

/**
 * Event: an alarm from the clock widget starts ringing.
 */
ModeCondition {
    id: root
    readonly property bool ringing: GlobalStates.alarmRinging
    onRingingChanged: {
        if (root.ringing)
            root.pulse("alarm");
    }
}
