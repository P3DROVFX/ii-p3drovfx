import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF

Item {
    id: lockBlurRoot

    required property var sourceItem
    required property real baseScale
    required property bool lockAnimationActive

    Loader {
        id: blurLoader
        active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || opacityAnim.running)
        anchors.fill: parent
        opacity: GlobalStates.screenLocked ? 1.0 : 0.0
        Behavior on opacity {
            SequentialAnimation {
                id: opacityAnim
                PauseAnimation { duration: GlobalStates.screenLocked ? Math.round(150 * Appearance.animMultiplier) : 0 }
                NumberAnimation {
                    duration: Math.round(350 * Appearance.animMultiplier)
                    easing.type: Easing.OutCubic
                }
            }
        }
        sourceComponent: MultiEffect {
            source: lockBlurRoot.sourceItem
            blurEnabled: true
            blurMax: 64
            blur: Math.min(Config.options.lock.blur.radius / 4, 24) / 64

            Rectangle {
                opacity: 1.0
                anchors.fill: parent
                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
            }
        }
    }
}
