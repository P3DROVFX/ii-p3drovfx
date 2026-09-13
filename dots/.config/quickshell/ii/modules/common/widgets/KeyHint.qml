pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Row {
    id: root

    property var keys: ["Ctrl", "K"]
    property color surface: Appearance.colors.colSurfaceContainerHigh
    property color onSurface: Appearance.colors.colOnSurface
    property real pixelSize: 9

    spacing: 2

    readonly property color keyFace: ColorUtils.mix(root.surface, root.onSurface, 0.86)
    readonly property color keyText: ColorUtils.getContrastingTextColor(root.keyFace)

    Repeater {
        model: root.keys

        delegate: Rectangle {
            required property string modelData

            implicitWidth: Math.max(14, label.implicitWidth + 10)
            implicitHeight: 16
            radius: Appearance.rounding.verysmall
            color: root.keyFace

            StyledText {
                id: label
                anchors.centerIn: parent
                text: modelData
                font.pixelSize: root.pixelSize
                font.family: Appearance.font.family.main
                font.weight: Font.Bold
                color: root.keyText
            }
        }
    }
}
