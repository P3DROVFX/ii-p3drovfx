import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.editMode

/**
 * Edit Mode over one dock item that is not an app: the widget becomes a
 * handle. A press that travels reorders it (the dock's own drag), one that
 * stays opens its menu, and the badge takes it off - Ctrl+Z is the confirm.
 *
 * It covers the widget whole, so nothing inside it (a play button, a tile's
 * own controls) answers while the dock is being arranged.
 */
Item {
    id: root

    property Item dockContent: null
    property Item wrapper: null
    property var itemData: null
    property int delegateIndex: -1

    readonly property bool menuShown: (root.dockContent?.editMenuOpen ?? false)
        && root.dockContent.editMenuTarget?.orderKey === root.itemData?.orderKey
    readonly property bool vertical: root.dockContent?.isVertical ?? false

    // The plate: the item reads as picked up while hovered or while its menu
    // is open. A fill, never a ring.
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: Appearance.colors.colPrimaryContainer
        opacity: root.menuShown ? 0.55 : (hover.hovered ? 0.35 : 0)

        Behavior on opacity {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        id: handle
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        property real pressCoord: 0
        property bool dragActive: false

        onPressed: event => pressCoord = root.vertical ? event.y : event.x
        onPositionChanged: event => {
            if (!pressed || !(pressedButtons & Qt.LeftButton) || !root.dockContent)
                return;
            const cur = root.vertical ? event.y : event.x;
            if (!dragActive && Math.abs(cur - pressCoord) > 5 && root.delegateIndex >= 0) {
                dragActive = true;
                root.dockContent.startItemDrag(root.delegateIndex, handle, event.x, event.y);
            }
            if (dragActive)
                root.dockContent.moveItemDrag(handle, event.x, event.y);
        }
        onReleased: event => {
            if (dragActive) {
                dragActive = false;
                root.dockContent?.endItemDrag();
                return;
            }
            root.dockContent?.openEditMenu(root.wrapper, root.itemData);
        }
        onCanceled: {
            if (!dragActive)
                return;
            dragActive = false;
            root.dockContent?.cancelDrag();
        }
    }

    EditRemoveBadge {
        anchors.top: parent.top
        anchors.right: parent.right
        z: 2
        visible: !handle.dragActive
        onClicked: root.dockContent?.dockEdit.remove(root.itemData)
    }
}
