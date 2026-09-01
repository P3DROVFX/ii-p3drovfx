pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The actions of a mode or routine, one ActionRow each, in the order the
 * engine runs them. Rows can be dragged by their handle; DragOrderList
 * does the moving and reports the new order. Rows are kept across edits
 * (the model is the count, each row looks up its own action) so an
 * unfolded form stays open while it is being changed.
 */
DragOrderList {
    id: root

    required property var actions
    /// "" for a mode; "while" / "once" when the rows belong to a routine.
    property string routineKind: ""
    property string ownerId: ""

    signal changed(int index, var action)
    signal removeRequested(int index)

    count: root.actions?.length ?? 0

    // An unfolded form would be dragged around at its full height, and the
    // gap it leaves is measured on the row.
    onDragBegan: index => {
        const row = root.rowAt(index);
        if (row)
            row.expanded = false;
    }

    delegate: ActionRow {
        id: row
        required property int index

        Layout.fillWidth: true
        action: root.actions[row.index] ?? ({})
        routineKind: root.routineKind
        ownerId: root.ownerId
        draggable: root.count > 1
        hidden: root.dragFrom === row.index
        onChanged: a => root.changed(row.index, a)
        onRemoveRequested: root.removeRequested(row.index)

        transform: Translate {
            y: root.shiftFor(row.index)

            Behavior on y {
                enabled: root.dragging
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        onDragStarted: y => {
            root.pointerY = row.mapToItem(root, 0, y).y;
            root.beginDrag(row.index, y);
        }
        onDragMoved: y => root.pointerMoved(row, y)
        onDragEnded: root.endDrag()
    }

    ghostDelegate: Item {
        implicitHeight: ghostRow.implicitHeight

        StyledRectangularShadow {
            target: ghostRow
        }

        ActionRow {
            id: ghostRow
            anchors {
                left: parent.left
                right: parent.right
            }
            action: root.actions[root.dragFrom] ?? ({})
            routineKind: root.routineKind
            ownerId: root.ownerId
            draggable: true
            ghost: true
            enabled: false
            scale: 1.01
        }
    }
}
