import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The small "take this off" badge Edit Mode pins to a bar widget or a dock
 * app: a click is the whole gesture, nothing to confirm - Ctrl+Z is the
 * confirmation.
 */
Rectangle {
    id: root

    signal clicked()

    width: 16
    height: 16
    radius: 8
    color: Appearance.m3colors.m3error

    MaterialSymbol {
        anchors.centerIn: parent
        text: "close"
        iconSize: 12
        color: Appearance.m3colors.m3onError
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
