import qs
import qs.modules.common
import QtQuick

/**
 * One lock island item's Edit Mode affordances, parented into the item over
 * the Lockscreen tab's preview: an input eater that gives the slot the move
 * cursor without touching a binding below, the reorder gesture, and the
 * remove badge.
 *
 * The badge is the same one the bar and the dock carry, and it is here because
 * its absence was the lock screen's one asymmetry: everything else in the mode
 * could be taken off where it was drawn, and a lock island could only be moved.
 * It writes `lock.islands.hidden` through Config, which records the history
 * entry; the catalogue's Lock screen page lists what is hidden and puts it
 * back. Only the two side islands carry one (lock_islands.js's `hideable`):
 * the main island is the authentication control.
 */
Item {
    id: root

    property var controller: null
    property string island: ""
    property int renderedIndex: -1
    property Item target: null
    property string itemId: ""
    property bool hideable: false

    parent: root.target
    anchors.fill: parent
    z: 100

    readonly property bool dragging: root.controller ? root.controller.dragSlot === root : false

    function slotVisible() {
        return root.target ? root.target.visible : false;
    }

    function sceneCentre() {
        return root.mapToItem(null, root.width / 2, root.height / 2);
    }

    Component.onCompleted: if (root.controller) root.controller.registerSlot(root)
    Component.onDestruction: if (root.controller) root.controller.unregisterSlot(root)

    MouseArea {
        id: eater
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeAllCursor

        property real pressX: 0
        property real pressY: 0
        property bool moved: false

        onWheel: wheel => wheel.accepted = true
        onPressed: mouse => {
            eater.pressX = mouse.x;
            eater.pressY = mouse.y;
            eater.moved = false;
        }
        onPositionChanged: mouse => {
            if (!eater.pressed || !root.controller)
                return;
            if (!eater.moved) {
                if (Math.hypot(mouse.x - eater.pressX, mouse.y - eater.pressY) < 6)
                    return;
                eater.moved = true;
                root.controller.beginDrag(root);
            }
            if (root.dragging)
                root.controller.dragMoved(root.mapToItem(null, mouse.x, mouse.y));
        }
        onReleased: {
            if (root.controller && eater.moved)
                root.controller.drop();
        }
    }

    EditRemoveBadge {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: -3
        visible: root.hideable && !root.dragging && root.itemId !== ""
        onClicked: Config.setLockIslandHidden(root.itemId, true)
    }
}
