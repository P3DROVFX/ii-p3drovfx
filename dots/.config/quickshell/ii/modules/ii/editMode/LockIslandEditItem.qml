import qs
import QtQuick

/**
 * One lock island item's Edit Mode affordances, parented into the item over
 * the Lockscreen tab's preview: an input eater that gives the slot the move
 * cursor without touching a binding below, and the reorder gesture. No
 * remove badge - islands hide through the lock.* switches. Every store write
 * goes through the islands' controller.
 */
Item {
    id: root

    property var controller: null
    property string island: ""
    property int renderedIndex: -1
    property Item target: null

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
}
