pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The left pane: every mode in priority order — or, with `routines`, every
 * routine. Order matters for modes (among automatic starts the first whose
 * conditions hold wins), so rows can be dragged by their handle. While
 * dragging, a copy of the row follows the pointer, the others slide out of
 * its way, and the drop commits the new order to the engine.
 */
Rectangle {
    id: root

    property string selectedId: ""
    property bool routines: false
    /// Optional block between the list and the New button (the templates).
    property alias footer: footerSlot.sourceComponent
    readonly property alias footerItem: footerSlot.item

    readonly property var items: root.routines ? Modes.routines : Modes.modes

    signal selected(string id)
    signal createRequested()

    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        RowLayout {
            id: header
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 4
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: root.routines ? Translation.tr("Routines") : Translation.tr("Modes")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                visible: root.items.length > 1
                text: root.routines ? Translation.tr("Drag to reorder") : Translation.tr("Drag to set priority")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // Sits above the list and gets its content height first; the list
        // fits in what is left. Capped so that the header, one list row and
        // the New button always stay inside the column.
        Loader {
            id: footerSlot

            readonly property real roomLeft: column.height - header.implicitHeight - newButton.implicitHeight
                - (root.items.length > 0 ? list.rowStride : 0) - 3 * column.spacing

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.maximumHeight: item ? item.implicitHeight : 0
            Layout.minimumHeight: item ? Math.max(0, Math.min(item.implicitHeight, item.minimumHeight ?? 0, roomLeft)) : 0
            visible: sourceComponent !== null && sourceComponent !== undefined
        }

        StyledListView {
            id: list

            // Takes whatever the slot above leaves: asks for its content,
            // gives way down to a single row, and scrolls past that.
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: contentHeight
            Layout.minimumHeight: Math.min(contentHeight, list.rowStride)
            visible: root.items.length > 0
            clip: true
            spacing: 4
            popin: false
            animateAppearance: false
            animatePopulate: false
            model: root.items

            readonly property real rowHeight: 62
            readonly property real rowStride: rowHeight + list.spacing

            // Drag state. `dropAt` is the slot the floating row would take;
            // rows between it and the origin slide one stride to make room.
            property int dragFrom: -1
            property int dropAt: -1
            /// The definition being dragged; the ghost reads it, not the list.
            property var dragMode: null
            readonly property bool dragging: dragFrom !== -1
            /// Pointer y in list coordinates, refreshed on every move.
            property real pointerY: 0
            /// Where inside the row the handle was grabbed.
            property real grabOffset: 0
            readonly property real ghostY: Math.max(0, Math.min(list.height - list.rowHeight, pointerY - grabOffset))

            function shiftFor(index) {
                if (!list.dragging || list.dropAt === -1 || index === list.dragFrom)
                    return 0;
                if (list.dragFrom < index && index <= list.dropAt)
                    return -list.rowStride;
                if (list.dropAt <= index && index < list.dragFrom)
                    return list.rowStride;
                return 0;
            }

            function updateDrop() {
                const slot = Math.round((list.ghostY + list.contentY) / list.rowStride);
                list.dropAt = Math.max(0, Math.min(list.count - 1, slot));
            }

            function beginDrag(index, grabY) {
                list.grabOffset = grabY;
                list.dragMode = root.items[index];
                list.dragFrom = index;
                list.dropAt = index;
            }

            function endDrag() {
                const from = list.dragFrom;
                const to = list.dropAt;
                const id = list.dragMode?.id ?? "";
                autoScroll.stop();
                // Clear the drag first so the slide animations are off, then
                // commit: the model is replaced synchronously and the rows are
                // rebuilt straight in their new slots.
                list.dragFrom = -1;
                list.dropAt = -1;
                if (from === -1 || to === -1 || from === to || !id.length)
                    return;
                if (root.routines)
                    Modes.moveRoutine(id, to);
                else
                    Modes.moveMode(id, to);
            }

            // Drag near an edge and the list scrolls, so long lists can be
            // reordered end to end without dropping halfway.
            Timer {
                id: autoScroll
                interval: 16
                repeat: true
                running: list.dragging && list.contentHeight > list.height
                    && (list.pointerY < 40 || list.pointerY > list.height - 40)
                onTriggered: {
                    const edge = 40;
                    const maxY = Math.max(0, list.contentHeight - list.height);
                    let step = 0;
                    if (list.pointerY < edge)
                        step = -(edge - list.pointerY) / 4;
                    else if (list.pointerY > list.height - edge)
                        step = (list.pointerY - (list.height - edge)) / 4;
                    const next = Math.max(0, Math.min(maxY, list.contentY + step));
                    if (next === list.contentY)
                        return;
                    list.contentY = next;
                    list.updateDrop();
                }
            }

            // The slot the floating row will drop into.
            Rectangle {
                z: -1
                visible: list.dragging && list.dropAt !== -1
                x: 0
                y: list.dropAt * list.rowStride
                width: list.width
                height: list.rowHeight
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colOutlineVariant

                Behavior on y {
                    enabled: list.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            delegate: ModeListRow {
                id: row

                required property var modelData
                required property int index

                width: list.width
                mode: modelData
                routine: root.routines
                selected: modelData.id === root.selectedId
                hidden: list.dragFrom === index
                onClicked: root.selected(modelData.id)

                transform: Translate {
                    id: slide
                    y: list.shiftFor(row.index)

                    Behavior on y {
                        enabled: list.dragging
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                onDragStarted: y => {
                    list.pointerY = row.mapToItem(list, 0, y).y;
                    list.beginDrag(row.index, y);
                }
                onDragMoved: y => {
                    list.pointerY = row.mapToItem(list, 0, y).y;
                    list.updateDrop();
                }
                onDragEnded: list.endDrag()
            }
        }

        // Keeps the New button at the bottom while there is nothing to list.
        Item {
            Layout.fillHeight: true
            visible: root.items.length === 0
        }

        RippleButton {
            id: newButton
            Layout.fillWidth: true
            implicitHeight: 44
            buttonRadius: Appearance.rounding.normal
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: root.createRequested()

            contentItem: RowLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    text: "add"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer2
                }

                StyledText {
                    text: root.routines ? Translation.tr("New routine") : Translation.tr("New mode")
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    // The row under the pointer, drawn above the list so it is not clipped
    // and keeps its look while the real delegate is hidden.
    Loader {
        id: ghost
        z: 10
        active: list.dragging && list.dragMode !== null
        x: column.x + list.x
        y: column.y + list.y + list.ghostY
        width: list.width

        sourceComponent: ModeListRow {
            mode: list.dragMode
            routine: root.routines
            selected: (list.dragMode?.id ?? "") === root.selectedId
            ghost: true
            enabled: false
            scale: 1.02
        }
    }
}
