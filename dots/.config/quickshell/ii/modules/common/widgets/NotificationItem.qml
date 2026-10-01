import qs
import qs.modules.common
import qs.services
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications

Item { // Notification item area
    id: root
    property var notificationObject
    property bool expanded: false
    property bool onlyNotification: false
    property real zoom: 1.0
    property real fontSize: Appearance.font.pixelSize.small * zoom
    property real padding: onlyNotification ? 0 : 8 * zoom
    property var animationSpec: Appearance.animation.elementMoveFast

    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: notificationIcon.implicitWidth + 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    /** Notifications with buttons of their own: the icon-only pair only takes the whole row when they don't. */
    readonly property bool hasActions: (notificationObject?.actions?.length ?? 0) > 0
    property var parentDragIndex: qmlParent?.dragIndex ?? -1
    property var parentDragDistance: qmlParent?.dragDistance ?? 0
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance : Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 : dragIndexDiff == 1 ? (parentDragDistance * 0.3) : dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    implicitHeight: background.implicitHeight

    function destroyWithAnimation(left = undefined) {
        if (left === undefined) {
            const pos = Config?.options.notifications.position ?? "top_right";
            if (pos.endsWith("left"))
                left = true;
            else if (pos.endsWith("right"))
                left = false;
            else
                left = false;
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
            Notifications.discardNotification(notificationObject.notificationId);
        }
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: root
        anchors.leftMargin: root.expanded ? -notificationIcon.implicitWidth : 0
        interactive: expanded
        minimumX: -Infinity
        maximumX: Infinity
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.destroyWithAnimation();
            }
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
            if (Math.abs(diffX) > root.dragConfirmThreshold) {
                root.destroyWithAnimation(diffX < 0);
            } else {
                dragManager.resetDrag();
            }
        }
    }

    NotificationAppIcon { // App icon
        id: notificationIcon
        implicitSize: 38 * root.zoom
        opacity: (!onlyNotification && (notificationObject?.image ?? "") != "" && expanded) ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.animationSpec.duration
                easing.type: root.animationSpec.type
                easing.bezierCurve: root.animationSpec.bezierCurve
            }
        }

        image: notificationObject?.image ?? ""
        anchors.right: background.left
        anchors.top: background.top
        anchors.rightMargin: 10
    }

    Rectangle { // Background of notification item
        id: background
        width: parent.width
        anchors.left: parent.left
        radius: Appearance.rounding.small * root.zoom
        anchors.leftMargin: root.xOffset

        opacity: {
            if (!dragManager.dragging)
                return 1.0;
            var u = root.width > 0 ? Math.min(1.0, Math.abs(root.xOffset) / root.width) : 0.0;
            return (1.0 - u * u * u) * (1.0 - u * u * u);
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

        color: (expanded && !onlyNotification) ? (notificationObject.urgency == NotificationUrgency.Critical) ? ColorUtils.mix(Appearance.colors.colSecondaryContainer, Appearance.colors.colLayer2, 0.35) : (Appearance.colors.colLayer3) : ColorUtils.transparentize(Appearance.colors.colLayer3)

        implicitHeight: expanded ? (contentColumn.implicitHeight + padding * 2) : summaryRow.implicitHeight

        ColumnLayout { // Content column
            id: contentColumn
            anchors.fill: parent
            anchors.margins: expanded ? root.padding : 0
            spacing: 3

            Behavior on anchors.margins {
                NumberAnimation {
                    duration: root.animationSpec.duration
                    easing.type: root.animationSpec.type
                    easing.bezierCurve: root.animationSpec.bezierCurve
                }
            }

            ColumnLayout { // Summary and collapsed body
                id: summaryRow
                visible: !root.onlyNotification || !root.expanded
                Layout.fillWidth: true
                spacing: 3
                StyledText {
                    id: summaryText
                    Layout.fillWidth: true
                    visible: !root.onlyNotification
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                    text: root.notificationObject?.summary ?? ""
                }
                StyledText {
                    id: collapsedBodyText
                    opacity: !root.expanded ? 1 : 0
                    visible: !root.expanded
                    Layout.fillWidth: true
                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.animationSpec.duration
                            easing.type: root.animationSpec.type
                            easing.bezierCurve: root.animationSpec.bezierCurve
                        }
                    }
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap // Needed for proper eliding????
                    maximumLineCount: 1
                    textFormat: Text.StyledText
                    text: {
                        if (!notificationObject) return "";
                        return NotificationUtils.processNotificationBody(notificationObject.body ?? "", notificationObject.appName || notificationObject.summary || "").replace(/\n/g, "<br/>");
                    }
                }
            }

            ColumnLayout { // Expanded content
                id: expandedContentColumn
                Layout.fillWidth: true
                opacity: root.expanded ? 1 : 0
                visible: root.expanded

                Behavior on opacity {
                    NumberAnimation {
                        duration: root.animationSpec.duration
                        easing.type: root.animationSpec.type
                        easing.bezierCurve: root.animationSpec.bezierCurve
                    }
                }

                StyledText { // Notification body (expanded)
                    id: notificationBodyText
                    Layout.fillWidth: true
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.RichText
                    text: {
                        if (!notificationObject) return "";
                        return `<style>img{max-width:${expandedContentColumn.width}px;}</style>` + `${NotificationUtils.processNotificationBody(notificationObject.body ?? "", notificationObject.appName || notificationObject.summary || "").replace(/\n/g, "<br/>")}`;
                    }

                    onLinkActivated: link => {
                        Qt.openUrlExternally(link);
                        GlobalStates.sidebarRightOpen = false;
                    }

                    PointingHandLinkHover {}
                }

                Item {
                    Layout.fillWidth: true
                    implicitWidth: actionsFlickable.implicitWidth
                    implicitHeight: actionsFlickable.implicitHeight

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: actionsFlickable.width
                            height: actionsFlickable.height
                            radius: Appearance.rounding.small * root.zoom
                        }
                    }

                    ScrollEdgeFade {
                        target: actionsFlickable
                        vertical: false
                    }

                    StyledFlickable { // Notification actions
                        id: actionsFlickable
                        anchors.fill: parent
                        implicitHeight: actionRowLayout.implicitHeight
                        contentWidth: actionRowLayout.implicitWidth

                        Behavior on opacity {
                            NumberAnimation {
                                duration: root.animationSpec.duration
                                easing.type: root.animationSpec.type
                                easing.bezierCurve: root.animationSpec.bezierCurve
                            }
                        }
                        Behavior on implicitHeight {
                            NumberAnimation {
                                duration: root.animationSpec.duration
                                easing.type: root.animationSpec.type
                                easing.bezierCurve: root.animationSpec.bezierCurve
                            }
                        }

                        RowLayout {
                            id: actionRowLayout
                            Layout.alignment: Qt.AlignBottom

                            NotificationActionButton {
                                // Square while the notification brings its own buttons, half the
                                // row when the two icon buttons are all there is.
                                Layout.fillWidth: !root.hasActions
                                buttonText: Translation.tr("Close")
                                urgency: notificationObject?.urgency ?? NotificationUrgency.Normal
                                implicitHeight: 34 * root.zoom
                                leftPadding: (root.hasActions ? 8 : 15) * root.zoom
                                rightPadding: (root.hasActions ? 8 : 15) * root.zoom
                                buttonRadius: Appearance.rounding.small * root.zoom
                                implicitWidth: root.hasActions
                                    ? implicitHeight
                                    : (actionsFlickable.width - actionRowLayout.spacing) / 2

                                onClicked: {
                                    root.destroyWithAnimation();
                                }

                                contentItem: MaterialSymbol {
                                    iconSize: Appearance.font.pixelSize.larger * root.zoom
                                    horizontalAlignment: Text.AlignHCenter
                                    color: ((notificationObject?.urgency ?? NotificationUrgency.Normal) == NotificationUrgency.Critical) ? Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                                    text: "close"
                                }
                            }

                            Repeater {
                                id: actionRepeater
                                model: notificationObject?.actions ?? []
                                NotificationActionButton {
                                    id: notifAction
                                    required property var modelData
                                    /**
                                     * An icon-only action (Open) is a square pill; the rest hug
                                     * their label instead of sharing the row equally, which is
                                     * what pushed the last one off the viewport.
                                     */
                                    readonly property bool iconOnlyAction: modelData.iconOnly === true
                                    buttonText: modelData.text
                                    iconOnly: iconOnlyAction
                                    actionIcon: modelData.icon ?? ""
                                    urgency: notificationObject?.urgency ?? NotificationUrgency.Normal
                                    implicitHeight: 34 * root.zoom
                                    leftPadding: (iconOnlyAction ? 8 : 15) * root.zoom
                                    rightPadding: (iconOnlyAction ? 8 : 15) * root.zoom
                                    buttonRadius: Appearance.rounding.small * root.zoom
                                    implicitWidth: iconOnlyAction ? implicitHeight : (contentItem.implicitWidth + leftPadding + rightPadding)
                                    onClicked: {
                                        if (modelData.identifier.startsWith("__qs_")) {
                                            Notifications.executeShellAction(notificationObject, modelData.identifier);
                                            root.destroyWithAnimation();
                                        } else {
                                            Notifications.attemptInvokeAction(notificationObject.notificationId, modelData.identifier);
                                        }
                                    }
                                }
                            }

                            NotificationActionButton {
                                // A notification that brings its own file-copy action keeps only
                                // that one: this button would sit right beside it as a second copy.
                                visible: !(notificationObject?.hasFileCopyAction ?? false)
                                Layout.fillWidth: !root.hasActions
                                urgency: notificationObject?.urgency ?? NotificationUrgency.Normal
                                implicitHeight: 34 * root.zoom
                                leftPadding: (root.hasActions ? 8 : 15) * root.zoom
                                rightPadding: (root.hasActions ? 8 : 15) * root.zoom
                                buttonRadius: Appearance.rounding.small * root.zoom
                                implicitWidth: root.hasActions
                                    ? implicitHeight
                                    : (actionsFlickable.width - actionRowLayout.spacing) / 2

                                onClicked: {
                                    Quickshell.clipboardText = notificationObject?.body ?? "";
                                    copyIcon.text = "inventory";
                                    copyIconTimer.restart();
                                }

                                Timer {
                                    id: copyIconTimer
                                    interval: 1500
                                    repeat: false
                                    onTriggered: {
                                        copyIcon.text = "content_copy";
                                    }
                                }

                                contentItem: MaterialSymbol {
                                    id: copyIcon
                                    iconSize: Appearance.font.pixelSize.larger * root.zoom
                                    horizontalAlignment: Text.AlignHCenter
                                    color: ((notificationObject?.urgency ?? NotificationUrgency.Normal) == NotificationUrgency.Critical) ? Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface
                                    text: "content_copy"
                                }

                                StyledToolTip {
                                    text: Translation.tr("Copy notification text to clipboard")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
