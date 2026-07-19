import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF

Item {
    id: windowBlurRoot

    required property var sourceItem
    required property bool hasWindowsInActiveWorkspace
    required property bool overviewOpen

    readonly property bool shouldBlur: Config.options.background.blurWhenWindowsOpen && hasWindowsInActiveWorkspace && !GlobalStates.screenLocked && !overviewOpen

    MultiEffect {
        id: windowBlurEffect
        anchors.fill: parent

        visible: windowBlurRoot.shouldBlur || opacity > 0.01
        opacity: windowBlurRoot.shouldBlur ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
        }

        source: (windowBlurRoot.shouldBlur || opacity > 0.01) ? windowBlurRoot.sourceItem : null
        blurEnabled: true
        blurMax: 64
        blur: Config.options.background.blurWhenWindowsOpenRadius / 100.0

        Rectangle {
            anchors.fill: parent
            color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
        }
    }
}
