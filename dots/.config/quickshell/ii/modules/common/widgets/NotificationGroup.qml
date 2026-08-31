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
    readonly property var expansionAnimationSpec: popup
        ? Appearance.animation.elementMoveFast
        : Appearance.animation.elementMove
    property bool expansionTransitionActive: false
    // Keep only the latest collapsed preview; the count button still exposes
    // the full group and expansion reveals the remaining notifications.
    property int lazyLimit: 1
    property int entranceTrigger: -1
    property bool entranceAnimationsEnabled: false
    property int globalIndex: 0

    // Entrance animation properties
    property real _entranceOpacity: 0
    property real _entranceScale: 0.65
    property real _entranceTranslateY: 50
    property bool _entranceDone: false

    function finishEntrance() {
        entranceAnim.stop();
        _entranceDone = true;
        _entranceOpacity = 1;
        _entranceScale = 1;
        _entranceTranslateY = 0;
    }

    function startEntrance() {
        _entranceDone = false;
        _entranceOpacity = 0;
        _entranceScale = 0.65;
        _entranceTranslateY = 50;
        Qt.callLater(function() {
            if (root.popup || root.entranceAnimationsEnabled)
                entranceAnim.start();
        });
    }

    onEntranceTriggerChanged: {
        if (popup || entranceAnimationsEnabled)
            root.startEntrance();
        else
            root.finishEntrance();
    }

    onEntranceAnimationsEnabledChanged: {
        if (!popup && !entranceAnimationsEnabled)
            root.finishEntrance();
    }

    Component.onCompleted: {
        if (popup || (entranceAnimationsEnabled && entranceTrigger >= 0))
            root.startEntrance();
        else
            root.finishEntrance();
    }

    SequentialAnimation {
        id: entranceAnim
        PauseAnimation {
            duration: Math.round(Appearance.animation.elementMove.duration
                * (0.35 + Math.min(Math.max(root.globalIndex, 0), 15) * 0.15))
        }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "_entranceOpacity"; from: 0; to: 1
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
            NumberAnimation {
                target: root; property: "_entranceScale"; from: 0.65; to: 1
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
            NumberAnimation {
                target: root; property: "_entranceTranslateY"; from: 50; to: 0
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
            }
        }
        PropertyAction { target: root; property: "_entranceDone"; value: true }
    }

    onExpandedChanged: {
        if (expanded) {
            // The sidebar needs one stable final height for its group motion.
            // Popup groups keep batched creation to protect their short-lived
            // surface from a large synchronous delegate burst.
            lazyLimit = root.popup
                ? Math.min(8, root.notificationCount)
                : root.notificationCount;
            if (root.popup && lazyLimit < root.notificationCount) {
                lazyLoadTimer.restart();
            }
        } else {
            lazyLoadTimer.stop();
            lazyLimit = 1;
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
    // Popup groups may use the scale entrance animation. Sidebar groups must stay
    // at layout scale 1.0: their parent ListView owns the delegate geometry, and
    // a transient scale there can make the next group paint over this one.
    scale: popup ? (_entranceDone ? 1.0 : _entranceScale) : 1.0
    Behavior on scale {
        enabled: popup && !entranceAnim.running
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutBack
            easing.overshoot: 0.8
        }
    }

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
            const ids = root.notifications.map(n => n.notificationId);
            if (ids.length > 0) {
                Notifications.discardMultipleNotifications(ids);
            }
        }
    }

    function toggleExpanded() {
        root.expansionTransitionActive = true;
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
        scale: 1.0
        // Fix: translateY only for popup. In sidebar the +50px shift pushed the card
        // into the next item's ListView slot causing visible overlap.
        transform: Translate {
            y: (root._entranceDone || !root.popup) ? 0 : root._entranceTranslateY
        }

        Behavior on opacity {
            enabled: !entranceAnim.running
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
        // Reserve the height of every visible preview; expanded groups grow with
        // the full Column + Repeater body as lazy loading adds more delegates.
        implicitHeight: row.implicitHeight + root.padding * 2

        Behavior on implicitHeight {
            // Only animate implicitHeight when manually expanding/collapsing.
            // When NOT expanded, new notifications arriving can cause row.implicitHeight
            // to momentarily resolve to a lower value (before layout settles), triggering
            // this Behavior and animating the card to a wrong intermediate height — which
            // desynchronizes the outer ListView's item positions, producing the overlap look.
            enabled: root.expansionTransitionActive
            NumberAnimation {
                duration: root.expansionAnimationSpec.duration
                easing.type: root.expansionAnimationSpec.type
                easing.bezierCurve: root.expansionAnimationSpec.bezierCurve
                onFinished: root.expansionTransitionActive = false
            }
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
                    NumberAnimation {
                        duration: root.expansionAnimationSpec.duration
                        easing.type: root.expansionAnimationSpec.type
                        easing.bezierCurve: root.expansionAnimationSpec.bezierCurve
                    }
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

                        RippleButton {
                            id: muteButton
                            readonly property bool muted: Notifications.appSoundsMuted(notificationGroup?.appName)

                            visible: root.expanded
                            Layout.rightMargin: 5
                            implicitWidth: implicitHeight
                            implicitHeight: expandButton.implicitHeight
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            onClicked: Notifications.toggleAppSoundMute(notificationGroup?.appName)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: muteButton.muted ? "notifications_off" : "notifications_active"
                                iconSize: Appearance.font.pixelSize.normal * root.zoom
                                color: Appearance.colors.colSubtext
                            }

                            StyledToolTip {
                                text: muteButton.muted ? Translation.tr("Unmute this app's notification sounds") : Translation.tr("Mute this app's notification sounds")
                            }
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
                        animationSpec: root.expansionAnimationSpec
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

                Column { // Notification body (expanded)
                    id: notificationsColumn
                    Layout.fillWidth: true
                    spacing: expanded ? 5 : 3

                    // This content is not independently scrollable: the outer
                    // notification center owns scrolling. Using a nested ListView
                    // here made implicitHeight depend on its estimated contentHeight;
                    // during rapid model updates it could report one delegate while
                    // two were already painted, so the outer ListView placed the next
                    // group too early. A positioner derives its height directly from
                    // the delegates and keeps both layout levels synchronized.
                    property int dragIndex: -1
                    property real dragDistance: 0

                    function resetDrag() {
                        dragIndex = -1;
                        dragDistance = 0;
                    }

                    Behavior on spacing {
                        NumberAnimation {
                            duration: root.expansionAnimationSpec.duration
                            easing.type: root.expansionAnimationSpec.type
                            easing.bezierCurve: root.expansionAnimationSpec.bezierCurve
                        }
                    }

                    Repeater {
                        model: ScriptModel {
                            values: root.notifications.slice().reverse().slice(0, root.lazyLimit)
                        }
                        delegate: NotificationItem {
                            required property int index
                            required property var modelData
                            width: notificationsColumn.width
                            height: implicitHeight
                            qmlParent: notificationsColumn
                            notificationObject: modelData
                            expanded: root.expanded
                            animationSpec: root.expansionAnimationSpec
                            zoom: root.zoom
                            onlyNotification: (root.notificationCount === 1)
                            visible: root.expanded || (index < 1)
                        }
                    }
                }
            }
        }
    }
}
