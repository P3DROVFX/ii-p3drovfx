import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common

Item {
    id: lockColorWashRoot

    required property var sourceItem
    required property real baseScale
    required property bool lockAnimationActive

    Loader {
        id: colorWashLoader
        active: Config.options.lock.colorWash.enable && (GlobalStates.lockLookActive || opacityAnim.running)
        anchors.fill: parent
        opacity: GlobalStates.lockLookActive ? Config.options.lock.colorWash.amount : 0.0
        Behavior on opacity {
            NumberAnimation {
                id: opacityAnim
                duration: Math.round(600 * Appearance.animMultiplier)
                easing.type: Easing.OutCubic
            }
        }
        sourceComponent: Item {
            anchors.fill: parent
            Rectangle {
                id: colorWashRect
                anchors.fill: parent
                color: Appearance.colors.colPrimary
            }
        }
    }
}
