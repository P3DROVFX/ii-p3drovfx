pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * A column of rows that can be put in a different order by dragging one: a copy follows the
 * pointer, the others slide out of its way, and the drop reports the new order.
 *
 * The model is the count, not the list, so a row is kept across edits and looks up its own
 * data - which is what lets a form stay open on a row while it is being changed. The rows are
 * the caller's, and three lines of theirs: a handle that calls beginDrag/pointerMoved/endDrag,
 * `y: shiftFor(index)` on a Translate, and `opacity` off `dragFrom`. Everything else - the gap,
 * the floating copy, the edge scroll - lives here.
 */
Item {
    id: root

    /// How many rows there are.
    property int count: 0
    /// One row, the Repeater's delegate: it needs `required property int index`.
    property Component delegate: null
    /// The copy under the pointer, drawn above the list. It reads `dragFrom` for what to show.
    property Component ghostDelegate: null
    /// The page's flickable, scrolled when a drag nears its edge.
    property Flickable flick: null
    property real spacing: 4

    signal moved(int from, int to)
    /// A drag is starting on this row, before anything has moved.
    signal dragBegan(int index)

    implicitHeight: column.implicitHeight

    // Drag state. `dropAt` is the index the floating row would land on; rows between it and the
    // origin slide one stride to make room. Rows differ in height, so everything is measured on
    // the live geometry.
    property int dragFrom: -1
    property int dropAt: -1
    readonly property bool dragging: root.dragFrom !== -1
    /// Pointer y in this item's coordinates, refreshed on every move.
    property real pointerY: 0
    /// Where inside the row the handle was grabbed.
    property real grabOffset: 0
    readonly property real ghostHeight: ghost.item?.height ?? 0
    readonly property real stride: root.ghostHeight + root.spacing
    readonly property real ghostY: Math.max(0, Math.min(root.height - root.ghostHeight,
        root.pointerY - root.grabOffset))

    function rowAt(index: int): var {
        return repeater.itemAt(index);
    }

    function shiftFor(index: int): real {
        if (!root.dragging || root.dropAt === -1 || index === root.dragFrom)
            return 0;
        if (root.dragFrom < index && index <= root.dropAt)
            return -root.stride;
        if (root.dropAt <= index && index < root.dragFrom)
            return root.stride;
        return 0;
    }

    /// Top of the gap the floating row would drop into.
    function slotY(): real {
        const row = root.rowAt(root.dropAt);
        if (!row)
            return 0;
        if (root.dropAt <= root.dragFrom)
            return row.y;
        return row.y + row.height - root.ghostHeight;
    }

    function updateDrop() {
        // The slot is how many other rows have their middle above the ghost's middle - judged
        // on the resting layout, so the sliding rows never feed back into the decision.
        //
        // The two ends are exact ties rather than near misses: the ghost is held inside the
        // list, so dragging the top row all the way down puts its middle exactly on the bottom
        // row's middle, and never past it. Which way a tie goes therefore has to follow the
        // direction of travel - counting it below meant the last row could be reached going up
        // but never going down.
        const centre = root.ghostY + root.ghostHeight / 2;
        let slot = 0;
        for (let i = 0; i < root.count; i++) {
            if (i === root.dragFrom)
                continue;
            const row = root.rowAt(i);
            if (!row)
                continue;
            const middle = row.y + row.height / 2;
            if (i > root.dragFrom ? middle <= centre : middle < centre)
                slot++;
        }
        root.dropAt = Math.max(0, Math.min(root.count - 1, slot));
    }

    function beginDrag(index: int, grabY: real) {
        root.grabOffset = grabY;
        root.dragFrom = index;
        root.dropAt = index;
        root.dragBegan(index);
    }

    function endDrag() {
        const from = root.dragFrom;
        const to = root.dropAt;
        autoScroll.stop();
        // Clear the drag first so the slide animations are off, then commit: the rows pick up
        // their new contents straight in place.
        root.dragFrom = -1;
        root.dropAt = -1;
        if (from === -1 || to === -1 || from === to)
            return;
        root.moved(from, to);
    }

    function pointerMoved(row: Item, y: real) {
        root.pointerY = row.mapToItem(root, 0, y).y;
        root.updateDrop();
    }

    // Pointer position in the flickable's viewport, for the edge scroll.
    readonly property real flickY: root.flick ? root.mapToItem(root.flick, 0, root.pointerY).y : 0

    Timer {
        id: autoScroll
        interval: 16
        repeat: true
        running: root.dragging && root.flick !== null && root.flick.contentHeight > root.flick.height
            && (root.flickY < 40 || root.flickY > root.flick.height - 40)
        onTriggered: {
            const edge = 40;
            const f = root.flick;
            const maxY = Math.max(0, f.contentHeight - f.height);
            let step = 0;
            if (root.flickY < edge)
                step = -(edge - root.flickY) / 4;
            else if (root.flickY > f.height - edge)
                step = (root.flickY - (f.height - edge)) / 4;
            const next = Math.max(0, Math.min(maxY, f.contentY + step));
            const delta = next - f.contentY;
            if (delta === 0)
                return;
            // The pointer stays put on screen while the content moves under it, so its position
            // in the list shifts by the scroll.
            f.contentY = next;
            root.pointerY += delta;
            root.updateDrop();
        }
    }

    // The gap the floating row will drop into.
    Rectangle {
        visible: root.dragging && root.dropAt !== -1
        x: 0
        y: root.slotY()
        width: root.width
        height: root.ghostHeight
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        Behavior on y {
            enabled: root.dragging
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        spacing: root.spacing

        Repeater {
            id: repeater
            model: root.count
            delegate: root.delegate
        }
    }

    // The row under the pointer, drawn above the list and never clipped by a row's own bounds;
    // the real delegate keeps its slot, invisible.
    Loader {
        id: ghost
        z: 10
        active: root.dragging && root.ghostDelegate !== null
        x: 0
        y: root.ghostY
        width: root.width
        sourceComponent: root.ghostDelegate
    }
}
