pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

/**
 * A group of remote (KDE Connect / Android) notifications from the same app.
 * Mirrors the visual design and interactions of `NotificationGroup.qml` from
 * the dashboard:
 *   - Collapsed: shows the latest notification's summary + body preview,
 *     plus a count badge when more than one notification exists.
 *   - Expanded: renders all notifications as `RemoteNotificationItem`
 *     children in a StyledListView.
 *   - Swipe-to-dismiss: horizontal drag past threshold dismisses the entire
 *     group (sends `cancel` to every notification on the phone).
 *   - `preventStealing: true` is set on the DragManager so the horizontal
 *     drag doesn't get intercepted by the parent SwipeView (tab navigation
 *     of SidebarPolicies). Vertical scrolling of the list still works via
 *     mouse wheel / trackpad.
 */
Item {
    id: root

    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property real padding: 10
    property int groupPosition: 0 // 0: single, 1: top, 2: middle, 3: bottom
    property bool isFirstInGroup: groupPosition === 0 || groupPosition === 1
    property bool isLastInGroup: groupPosition === 0 || groupPosition === 3

    readonly property real outerRadius: Appearance.rounding.large ?? 23
    readonly property real innerRadius: Appearance.rounding.verysmall ?? 4

    onExpandedChanged: {
        if (expanded) {
            lazyLimit = Math.min(8, root.notificationCount)
            if (lazyLimit < root.notificationCount) {
                lazyLoadTimer.restart()
            }
        } else {
            lazyLoadTimer.stop()
            lazyLimit = 2
        }
    }

    Timer {
        id: lazyLoadTimer
        interval: 50
        repeat: true
        running: false
        onTriggered: {
            if (root.lazyLimit < root.notificationCount) {
                root.lazyLimit = Math.min(root.lazyLimit + 8, root.notificationCount)
            } else {
                stop()
            }
        }
    }

    readonly property bool _validGroup: root.notificationGroup !== null
                                        && root.notificationGroup !== undefined
                                        && Array.isArray(root.notifications)

    implicitHeight: _validGroup ? background.implicitHeight : 0
    visible: _validGroup
    opacity: _validGroup ? 1.0 : 0.0

    Behavior on opacity {
        // NOTE: previously this had `enabled: _validGroup`. That was a bug:
        // when `_validGroup` flipped from true→false (the group lost its
        // last notification), the behavior was *disabled*, so opacity
        // snapped to 0 instantly instead of fading out. The remaining
        // groups in the ListView had no time to play removeDisplaced —
        // the delegate vanished and the neighbors jumped into place.
        // Removing the `enabled` flag lets the fade-out animation play,
        // giving the ListView the visual time needed to slide neighbors.
        NumberAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    property real dragConfirmThreshold: 70
    property real dismissOvershoot: 20
    property var qmlParent: root?.parent?.parent
    property var parentDragIndex: qmlParent?.dragIndex ?? -1
    property var parentDragDistance: qmlParent?.dragDistance ?? 0
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff === 0 ? parentDragDistance :
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff === 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff === 2 ? (parentDragDistance * 0.1) : 0

    // Tracks whether a real drag occurred during the press-release cycle.
    // DragManager.onClicked fires even after a slow/below-threshold drag,
    // which would trigger scrcpy launch on what the user intended as a
    // swipe-to-dismiss. We set this flag in onDraggingChanged when `dragging`
    // becomes true (mouse moved enough to start a drag), and suppress the
    // next click if the flag is set.
    property bool _wasDragged: false

    function destroyWithAnimation(left = undefined) {
        if (left === undefined) {
            left = false
        }
        // Save current xOffset before breaking binding and resetting drag
        const currentX = root.xOffset
        background.anchors.leftMargin = currentX // Break binding
        background.opacity = background.opacity // Break binding
        root.qmlParent?.resetDrag?.()
        destroyAnimation.left = left
        destroyAnimation.running = true
    }

    function toggleExpanded() {
        root.expanded = !root.expanded
    }

    function dismissAllOnPhone() {
        root.notifications.forEach(notif => {
            KdeConnectService.discardNotification(notif.publicId)
        })
    }

    SequentialAnimation {
        id: destroyAnimation
        property bool left: true
        running: false
        ParallelAnimation {
            NumberAnimation {
                target: background.anchors
                property: "leftMargin"
                to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
            NumberAnimation {
                target: background
                property: "opacity"
                to: 0.0
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
        onFinished: () => {
            root.dismissAllOnPhone()
        }
    }

    DragManager {
        id: dragManager
        anchors.fill: parent
        interactive: !root.expanded
        preventStealing: true
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: mouse => {
            if (root._wasDragged) {
                root._wasDragged = false
                return
            }
            if (mouse.button === Qt.MiddleButton)
                root.destroyWithAnimation()
            else if (mouse.button === Qt.RightButton)
                root.toggleExpanded()
            else if (mouse.button === Qt.LeftButton) {
                const latest = root.notifications[0]
                if (latest && latest.publicId) {
                    KdeConnectService.openNotificationIntent(latest.publicId)
                }
            }
        }
        onDraggingChanged: () => {
            if (dragging) {
                root._wasDragged = true
                root.qmlParent.dragIndex = root.index ?? root.parent?.children?.indexOf(root) ?? -1
            }
        }
        onDragDiffXChanged: () => {
            if (root.qmlParent)
                root.qmlParent.dragDistance = dragDiffX
        }
        onDragReleased: (diffX, diffY) => {
            // Keep _wasDragged=true so the upcoming onClicked (which fires
            // right after onDragReleased) is suppressed.
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0)
            else
                dragManager.resetDrag()
        }
    }

    Rectangle {
        id: background
        anchors.left: parent.left
        width: parent.width
        color: hoverHandler.hovered && !dragManager.dragging
               ? Appearance.colors.colLayer3Hover
               : Appearance.colors.colLayer3
        
        readonly property real activeDragDistance: dragIndexDiff === 0 ? parentDragDistance : (parentDragIndex >= 0 ? parentDragDistance * 0.4 : 0)
        readonly property real dragRatio: Math.min(1.0, Math.abs(activeDragDistance) / Math.max(1, root.dragConfirmThreshold))
        readonly property real swipePillRadius: root.innerRadius + (root.outerRadius - root.innerRadius) * dragRatio

        topLeftRadius: (activeDragDistance < 0 || (dragIndexDiff === 1 && activeDragDistance !== 0))
                       ? swipePillRadius
                       : (root.isFirstInGroup ? root.outerRadius : root.innerRadius)
        topRightRadius: (activeDragDistance > 0 || (dragIndexDiff === 1 && activeDragDistance !== 0))
                        ? swipePillRadius
                        : (root.isFirstInGroup ? root.outerRadius : root.innerRadius)
        bottomLeftRadius: (activeDragDistance < 0 || (dragIndexDiff === 1 && activeDragDistance !== 0))
                          ? swipePillRadius
                          : (root.isLastInGroup ? root.outerRadius : root.innerRadius)
        bottomRightRadius: (activeDragDistance > 0 || (dragIndexDiff === 1 && activeDragDistance !== 0))
                           ? swipePillRadius
                           : (root.isLastInGroup ? root.outerRadius : root.innerRadius)

        Behavior on topLeftRadius { NumberAnimation { duration: dragManager.dragging ? 50 : 250; easing.type: Easing.OutCubic } }
        Behavior on topRightRadius { NumberAnimation { duration: dragManager.dragging ? 50 : 250; easing.type: Easing.OutCubic } }
        Behavior on bottomLeftRadius { NumberAnimation { duration: dragManager.dragging ? 50 : 250; easing.type: Easing.OutCubic } }
        Behavior on bottomRightRadius { NumberAnimation { duration: dragManager.dragging ? 50 : 250; easing.type: Easing.OutCubic } }

        anchors.leftMargin: root.xOffset

        HoverHandler {
            id: hoverHandler
        }

        // Subtle tactile feedback: lighter press, no visible change while dragging.
        scale: dragManager.dragging ? 1.0 : (dragManager.pressed ? 0.993 : 1.0)
        Behavior on scale {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        opacity: {
            if (!dragManager.dragging) return 1.0
            const u = root.width > 0 ? Math.min(1.0, Math.abs(root.xOffset) / root.width) : 0.0
            return (1.0 - u * u * u) * (1.0 - u * u * u)
        }
        Behavior on opacity {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        clip: true
        // When collapsed, show up to 2 notification previews. Each preview
        // needs ~36px (summaryRow height), so 2 previews + padding ≈ 92px.
        // The old limit of 80px was too small, causing the previews to be
        // clipped/scaled down and look "smaller".
        // The minimum of 82px ensures single-notification groups (e.g. Bluelink)
        // match the height of multi-notification groups visually, rather than
        // appearing smaller just because they have less body text.
        implicitHeight: root.expanded ? row.implicitHeight + root.padding * 2
            : Math.max(58, Math.min(120, row.implicitHeight + root.padding * 2))

        Behavior on implicitHeight {
            id: implicitHeightAnim
            enabled: true
            NumberAnimation {
                duration: 380
                easing.type: Easing.OutQuart
            }
        }

        RowLayout {
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: 10

            NotificationAppIcon {
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                visible: !(root.expanded && root.multipleNotifications)
                appIcon: root.notificationGroup?.appIcon || ""
                summary: root.notificationGroup?.appName || ""
                color: Appearance.colors.colSurfaceContainerHighest
            }

            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 80
                Layout.preferredHeight: 45
                visible: !root.expanded && !root.multipleNotifications && (root.notifications[0]?.image || "") !== ""
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colSurfaceContainerHighest

                Image {
                    id: groupThumbImage
                    anchors.fill: parent
                    source: visible ? (root.notifications[0]?.image || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: groupThumbImage.width
                            height: groupThumbImage.height
                            radius: Appearance.rounding.verysmall
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.expanded && root.multipleNotifications ? 5 : 0

                Behavior on spacing {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: expandedGroupHeader
                    Layout.fillWidth: true
                    visible: root.expanded && root.multipleNotifications
                    implicitHeight: visible ? 28 : 0

                    RowLayout {
                        anchors.fill: parent
                        spacing: 6

                        NotificationAppIcon {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: false
                            appIcon: root.notificationGroup?.appIcon || ""
                            summary: root.notificationGroup?.appName || ""
                            color: Appearance.colors.colSurfaceContainerHighest
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: root.notificationGroup?.appName || ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer3
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: {
                                KdeConnectService._timeTick
                                return NotificationUtils.getFriendlyNotifTimeString(
                                    root.notificationGroup?.time ?? 0)
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.35)
                        }

                        NotificationGroupExpandButton {
                            Layout.alignment: Qt.AlignVCenter
                            count: root.notificationCount
                            expanded: root.expanded
                            fontSize: Appearance.font.pixelSize.smaller
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colRipple: Appearance.colors.colLayer2Active
                            onClicked: root.toggleExpanded()
                            altAction: () => root.toggleExpanded()
                            contentItem: Item {
                                anchors.centerIn: parent
                                implicitWidth: expandedContentRow.implicitWidth
                                RowLayout {
                                    id: expandedContentRow
                                    anchors.centerIn: parent
                                    spacing: 3
                                    StyledText {
                                        Layout.leftMargin: 4
                                        text: root.notificationCount
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colOnLayer3
                                    }
                                    MaterialSymbol {
                                        text: "keyboard_arrow_down"
                                        iconSize: 16
                                        color: Appearance.colors.colOnLayer3
                                        rotation: root.expanded ? 180 : 0
                                        Behavior on rotation {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    id: topRow
                    Layout.fillWidth: true
                    visible: !(root.expanded && root.multipleNotifications)
                    property real fontSize: Appearance.font.pixelSize.smaller
                    implicitHeight: visible ? Math.max(topTextRow.implicitHeight, expandButton.implicitHeight) : 0

                    RowLayout {
                        id: topTextRow
                        anchors.left: parent.left
                        anchors.right: expandButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        StyledText {
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: root.multipleNotifications
                                ? (root.notificationGroup?.appName || "")
                                : (root.notifications[0]?.summary || "")
                            font.pixelSize: root.multipleNotifications
                                ? topRow.fontSize
                                : Appearance.font.pixelSize.small
                            color: root.multipleNotifications
                                 ? ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.35)
                                 : Appearance.colors.colOnLayer3
                        }

                        StyledText {
                            horizontalAlignment: Text.AlignLeft
                            Layout.rightMargin: 10
                            // Include _timeTick in the expression so the
                            // binding re-evaluates every 30s, updating the
                            // relative time string ("Now" → "1m" → "5m" → "1h").
                            // Without this, the timestamp would be computed
                            // once and never change.
                            text: {
                                KdeConnectService._timeTick
                                return NotificationUtils.getFriendlyNotifTimeString(
                                    root.notificationGroup?.time ?? 0)
                            }
                            font.pixelSize: topRow.fontSize
                            color: ColorUtils.transparentize(Appearance.colors.colOnLayer3, 0.35)
                        }
                    }

                    NotificationGroupExpandButton {
                        id: expandButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        count: root.notificationCount
                        expanded: root.expanded
                        fontSize: topRow.fontSize
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active
                        onClicked: root.toggleExpanded()
                        altAction: () => root.toggleExpanded()
                        contentItem: Item {
                            anchors.centerIn: parent
                            implicitWidth: contentRow.implicitWidth
                            RowLayout {
                                id: contentRow
                                anchors.centerIn: parent
                                spacing: 3 * expandButton.zoom
                                StyledText {
                                    Layout.leftMargin: 4 * expandButton.zoom
                                    visible: root.count > 1
                                    text: root.count
                                    font.pixelSize: expandButton.fontSize
                                    color: Appearance.colors.colOnLayer3
                                }
                                MaterialSymbol {
                                    text: "keyboard_arrow_down"
                                    iconSize: expandButton.iconSize
                                    color: Appearance.colors.colOnLayer3
                                    rotation: expanded ? 180 : 0
                                    Behavior on rotation {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }
                            }
                        }
                        StyledToolTip {
                            text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                        }
                    }
                }

                // Using a plain Column + Repeater instead of StyledListView
                // because this list is non-interactive (no scrolling, no
                // flick). ListView has heavy delegate-management overhead
                // (contentHeight calculation, lazy instantiation queue,
                // flick physics) that is unnecessary here. With
                // `implicitHeight: contentHeight` ListView was forced to
                // instantiate ALL delegates just to measure total height —
                // for a 2-item collapsed preview this wastes cycles on every
                // scroll of the outer list. Column eagerly creates children
                // but is far cheaper per-item.
                //
                // NOTE: Do NOT add `move:` or `add:` Transition to this
                // Column. The `move: Transition` fires every time the
                // notification model syncs (which generates new JS objects
                // via `_normaliseNotifications` even for unchanged content).
                // With llvmpipe software rendering, each animation frame
                // requires CPU-intensive software rendering → 380% CPU.
                // Without the Transition, items reposition instantly (no
                // When collapsed, notifications form a stacked preview (latest on top, previous behind/below).
                // Using an Item with absolute positioning when collapsed prevents Column layout overflow/overlap bugs.
                Item {
                    id: notifChildContainer
                    Layout.fillWidth: true
                    implicitHeight: root.expanded ? notifChildColumn.implicitHeight : (childRepeater.count > 1 ? 44 : (notifChildColumn.children[0]?.implicitHeight ?? 36))

                    Column {
                        id: notifChildColumn
                        width: parent.width
                        visible: root.expanded
                        spacing: 5

                        Repeater {
                            id: childRepeaterExpanded
                            model: root.expanded ? root.notifications.slice().reverse().slice(0, root.lazyLimit) : []
                            delegate: Column {
                                id: childWrapperExp
                                required property int index
                                required property var modelData
                                width: notifChildColumn.width

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    visible: childWrapperExp.index > 0
                                    color: ColorUtils.transparentize(Appearance.colors.colOnSecondaryContainer, 0.88)
                                }

                                RemoteNotificationItem {
                                    width: parent.width
                                    modelData: childWrapperExp.modelData
                                    expanded: true
                                    onlyNotification: root.notificationCount === 1
                                    itemPosition: {
                                        const count = childRepeaterExpanded.count
                                        if (count <= 1) return 0
                                        if (childWrapperExp.index === 0) return 1
                                        if (childWrapperExp.index === count - 1) return 3
                                        return 2
                                    }
                                }
                            }
                        }
                    }

                    // Collapsed preview stacked layout (max 2 items)
                    Column {
                        id: notifChildColumnCollapsed
                        width: parent.width
                        visible: !root.expanded
                        spacing: 2

                        Repeater {
                            id: childRepeater
                            model: !root.expanded ? root.notifications.slice().reverse().slice(0, Math.min(2, root.notifications.length)) : []
                            delegate: RemoteNotificationItem {
                                required property int index
                                required property var modelData
                                width: notifChildColumnCollapsed.width
                                expanded: false
                                onlyNotification: root.notificationCount === 1
                                opacity: index === 1 ? 0.55 : 1.0
                            }
                        }
                    }
                }
            }
        }
    }
}
