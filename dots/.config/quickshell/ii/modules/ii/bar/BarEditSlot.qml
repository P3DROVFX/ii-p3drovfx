import qs
import qs.modules.common
import qs.modules.ii.editMode
import QtQuick

/**
 * One bar widget's Edit Mode affordances, loaded over the widget while the
 * mode is on: an input eater that makes the widget inert without touching a
 * binding in it, the reorder gesture, the right-click menu and the remove
 * badge. Every store write goes through the bar's controller.
 */
Item {
    id: root

    property var controller: null
    property int bucket: 0
    property int storedIndex: -1
    property string widgetId: ""

    readonly property bool dragging: root.controller ? root.controller.dragSlot === root : false

    function sceneCentre() {
        return root.mapToItem(null, root.width / 2, root.height / 2);
    }

    Component.onCompleted: if (root.controller) root.controller.registerSlot(root)
    Component.onDestruction: {
        GlobalStates.clearEditBarHover(root);
        if (root.controller)
            root.controller.unregisterSlot(root);
    }

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

        // Wheel is its own channel: unhandled, it reaches the widget below.
        onWheel: wheel => wheel.accepted = true
        onPressed: mouse => {
            GlobalStates.closeEditBarMenu();
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
        onReleased: mouse => {
            if (!root.controller)
                return;
            if (eater.moved) {
                root.controller.drop();
                return;
            }
            if (mouse.button === Qt.RightButton)
                root.controller.openMenu(root, root.mapToItem(null, mouse.x, mouse.y));
        }

        // Naming what is under the pointer. The label itself belongs to the
        // chrome; all that happens here is saying which widget it is.
        onContainsMouseChanged: {
            if (!root.controller)
                return;
            if (eater.containsMouse)
                root.controller.showHoverName(root);
            else
                root.controller.clearHoverName(root);
        }
    }

    EditRemoveBadge {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: -3
        visible: !root.dragging
        onClicked: root.controller?.removeSlot(root)
    }
}
