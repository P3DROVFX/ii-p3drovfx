import QtQuick

import qs.modules.common

/**
 * The seam between two panes, and the handle for moving it.
 *
 * There is nothing drawn here at rest. The panes are already separated by a gap, and a
 * visible bar in it would be a divider — which this app does not use. What the seam gets
 * instead is a cursor: hovering it says the boundary can be moved, which is the only
 * announcement a splitter actually needs.
 *
 * The grip is wider than the gap it sits in. A 12px target is a target people miss, and
 * the extra width overlaps the pane corners, which are rounded and empty anyway.
 */
Item {
    id: root

    /// Pixels added to the pane on the left as the handle is dragged right.
    signal moved(real delta)

    /// Whether the seam can be dragged. A collapsed rail keeps the gap but not the handle:
    /// there is no width there to negotiate.
    property bool resizable: true

    implicitWidth: NotesMetrics.paneGap

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.leftMargin: -5
        anchors.rightMargin: -5
        enabled: root.resizable
        visible: root.resizable
        hoverEnabled: true
        cursorShape: Qt.SizeHorCursor

        property real lastX: 0

        onPressed: mouse => area.lastX = mouse.x
        onPositionChanged: mouse => {
            if (!area.pressed)
                return;
            // Reported against this item, which moves with the layout as the panes resize:
            // the delta has to be taken against the press position, or the handle chases
            // its own movement and the drag accelerates.
            root.moved(mouse.x - area.lastX);
        }
    }

    // A hint, not a rule: it fades in under the pointer and is gone again on the way out.
    Rectangle {
        anchors.centerIn: parent
        width: 3
        height: Math.min(parent.height * 0.18, 56)
        // Half the width, not the `full` token: 9999 on a 3px-wide rectangle pinches it
        // into two blobs instead of drawing a capsule.
        radius: width / 2
        color: Appearance.colors.colOutline
        opacity: area.containsMouse || area.pressed ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
}
