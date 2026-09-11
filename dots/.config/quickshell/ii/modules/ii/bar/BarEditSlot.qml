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
    property var barComponent: null
    // The room the drop preview has opened on either side of this widget, live
    // (BarComponent animates it on the bar's own clock). The controller reads
    // it to size the indicator: drawn at the drop's FINAL extent it sat on top
    // of the neighbour for the whole 280ms the row took to part.
    property real gapBefore: 0
    property real gapAfter: 0

    readonly property bool dragging: root.controller ? root.controller.dragSlot === root : false
    readonly property real realWidth: root.width > 0 ? root.width : (root.barComponent ? root.barComponent.width : 0)
    readonly property real realHeight: root.height > 0 ? root.height : (root.barComponent ? root.barComponent.height : 0)
    readonly property real realExtent: (root.controller && root.controller.vertical) ? root.realHeight : root.realWidth

    function sceneCentre() {
        const w = root.realWidth > 0 ? root.realWidth : 36;
        const h = root.realHeight > 0 ? root.realHeight : 36;
        return root.mapToItem(null, w / 2, h / 2);
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
        cursorShape: (root.controller && root.controller.vertical) ? Qt.SizeVerCursor : Qt.SizeHorCursor

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
            const scenePoint = root.mapToItem(null, mouse.x, mouse.y);
            if (!eater.moved) {
                if (Math.hypot(mouse.x - eater.pressX, mouse.y - eater.pressY) < 6)
                    return;
                eater.moved = true;
                root.controller.beginDrag(root, scenePoint);
            }
            if (root.dragging)
                root.controller.dragMoved(scenePoint);
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
        // Keep the action inside the widget bounds.  The previous negative
        // margin placed half of the badge in the bar's clipping edge, so the
        // top-bar and right-bar layouts could cut it against the wallpaper.
        anchors.margins: Appearance.sizes.editModeEdgeMargin / 4
        enabled: !root.dragging
        onClicked: root.controller?.removeSlot(root)
    }
}
