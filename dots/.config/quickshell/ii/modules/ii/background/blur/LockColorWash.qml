import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common

Item {
    id: lockColorWashRoot
    // The lock's look on this screen (GlobalStates.lockLookFor), handed in by
    // the wallpaper that owns this treatment.
    property bool lockLook: GlobalStates.lockLookActive

    required property var sourceItem
    required property real baseScale
    required property bool lockAnimationActive
    // Set while the overview-style lock animation owns the look: the effects then
    // belong to the backing wallpaper, and the zooming plane stays clean.
    property bool suppressed: false

    Loader {
        id: colorWashLoader
        active: !lockColorWashRoot.suppressed && Config.options.lock.colorWash.enable && (lockColorWashRoot.lockLook || opacityAnim.running)
        anchors.fill: parent
        opacity: lockColorWashRoot.lockLook ? Config.options.lock.colorWash.amount : 0.0
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
