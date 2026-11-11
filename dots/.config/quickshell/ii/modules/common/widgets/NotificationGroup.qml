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
    /** A phone live update: one notification, drawn as LiveNotificationCard. */
    readonly property bool live: notificationGroup?.live === true
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
    // A popup is born done: its entrance is the slide, and starting at false made
    // the card fade in from 0 through background's opacity Behavior.
    property bool _entranceDone: popup

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
        if (popup)
            return;
        if (entranceAnimationsEnabled)
            root.startEntrance();
        else
            root.finishEntrance();
    }

    onEntranceAnimationsEnabledChanged: {
        if (!popup && !entranceAnimationsEnabled)
            root.finishEntrance();
    }

    Component.onCompleted: {
        if (popup) {
            // The popup's motion is the slide below; the fade/scale/+50 px entrance
            // is the sidebar's (its +50 px pushed a card into the next one's slot).
            root.finishEntrance();
            root.beginPopupEntrance();
        } else if (entranceAnimationsEnabled && entranceTrigger >= 0)
            root.startEntrance();
        else
            root.finishEntrance();
    }

    // ── Popup motion ──
    // The ListView only ever places this card at its settled slot (no y
    // transitions there). What the eye sees is that slot plus a visual offset:
    //  · entrance: slides in vertically from the screen edge the popup sits on;
    //  · any later shift of the slot (a card added above or removed, a reorder,
    //    a sibling's height settling): the old→new jump replayed as an offset
    //    decaying to 0, so the resting layout can never be stale.
    readonly property var popupView: ListView.view
    readonly property bool popupFromBottom: popupView !== null
        && popupView.verticalLayoutDirection === ListView.BottomToTop
    // The slot's on-screen top: in a bottom-to-top list a new card moves the
    // others through contentY/height, not through their own y.
    readonly property real popupSlotTop: (popup && popupView)
        ? popupView.y + root.y - popupView.contentY : 0
    // How far past the edge the card starts: its own on-screen top/bottom plus a gap.
    readonly property real popupEnterDistance: {
        if (!popup || !popupView)
            return 0;
        return popupFromBottom
            ? ((popupView.parent?.height ?? 0) - popupSlotTop + root.dismissOvershoot)
            : -(popupSlotTop + root.height + root.dismissOvershoot);
    }
    property real popupEnterProgress: popup ? 0 : 1 // 0 = past the edge, 1 = at rest
    property real popupShiftOffset: 0
    property bool popupWaitingFrame: false
    property real _popupLastY: NaN
    readonly property real popupOffsetY: popup
        ? ((1 - popupEnterProgress) * popupEnterDistance + popupShiftOffset) : 0

    // Newer groups sit on top, so a card entering below slides in from behind them.
    z: popup ? 100 - Math.max(0, index) : 1
    transform: Translate { y: root.popupOffsetY }

    function beginPopupEntrance() {
        popupEnterProgress = 0;
        // The first notification maps the popup surface, which costs a few frames;
        // start once a frame with this card in it reached the screen, or the slide
        // would already be half over when it becomes visible.
        popupWaitingFrame = true;
        popupFrameFallback.restart();
    }
    function startPopupEnterAnim() {
        if (!popupWaitingFrame)
            return;
        popupWaitingFrame = false;
        popupFrameFallback.stop();
        popupEnterAnim.restart();
    }
    Connections {
        target: root.popupWaitingFrame ? root.Window.window : null
        function onFrameSwapped() { root.startPopupEnterAnim(); }
    }
    Timer {
        id: popupFrameFallback
        interval: 160
        onTriggered: root.startPopupEnterAnim()
    }
    NumberAnimation {
        id: popupEnterAnim
        target: root
        property: "popupEnterProgress"
        from: 0
        to: 1
        // Long, soft settle with a small overshoot (~3% of the travel). The
        // expressive spatial curves felt stiff and quick over an off-screen travel.
        duration: Math.round(700 * Appearance.animMultiplier)
        easing.type: Easing.OutBack
        easing.overshoot: 0.8
        onStopped: root._popupLastY = root.popupSlotTop
    }
    NumberAnimation {
        id: popupShiftAnim
        target: root
        property: "popupShiftOffset"
        to: 0
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }
    onPopupSlotTopChanged: {
        if (!popup)
            return;
        const last = _popupLastY;
        _popupLastY = popupSlotTop;
        // While entering, the distance already follows the live slot; a scroll
        // the reader drives must move the card with it, not chase it.
        if (isNaN(last) || popupWaitingFrame || popupEnterAnim.running
                || popupView.dragging || popupView.flicking || popupView._wheelScrolling)
            return;
        const delta = last - popupSlotTop;
        if (Math.abs(delta) < 0.5)
            return;
        popupShiftAnim.stop();
        popupShiftOffset += delta;
        popupShiftAnim.from = popupShiftOffset;
        popupShiftAnim.start();
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
    // Always layout scale 1.0. The popup used to be born at 0.65 and an OutBack
    // Behavior grew it to 1 the moment its entrance finished, which read as a
    // scale-in under the slide; in the sidebar a transient scale lets the next
    // group paint over this one.
    scale: 1.0

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
                // A swipe or the close button on a live card is the by-hand dismissal.
                Notifications.discardMultipleNotifications(ids, root.live);
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
        // Dismissal is horizontal only. Without this the popup's ListView steals the
        // gesture on a vertical drag and slides the card up or down before rebounding.
        preventStealing: root.popup
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
        visible: popup && !(Config.options?.appearance?.transparency?.enable ?? false)
    }
    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width
        color: root.live ? Appearance.colors.colPrimaryContainer
            : popup ? Appearance.colors.colBackgroundSurfaceContainer : Appearance.colors.colLayer2
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
        implicitHeight: (root.live ? liveCardLoader.implicitHeight : row.implicitHeight) + root.padding * (root.live ? 2.6 : 2)

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

        Loader {
            id: liveCardLoader
            active: root.live
            visible: active
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding * 1.3
            sourceComponent: LiveNotificationCard {
                notificationObject: root.notifications[0] ?? null
                zoom: root.zoom
                popup: root.popup
                onDismissRequested: root.destroyWithAnimation()
            }
        }

        RowLayout { // Left column for icon, right column for content
            id: row
            visible: !root.live
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: 10 * root.zoom

            NotificationAppIcon { // Icons
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                implicitSize: 38 * root.zoom
                image: root?.multipleNotifications ? "" : (notificationGroup?.notifications?.[0]?.image ?? "")
                appIcon: root.notificationGroup?.appIcon ?? ""
                summary: root.notificationGroup?.notifications?.[root.notificationCount - 1]?.summary ?? ""
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
                            popup: root.popup
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
