import QtQuick
import qs.modules.common

QtObject {
    id: root

    required property string mode
    property real launcherContentWidth: 0
    property real launcherContentHeight: 0
    property real screenWidth: 1920
    property real screenHeight: 1080

    readonly property int maxHeight: Math.round(screenHeight * 0.7)

    readonly property bool isLauncher: mode === "launcher"

    readonly property real targetW: {
        return Math.max(0, launcherContentWidth)
    }

    readonly property real targetH: {
        if (launcherContentHeight <= 0) return 0
        return Math.min(maxHeight, launcherContentHeight)
    }
}
