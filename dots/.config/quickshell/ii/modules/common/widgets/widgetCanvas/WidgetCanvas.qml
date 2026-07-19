import QtQuick
import qs.modules.common

MouseArea {
    id: root

    readonly property bool isWidgetCanvas: true
    property real snapLineX: -1
    property real snapLineY: -1
    property bool draggingActive: false

    Rectangle {
        id: snapLineV
        visible: root.snapLineX >= 0
        x: root.snapLineX
        width: 1.5
        height: root.height
        color: Appearance.colors.colPrimary
        z: 999
    }
    Rectangle {
        id: snapLineH
        visible: root.snapLineY >= 0
        y: root.snapLineY
        width: root.width
        height: 1.5
        color: Appearance.colors.colPrimary
        z: 999
    }
}
