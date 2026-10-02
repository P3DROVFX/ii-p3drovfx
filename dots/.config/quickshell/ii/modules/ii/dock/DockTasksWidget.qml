import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "./widgets"

/**
 * The open tasks of the configured provider (local, TickTick or Google
 * Tasks, through the Todo service), as a short vertical list on the dock.
 *
 * Rows are the dashboard ToDo's rows cut down to what fits a dock slot: the
 * priority container colours, the circle that completes the task, the title
 * struck through once done, and a delete button that slides in on hover.
 * Nothing is edited here - that stays in the dashboard.
 *
 * The wheel scrolls the list while it can and lets go at either end, so a
 * widget stack around it gets the next notch and turns the page.
 */
Item {
    id: root

    property bool isVertical: false
    property var dockContent: null
    property int delegateIndex: -1

    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: root.dockContent?.dotMargin ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    readonly property real slotSize: root.dockContent?.buttonSlotSize ?? (buttonSize + dotMargin * 2)
    readonly property real slotHeight: root.dockContent
        ? (root.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : (buttonSize + dotMarginV * 2)
    readonly property real fixedSlots: 3
    readonly property real fixedLength: fixedSlots * slotSize

    implicitWidth: root.isVertical ? root.slotSize : root.fixedLength
    implicitHeight: root.isVertical ? root.slotSize : root.slotHeight
    // Magnified with the icons at the muted share the dock keeps for a widget
    // body; the delegate wrapper grows the slot by exactly this much.
    readonly property real contentMagnification: root.dockContent ? root.dockContent._getSlotMagScale(root) : 1.0
    scale: root.contentMagnification
    transformOrigin: root.dockContent?.magnificationTransformOrigin ?? Item.Bottom

    readonly property real widgetRadius: (Config.options?.dock?.widgetRadius ?? -1) >= 0
        ? Config.options.dock.widgetRadius
        : (Appearance.rounding.windowRounding + 12)

    readonly property var openTasks: (Todo.list ?? []).filter(task => task && !task.done)
    readonly property int openCount: root.openTasks.length

    // ── Card ───────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.fill: parent
        anchors.leftMargin: root.dotMargin
        anchors.rightMargin: root.dotMargin
        anchors.topMargin: root.dotMarginV
        anchors.bottomMargin: root.dotMarginV
        radius: root.widgetRadius
        color: Appearance.colors.colSurfaceContainerHigh

        readonly property real inset: Math.max(4, Math.round(height * 0.11))
        // Rows sit concentric with the card corner.
        readonly property real rowRadius: Math.max(Appearance.rounding.verysmall, Math.min(radius - inset, rowHeight / 2))
        readonly property real rowSpacing: 3
        readonly property int visibleRows: Math.max(2, Math.floor((height - inset * 2 + rowSpacing) / (20 + rowSpacing)))
        readonly property real rowHeight: Math.max(16, (height - inset * 2 - rowSpacing * (visibleRows - 1)) / visibleRows)

        // Hover, wheel and the dock's drag-to-reorder live under the rows,
        // the way the media card does it: a press that travels drags the
        // whole widget, a press on a row button is the button's.
        MouseArea {
            id: dragOverlay
            anchors.fill: parent
            z: 0
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            hoverEnabled: true
            property real pressCoord: 0
            property bool dragActive: false

            onEntered: root.dockContent?.onButtonEntered(root)
            onExited: root.dockContent?.onButtonExited(root)
            onPressed: event => pressCoord = root.isVertical ? event.y : event.x
            onPositionChanged: event => {
                if (!pressed)
                    return;
                const cur = root.isVertical ? event.y : event.x;
                if (!dragActive && Math.abs(cur - pressCoord) > 5 && root.delegateIndex >= 0) {
                    dragActive = true;
                    root.dockContent?.startItemDrag(root.delegateIndex, dragOverlay, event.x, event.y);
                }
                if (dragActive)
                    root.dockContent?.moveItemDrag(dragOverlay, event.x, event.y);
            }
            onReleased: {
                if (!dragActive)
                    return;
                dragActive = false;
                root.dockContent?.endItemDrag();
            }
            onCanceled: {
                if (!dragActive)
                    return;
                dragActive = false;
                root.dockContent?.cancelDrag();
            }
            // Touchpads report many small deltas: they add up to a notch per
            // row. A delta toward an end the list cannot pass is left alone,
            // for a widget stack to turn its page with.
            property real wheelAccumulator: 0
            onWheel: wheel => {
                const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                const rows = delta > 0 ? -1 : 1;
                if (!taskList.canScroll(rows)) {
                    wheelAccumulator = 0;
                    wheel.accepted = false;
                    return;
                }
                wheel.accepted = true;
                wheelAccumulator += delta;
                if (Math.abs(wheelAccumulator) < 120)
                    return;
                wheelAccumulator = 0;
                taskList.scrollBy(rows);
            }
        }

        DockTooltip {
            parentItem: root
            text: root.openCount === 0 ? Translation.tr("No open tasks") + " · " + Todo.providerName
                : (root.openCount === 1 ? Translation.tr("1 open task") : Translation.tr("%1 open tasks").arg(root.openCount))
                    + " · " + Todo.providerName
            showTooltip: dragOverlay.containsMouse && root.isVertical
            tooltipOffset: -root.dotMargin
        }

        // ── Vertical dock: the count, nothing else fits ───────────────────
        Loader {
            active: root.isVertical
            anchors.fill: parent
            sourceComponent: Item {
                MaterialSymbol {
                    anchors.centerIn: parent
                    renderType: Text.CurveRendering
                    text: root.openCount > 0 ? "checklist" : "task_alt"
                    iconSize: Math.round(root.buttonSize * 0.42)
                    color: Appearance.colors.colOnSurface
                }
                Rectangle {
                    visible: root.openCount > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: Math.max(height, countText.implicitWidth + 8)
                    height: Math.round(root.buttonSize * 0.34)
                    radius: height / 2
                    color: Appearance.colors.colPrimary
                    StyledText {
                        id: countText
                        anchors.centerIn: parent
                        text: String(root.openCount)
                        font.pixelSize: Math.round(parent.height * 0.62)
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
        }

        // ── Horizontal dock: the list ─────────────────────────────────────
        ListView {
            id: taskList
            visible: !root.isVertical
            anchors.fill: parent
            anchors.margins: card.inset
            z: 1
            clip: true
            interactive: false
            spacing: card.rowSpacing
            boundsBehavior: Flickable.StopAtBounds
            model: root.isVertical ? [] : root.openTasks

            // One row per notch; false at either end so the wheel moves on.
            // Assigned, never bound: the view resets contentY itself when its
            // model changes, which would silently drop a binding.
            property real scrollTarget: 0
            function canScroll(rows) {
                const maxY = Math.max(0, contentHeight - height);
                return rows < 0 ? scrollTarget > 0.5 : scrollTarget < maxY - 0.5;
            }
            function scrollBy(rows) {
                const step = card.rowHeight + card.rowSpacing;
                const maxY = Math.max(0, contentHeight - height);
                const target = Math.max(0, Math.min(maxY, Math.round((scrollTarget + rows * step) / step) * step));
                if (Math.abs(target - scrollTarget) < 0.5)
                    return false;
                scrollTarget = target;
                scrollAnimation.restart();
                return true;
            }
            NumberAnimation {
                id: scrollAnimation
                target: taskList
                property: "contentY"
                to: taskList.scrollTarget
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            onCountChanged: {
                scrollAnimation.stop();
                scrollTarget = Math.max(0, Math.min(scrollTarget, contentHeight - height));
                contentY = scrollTarget;
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: taskList.width
                height: card.rowHeight

                property bool optimisticDone: false
                readonly property int taskPriority: row.modelData.priority ?? 0
                readonly property color containerColor: row.taskPriority >= 5 ? Appearance.colors.colError
                    : row.taskPriority >= 3 ? Appearance.colors.colTertiaryContainer
                    : row.taskPriority > 0 ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colSurfaceContainerHighest
                readonly property color containerHoverColor: row.taskPriority >= 5 ? Appearance.colors.colErrorHover
                    : row.taskPriority >= 3 ? Appearance.colors.colTertiaryContainerHover
                    : row.taskPriority > 0 ? Appearance.colors.colSecondaryContainerHover
                    : Appearance.colors.colSurfaceContainerHighestActive
                // Not "onContainerColor": a property named on + Capital is
                // read as a signal handler and its binding never runs.
                readonly property color contentColor: row.taskPriority >= 5 ? Appearance.colors.colOnError
                    : row.taskPriority >= 3 ? Appearance.colors.colOnTertiaryContainer
                    : row.taskPriority > 0 ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnSurface
                readonly property bool engaged: rowHover.hovered

                HoverHandler { id: rowHover }

                // The check answers at once; the task leaves the list a beat
                // later, so the completion is seen before the row goes.
                Timer {
                    id: completeTimer
                    interval: Appearance.animation.elementMoveFast.duration + 120
                    onTriggered: Todo.markDone(row.modelData)
                }

                Rectangle {
                    anchors.fill: parent
                    radius: card.rowRadius
                    color: row.engaged ? row.containerHoverColor : row.containerColor
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }

                MouseArea {
                    id: checkArea
                    anchors.left: parent.left
                    anchors.leftMargin: 2
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.height + 2
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !row.optimisticDone
                    onClicked: {
                        row.optimisticDone = true;
                        completeTimer.restart();
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.height - 4
                        height: width
                        radius: width / 2
                        color: ColorUtils.applyAlpha(row.contentColor, checkArea.pressed ? 0.2 : (checkArea.containsMouse ? 0.12 : 0))
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        renderType: Text.CurveRendering
                        text: row.optimisticDone ? "check_circle" : "radio_button_unchecked"
                        fill: row.optimisticDone ? 1 : 0
                        iconSize: Math.round(card.rowHeight * 0.82)
                        color: row.taskPriority > 0 ? row.contentColor
                            : row.optimisticDone ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                }

                StyledText {
                    anchors.left: checkArea.right
                    anchors.leftMargin: Math.max(4, Math.round(card.rowHeight * 0.3))
                    anchors.right: actionSlot.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.content ?? ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.pixelSize: Math.max(Appearance.font.pixelSize.smallest, Math.min(Appearance.font.pixelSize.smallie, Math.round(card.rowHeight * 0.6)))
                    font.weight: Font.Medium
                    font.strikeout: row.optimisticDone
                    color: row.contentColor
                    opacity: row.optimisticDone ? 0.6 : 1
                }

                // One animated extent drives the title's elision and the
                // delete button's reveal together, as in the dashboard rows.
                Item {
                    id: actionSlot
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height - 4
                    width: (height + 2) * revealProgress
                    clip: true
                    property real revealProgress: row.engaged && !row.optimisticDone ? 1 : 0
                    Behavior on revealProgress {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(actionSlot)
                    }

                    MouseArea {
                        id: deleteArea
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.height
                        height: parent.height
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: actionSlot.revealProgress > 0.5
                        opacity: actionSlot.revealProgress
                        onClicked: Todo.deleteItem(row.modelData)

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: deleteArea.pressed ? Appearance.colors.colErrorContainerActive
                                : deleteArea.containsMouse ? Appearance.colors.colErrorContainerHover
                                : Appearance.colors.colErrorContainer
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            renderType: Text.CurveRendering
                            text: "delete"
                            iconSize: Math.round(parent.height * 0.68)
                            color: Appearance.colors.colOnErrorContainer
                        }
                    }
                }
            }
        }

        // Empty state.
        Row {
            visible: !root.isVertical && root.openCount === 0
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                renderType: Text.CurveRendering
                text: "task_alt"
                iconSize: Math.round(card.height * 0.42)
                color: Appearance.colors.colPrimary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("All done")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurface
            }
        }
    }
}
