pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

MaterialShape {
    id: root

    property real iconSize: implicitSize * 0.52
    property color iconColor: Appearance.colors.colOnPrimaryContainer

    shape: MaterialShape.Shape.Cookie7Sided
    color: Appearance.colors.colPrimaryContainer

    CustomIcon {
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: "discord.svg"
        iconFolder: Qt.resolvedUrl("assets")
        colorize: true
        color: root.iconColor
    }
}
