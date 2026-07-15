import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * A group of notifications from the same app.
 * Similar to Android's notifications
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    property real zoom: 1.0
    property int lazyLimit: 2
    property int entranceTrigger: -1
    property int globalIndex: 0

    // Entrance animation properties
    property real _entranceOpacity: 0
    property real _entranceScale: 0.75
    property real _entranceTranslateY: 35
    property bool _entranceDone: false

    onEntranceTriggerChanged: {
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.75;
        _entranceTranslateY = 35;
        Qt.callLater(function() {
            entranceAnim.start();
        });
    }

    Component.onCompleted: {
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.75;
        _entranceTranslateY = 35;
        Qt.callLater(function() {
            entranceAnim.start();
        });
    }

    SequentialAnimation {
        id: entranceAnim
        PauseAnimation { duration: Math.min(Math.max(root.globalIndex, 0), 15) * 35 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "_entranceOpacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_entranceScale"; from: 0.75; to: 1.0; duration: 350; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "_entranceTranslateY"; from: 35; to: 0; duration: 320; easing.type: Easing.OutCubic }
        }
        PropertyAction { target: root; property: "_entranceDone"; value: true }
    }

    onExpandedChanged: {
        if (expanded) {
            lazyLimit = Math.min(8, root.notificationCount);
            if (lazyLimit < root.notificationCount) {
                lazyLoadTimer.restart();
            }
        } else {
            lazyLoadTimer.stop();
            lazyLimit = 2;
        }
    }

    Timer {
        id: lazyLoadTimer
        interval: 50
        repeat: true
        running: false
        onTriggered: {
            if (root.lazyLimit < root.notificationCount) {
                root.lazyLimit = Math.min(root.lazyLimit + 8, root.notificationCount);
            } else {
                stop();
            }
        }
    }
    property real padding: 10 * zoom
    implicitHeight: background.implicitHeight

    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 : dragIndexDiff == 1 ? (parentDragDistance * 0.3) : dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    function destroyWithAnimation(left = undefined) {
        if (left === undefined) {
            const pos = Config?.options.notifications.position ?? "top_right";
            if (pos.endsWith("left"))
                left = true;
            else if (pos.endsWith("right"))
                left = false;
            else
                left = false; // default left = false -> animate right
        }
        // Save current xOffset before breaking binding and resetting drag
        const currentX = root.xOffset;
        background.anchors.leftMargin = currentX; // Break binding
        background.opacity = background.opacity; // Break binding
        if (root.qmlParent && typeof root.qmlParent.resetDrag === "function") {
            root.qmlParent.resetDrag();
        }
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    hoverEnabled: true
    onContainsMouseChanged: {
        if (!root.popup)
            return;
        if (root.containsMouse)
            root.notifications.forEach(notif => {
                Notifications.cancelTimeout(notif.notificationId);
            });
        else
            root.notifications.forEach(notif => {
                Notifications.timeoutNotification(notif.notificationId);
            });
    }

    SequentialAnimation { // Drag finish animation
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
            root.notifications.forEach(notif => {
                Qt.callLater(() => {
                    Notifications.discardNotification(notif.notificationId);
                });
            });
        }
    }

    function toggleExpanded() {
        if (expanded)
            implicitHeightAnim.enabled = true;
        else
            implicitHeightAnim.enabled = false;
        root.expanded = !root.expanded;
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        minimumX: -Infinity
        maximumX: Infinity
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                root.destroyWithAnimation();
            else if (mouse.button === Qt.RightButton)
                root.toggleExpanded();
        }

        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else
                dragManager.resetDrag();
        }
    }

    StyledRectangularShadow {
        target: background
        visible: popup
    }
    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width
        color: popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2
        radius: Appearance.rounding.windowRounding * root.zoom
        anchors.leftMargin: root.xOffset

        opacity: {
            if (!root._entranceDone) return root._entranceOpacity;
            if (!dragManager.dragging)
                return 1.0;
            var u = root.width > 0 ? Math.min(1.0, Math.abs(root.xOffset) / root.width) : 0.0;
            return (1.0 - u * u * u) * (1.0 - u * u * u);
        }
        scale: root._entranceDone ? 1.0 : root._entranceScale
        Behavior on opacity {
            enabled: !entranceAnim.running
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        Behavior on scale {
            enabled: !entranceAnim.running
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutBack
            }
        }

        transform: Translate {
            y: root._entranceDone ? 0 : root._entranceTranslateY
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
        implicitHeight: root.expanded ? row.implicitHeight + padding * 2 : Math.min(80 * root.zoom, row.implicitHeight + padding * 2)

        Behavior on implicitHeight {
            id: implicitHeightAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout { // Left column for icon, right column for content
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: 10 * root.zoom

            NotificationAppIcon { // Icons
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                implicitSize: 38 * root.zoom
                image: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.image ?? ""
                appIcon: root.notificationGroup?.appIcon
                summary: root.notificationGroup?.notifications[root.notificationCount - 1]?.summary
                urgency: root.notifications.some(n => n.urgency === NotificationUrgency.Critical.toString()) ? NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout { // Content
                Layout.fillWidth: true
                spacing: expanded ? (root.multipleNotifications ? (notificationGroup?.notifications[root.notificationCount - 1].image != "") ? 35 : 5 : 0) : 0
                // spacing: 00
                Behavior on spacing {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item { // App name (or summary when there's only 1 notif) and time
                    id: topRow
                    // spacing: 0
                    Layout.fillWidth: true
                    property real fontSize: Appearance.font.pixelSize.smaller * root.zoom
                    property bool showAppName: root.multipleNotifications
                    implicitHeight: Math.max(topTextRow.implicitHeight, expandButton.implicitHeight)

                    RowLayout {
                        id: topTextRow
                        anchors.left: parent.left
                        anchors.right: expandButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        StyledText {
                            id: appName
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: (topRow.showAppName ? notificationGroup?.appName : notificationGroup?.notifications[0]?.summary) || ""
                            font.pixelSize: topRow.showAppName ? topRow.fontSize : Appearance.font.pixelSize.small * root.zoom
                            color: topRow.showAppName ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            id: timeText
                            // Layout.fillWidth: true
                            Layout.rightMargin: 10
                            horizontalAlignment: Text.AlignLeft
                            text: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)
                            font.pixelSize: topRow.fontSize
                            color: Appearance.colors.colSubtext
                        }
                    }
                    NotificationGroupExpandButton {
                        id: expandButton
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        count: root.notificationCount
                        expanded: root.expanded
                        zoom: root.zoom
                        fontSize: topRow.fontSize
                        iconSize: Appearance.font.pixelSize.normal * root.zoom
                        onClicked: {
                            root.toggleExpanded();
                        }
                        altAction: () => {
                            root.toggleExpanded();
                        }

                        StyledToolTip {
                            text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                        }
                    }
                }

                StyledListView { // Notification body (expanded)
                    id: notificationsColumn
                    implicitHeight: contentHeight
                    Layout.fillWidth: true
                    spacing: expanded ? 5 : 3
                    // clip: true
                    interactive: false
                    Behavior on spacing {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    model: ScriptModel {
                        values: root.notifications.slice().reverse().slice(0, root.lazyLimit)
                    }
                    delegate: NotificationItem {
                        required property int index
                        required property var modelData
                        notificationObject: modelData
                        expanded: root.expanded
                        zoom: root.zoom
                        onlyNotification: (root.notificationCount === 1)
                        opacity: (!root.expanded && index == 1 && root.notificationCount > 2) ? 0.5 : 1
                        visible: root.expanded || (index < 2)
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                    }
                }
            }
        }
    }
}
