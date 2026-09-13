import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The counterpart to EditRemoveBadge: the "put this one on" badge Edit Mode
 * pins to a dock app that is only open, not kept. A click is the whole
 * gesture, and Ctrl+Z is the confirmation.
 */
Rectangle {
    id: root

    signal clicked()

    width: 16
    height: 16
    radius: 8
    color: Appearance.colors.colPrimary

    MaterialSymbol {
        anchors.centerIn: parent
        text: "add"
        iconSize: 12
        color: Appearance.colors.colOnPrimary
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
