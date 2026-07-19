import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common

Item {
    id: lockDesatRoot

    required property var sourceItem
    required property real baseScale
    required property bool lockAnimationActive

    readonly property real targetSaturation: -Config.options.lock.desaturate.amount

    Loader {
        id: desatLoader
        active: Config.options.lock.desaturate.enable && (GlobalStates.screenLocked || desaturationAnim.running)
        anchors.fill: parent
        sourceComponent: MultiEffect {
            source: lockDesatRoot.sourceItem
            saturation: GlobalStates.screenLocked ? lockDesatRoot.targetSaturation : 0.0
            Behavior on saturation {
                NumberAnimation {
                    id: desaturationAnim
                    duration: Math.round(600 * Appearance.animMultiplier)
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
