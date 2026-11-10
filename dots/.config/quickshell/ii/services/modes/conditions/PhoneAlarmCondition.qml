import QtQuick
import qs.services
import ".."

/**
 * Event: the phone's alarm goes off, noticed when its mirrored time passes and the
 * phone moves on to the next one (see PhoneAlarmService), or from a mirrored
 * KDE Connect notification when the phone forwards it.
 */
ModeCondition {
    id: root

    readonly property Connections link: Connections {
        target: PhoneAlarmService
        function onPhoneAlarmRang(summary) {
            root.pulse(summary);
        }
    }
}
