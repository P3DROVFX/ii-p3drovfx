import QtQuick

import qs.modules.common
import qs.modules.ii.notes

/// A divider. The one block with nothing to type in, so it is selected rather than
/// focused: clicking it arms a Backspace that removes it.
Item {
    id: root

    property var editor: null
    property var block: null
    property int blockIndex: 0

    implicitHeight: NotesMetrics.paperLineHeight

    Rectangle {
        anchors.centerIn: parent
        width: parent.width - NotesMetrics.readingPadding * 2
        height: 2
        radius: 1
        color: area.containsMouse
            ? Appearance.colors.colOnLayer1
            : Appearance.colors.colOnLayer1Inactive

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.editor.removeBlock(root.block.id)
    }
}
