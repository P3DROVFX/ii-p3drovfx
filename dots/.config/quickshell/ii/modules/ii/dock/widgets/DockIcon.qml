import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: root
    property string appId: ""
    property bool isRunning: true
    property real iconOpacity: isRunning ? 1.0 : (Config.options.dock.dimInactiveIcons ? 0.55 : 1.0)

    IconImage {
        id: baseIcon
        anchors.fill: parent
        source: Quickshell.iconPath(TaskbarApps.getCachedIcon(root.appId), "image-missing")
        visible: !Config.options.dock.monochromeIcons
        opacity: root.iconOpacity

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    Desaturate {
        anchors.fill: parent
        source: baseIcon
        desaturation: 0.8
        visible: !root.isRunning && !Config.options.dock.monochromeIcons && Config.options.dock.dimInactiveIcons
        opacity: baseIcon.opacity
    }

    Loader {
        active: Config.options.dock.monochromeIcons
        anchors.fill: parent
        sourceComponent: Item {
            Desaturate {
                id: monoDesat
                anchors.fill: parent
                source: baseIcon
                desaturation: 0.8
                visible: false
            }
            ColorOverlay {
                anchors.fill: parent
                source: monoDesat
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
            }
        }
    }
}
