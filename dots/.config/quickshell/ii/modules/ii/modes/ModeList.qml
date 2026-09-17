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

    // The assistant entry: the button lives in the header, the bar it opens
    // is the slot under it. State is owned by the overlay (ModesContent),
    // which runs the agent; this pane only renders it and passes gestures.
    property bool aiVisible: true
    property string aiPhase: "idle"
    property string aiErrorText: ""
    property string aiCreatedName: ""

    signal selected(string id)
    signal createRequested()
    signal aiSubmitted(string text)
    signal aiStopRequested()
    signal aiDismissed()
    signal aiSuccessFinished()
    signal aiOpenChatRequested()

    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1

    // Bring the selected row to the middle of the list; the row can sit
    // below the fold in a long list and the reveal seam asks for it.
    function revealSelected() {
        const idx = Array.from(root.items).findIndex(x => (x?.id ?? "") === root.selectedId);
        if (idx >= 0)
            list.positionViewAtIndex(idx, ListView.Center);
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // The header and the assistant bar are one group: the bar grows and
        // folds inside it, so the column's rhythm above and below never
        // changes and the roomLeft maths below keeps counting the same
        // three real rows.
        ColumnLayout {
            id: headerGroup
            Layout.fillWidth: true
            spacing: 0

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
                    visible: root.items.length > 1 && !aiButton.visible
                    text: root.routines ? Translation.tr("Drag to reorder") : Translation.tr("Drag to set priority")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                // The assistant's seat. Open state is a colour pair, not a
                // border: the pill fills when the bar it opened is on.
                RippleButton {
                    id: aiButton
                    visible: root.aiVisible && SearchPanelRegistry.aiPolicyEnabled
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    buttonRadius: Appearance.rounding.full
                    onClicked: {
                        if (root.aiPhase === "running")
                            return;
                        // A verdict on screen: the press clears it and
                        // folds the bar; from idle, it opens the field.
                        if (root.aiPhase !== "idle") {
                            aiBar.userOpened = false;
                            root.aiDismissed();
                            return;
                        }
                        aiBar.userOpened = true;
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "auto_awesome"
                        iconSize: 18
                        fill: aiBar.expanded ? 1 : 0
                        color: aiBar.expanded
                            ? Appearance.colors.colOnTertiaryContainer
                            : Appearance.colors.colOnLayer2

                        Behavior on fill {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasized
                            }
                        }

                        Behavior on color {
                            ColorAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }
                    }

                    StyledToolTip {
                        text: Translation.tr("Create with the assistant")
                    }
                }
            }

            ModeAiBar {
                id: aiBar
                Layout.fillWidth: true
                // A tab switch rebuilds this pane mid-run; the run's phase
                // keeps the bar open across the rebuild, while the local
                // press only ever opens it.
                property bool userOpened: false
                expanded: userOpened || root.aiPhase !== "idle"
                phase: root.aiPhase
                errorText: root.aiErrorText
                createdName: root.aiCreatedName
                onPhaseChanged: {
                    if (phase === "idle")
                        aiBar.userOpened = false;
                }
                onSubmitted: text => root.aiSubmitted(text)
                onStopRequested: root.aiStopRequested()
                onDismissed: {
                    aiBar.userOpened = false;
                    root.aiDismissed();
                }
                onSuccessFinished: root.aiSuccessFinished()
                onOpenChatRequested: root.aiOpenChatRequested()
            }
        }

        // Sits above the list and gets its content height first; the list
        // fits in what is left. Capped so that the header, one list row and
        // the New button always stay inside the column.
        Loader {
            id: footerSlot

            readonly property real roomLeft: column.height - headerGroup.implicitHeight - newButton.implicitHeight
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

            contentItem: Item {
                implicitWidth: newLabelRow.implicitWidth
                implicitHeight: newLabelRow.implicitHeight

                RowLayout {
                    id: newLabelRow
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
