import QtQuick

/**
 * The press of an Edit Mode catalogue entry: a click, or a drag that carries
 * the entry out of the panel. `activated()` is emitted only for a release that
 * was NOT a drag. Rows and cards share it so the gesture lives in one place.
 *
 * `preventStealing` only while the entry carries something: a static entry
 * must let the list's own flick through.
 */
MouseArea {
    id: root

    property bool draggable: false
    property Flickable dragOwner: null
    property real dragThreshold: 5
    property bool dragActive: false

    property real _pressX: 0
    property real _pressY: 0

    signal activated()
    signal dragBegan()
    signal dragMovedTo(real sceneX, real sceneY)
    signal dragFinished(real sceneX, real sceneY)
    signal dragCancelled()

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    preventStealing: root.draggable

    function _scene(mouse) {
        return root.mapToItem(null, mouse.x, mouse.y);
    }

    function _release() {
        root.dragActive = false;
        if (root.dragOwner)
            root.dragOwner.interactive = true;
    }

    onPressed: mouse => {
        root._pressX = mouse.x;
        root._pressY = mouse.y;
        root.dragActive = false;
    }
    onPositionChanged: mouse => {
        if (!root.pressed || !root.draggable)
            return;
        if (!root.dragActive
                && Math.abs(mouse.x - root._pressX) < root.dragThreshold
                && Math.abs(mouse.y - root._pressY) < root.dragThreshold)
            return;
        if (!root.dragActive) {
            root.dragActive = true;
            if (root.dragOwner)
                root.dragOwner.interactive = false;
            root.dragBegan();
        }
        const p = root._scene(mouse);
        root.dragMovedTo(p.x, p.y);
    }
    onReleased: mouse => {
        const wasDrag = root.dragActive;
        root._release();
        if (!wasDrag) {
            root.activated();
            return;
        }
        const p = root._scene(mouse);
        root.dragFinished(p.x, p.y);
    }
    onCanceled: {
        if (!root.dragActive)
            return;
        root._release();
        root.dragCancelled();
    }
}
