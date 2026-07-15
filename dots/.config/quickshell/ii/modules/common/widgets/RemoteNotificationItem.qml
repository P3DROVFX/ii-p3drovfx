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
 * Single remote (KDE Connect / Android) notification card.
 *
 * This is a CHILD item rendered inside `RemoteNotificationGroup`. It owns a
 * DragManager that is only active when the group is expanded — this mirrors
 * the dashboard pattern where `NotificationGroup` handles swipe when
 * collapsed and `NotificationItem` handles swipe when expanded.
 *
 * Visual design mirrors `NotificationItem.qml` from the dashboard:
 *   - Collapsed (inside a group, not expanded): shows summary + body
 *     preview in a single line.
 *   - Expanded: shows the full body text, action buttons (dismiss, copy),
 *     and an inline reply box when the notification supports replies.
 *
 * The action buttons (Close / Copy) and reply row are hidden by default
 * and only appear when the parent group is expanded — matching how the
 * dashboard's `NotificationItem` shows actions only in `expanded` mode.
 */
Item {
    id: root

    property bool expanded: false
    property bool onlyNotification: false
    property real fontSize: Appearance.font.pixelSize.small
    property real padding: onlyNotification ? 0 : 8
    property real summaryElideRatio: 0.85

    property real dragConfirmThreshold: 70
    property real dismissOvershoot: 20
    property var qmlParent: root?.parent?.parent
    property var parentDragIndex: qmlParent?.dragIndex ?? -1
    property var parentDragDistance: qmlParent?.dragDistance ?? 0
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff === 0 ? parentDragDistance : Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 : dragIndexDiff === 1 ? (parentDragDistance * 0.3) : dragIndexDiff === 2 ? (parentDragDistance * 0.1) : 0

    // Suppresses onClicked after a real drag (see RemoteNotificationGroup
    // for the same fix). The DragManager fires onClicked even after a
    // below-threshold drag, which would launch the phone app via ADB when
    // the user actually intended a swipe-to-dismiss on an expanded card.
    property bool _wasDragged: false

    implicitHeight: background.implicitHeight
    opacity: 1.0
    scale: 1.0

    Behavior on opacity {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutBack
            easing.overshoot: 1.35
        }
    }

    readonly property string publicId: modelData?.publicId ?? ""
    readonly property bool dismissable: modelData?.dismissable !== false
    readonly property bool hasReply: (modelData?.replyId ?? "").length > 0
    readonly property var actions: modelData?.actions ?? []
    readonly property bool hasActions: actions.length > 0
    // Package name extracted from internalId by the Python scripts.
    // Used by openNotificationIntent() to launch the app via ADB.
    readonly property string packageName: modelData?.package ?? ""
    readonly property bool hasPackage: packageName.length > 0

    property string replyDraft: ""
    property bool replyJustSent: false

    function destroyWithAnimation(left = undefined) {
        if (left === undefined)
            left = false;
        // Save current xOffset before breaking binding and resetting drag
        const currentX = root.xOffset;
        background.anchors.leftMargin = currentX; // Break binding
        background.opacity = background.opacity; // Break binding
        root.qmlParent?.resetDrag?.();
        destroyAnimation.left = left;
        destroyAnimation.running = true;
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
            KdeConnectService.discardNotification(root.publicId);
        }
    }

    DragManager {
        id: dragManager
        anchors.fill: parent
        interactive: root.expanded
        preventStealing: true
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        minimumX: -Infinity
        maximumX: Infinity
        onClicked: mouse => {
            // Suppress click if a drag actually happened during this press
            // cycle — without this, a slow swipe-to-dismiss on an expanded
            // notification would launch the phone app via ADB.
            if (root._wasDragged) {
                root._wasDragged = false;
                return;
            }
            if (mouse.button === Qt.MiddleButton) {
                root.destroyWithAnimation();
                return;
            }
            // Left-click opens the app on the phone via ADB. This works
            // even without an intent — we extract the package from the
            // internalId and use `adb shell monkey -p <pkg>` to launch it.
            if (mouse.button === Qt.LeftButton) {
                KdeConnectService.openNotificationIntent(root.publicId);
            }
        }
        onDraggingChanged: () => {
            if (dragging) {
                root._wasDragged = true;
                root.qmlParent.dragIndex = root.index ?? -1;
            }
        }
        onDragDiffXChanged: () => {
            if (root.qmlParent)
                root.qmlParent.dragDistance = dragDiffX;
        }
        onDragReleased: (diffX, diffY) => {
            if (!root.dismissable) {
                dragManager.resetDrag();
                return;
            }
            // Keep _wasDragged=true so the upcoming onClicked is suppressed.
            if (Math.abs(diffX) > dragConfirmThreshold) {
                root.destroyWithAnimation(diffX < 0);
            } else {
                dragManager.resetDrag();
            }
        }
    }

    TextMetrics {
        id: summaryTextMetrics
        font.pixelSize: root.fontSize
        text: root.modelData?.summary || root.modelData?.appName || Translation.tr("Notification")
    }

    Rectangle {
        id: background
        width: parent.width
        anchors.left: parent.left
        anchors.leftMargin: root.xOffset
        radius: Appearance.rounding.small

        color: (root.expanded && !root.onlyNotification) ? Appearance.colors.colLayer3 : ColorUtils.transparentize(Appearance.colors.colLayer3)

        // Subtle hover/press feedback; suppressed during drag.
        scale: dragManager.dragging ? 1.0 : (dragManager.pressed ? 0.992 : 1.0)
        Behavior on scale {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutQuad
            }
        }

        border.width: 1
        border.color: dragManager.containsMouse && !dragManager.dragging ? ColorUtils.transparentize(Appearance.colors.colOutline, 0.6) : "transparent"
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        opacity: {
            if (!dragManager.dragging)
                return 1.0;
            const u = root.width > 0 ? Math.min(1.0, Math.abs(root.xOffset) / root.width) : 0.0;
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

        implicitHeight: root.expanded ? (contentColumn.implicitHeight + root.padding * 2) : summaryRow.implicitHeight

        Behavior on implicitHeight {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        clip: true

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: root.expanded ? root.padding : 0
            spacing: 3

            Behavior on anchors.margins {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: summaryRow
                visible: !root.onlyNotification || !root.expanded
                Layout.fillWidth: true
                implicitHeight: summaryText.implicitHeight

                StyledText {
                    id: summaryText
                    Layout.fillWidth: true
                    visible: !root.onlyNotification
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colOnLayer3
                    elide: Text.ElideRight
                    text: root.modelData?.summary || root.modelData?.appName || Translation.tr("Notification")
                }

                StyledText {
                    opacity: !root.expanded ? 1 : 0
                    visible: opacity > 0
                    Layout.fillWidth: true
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    maximumLineCount: 1
                    textFormat: Text.StyledText
                    text: NotificationUtils.processNotificationBody(root.modelData?.body || "", root.modelData?.appName || "").replace(/\n/g, " ")
                }
            }

            ColumnLayout {
                id: expandedContentColumn
                Layout.fillWidth: true
                opacity: root.expanded ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: root.fontSize
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.RichText
                    text: {
                        const body = NotificationUtils.processNotificationBody(root.modelData?.body || "", root.modelData?.appName || "").replace(/\n/g, "<br/>");
                        return `<style>img{max-width:${expandedContentColumn.width}px;}</style>${body}`;
                    }

                    onLinkActivated: link => {
                        Qt.openUrlExternally(link);
                        // Phone lives in the left sidebar (Policies), not the
                        // right sidebar, so close the correct panel.
                        GlobalStates.policiesPanelOpen = false;
                    }

                    PointingHandLinkHover {}
                }

                Item {
                    Layout.fillWidth: true
                    implicitWidth: actionsFlickable.implicitWidth
                    implicitHeight: actionsFlickable.implicitHeight
                    visible: root.expanded

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: actionsFlickable.width
                            height: actionsFlickable.height
                            radius: Appearance.rounding.small
                        }
                    }

                    ScrollEdgeFade {
                        target: actionsFlickable
                        vertical: false
                        // Only render the side fades when the actions row
                        // actually overflows horizontally — otherwise the
                        // right-side gradient bleeds into the card edge.
                        visible: actionsFlickable.contentWidth > actionsFlickable.width + 2
                        opacity: visible ? 1 : 0
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }

                    StyledFlickable {
                        id: actionsFlickable
                        anchors.fill: parent
                        implicitHeight: actionColumn.implicitHeight
                        contentWidth: actionColumn.implicitWidth

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on height {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on implicitHeight {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        ColumnLayout {
                            id: actionColumn
                            spacing: 6
                            width: actionsFlickable.width

                            RowLayout {
                                width: parent.width
                                spacing: 6
                                visible: root.hasActions

                                Repeater {
                                    model: root.actions
                                    delegate: RippleButton {
                                        id: notifAction
                                        required property var modelData
                                        readonly property string _label: modelData?.label ?? ""
                                        Layout.fillWidth: true
                                        implicitHeight: 34
                                        leftPadding: 15
                                        rightPadding: 15
                                        buttonRadius: Appearance.rounding.small
                                        colBackground: Appearance.colors.colLayer4
                                        colBackgroundHover: Appearance.colors.colLayer4Hover
                                        buttonText: _label
                                        contentItem: StyledText {
                                            text: notifAction._label
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer4
                                        }
                                        onClicked: {
                                            KdeConnectService.sendAction(KdeConnectService.activeDeviceId, root.publicId, modelData.key);
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                width: parent.width
                                visible: root.hasReply
                                spacing: 6

                                Rectangle {
                                    id: replyBg
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colLayer4
                                    border.width: replyField.activeFocus ? 2 : 1
                                    border.color: replyField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                                    Behavior on border.color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                    Behavior on border.width {
                                        NumberAnimation {
                                            duration: Appearance.animation.elementMoveFast.duration
                                            easing.type: Appearance.animation.elementMoveFast.type
                                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                        }
                                    }

                                    StyledTextInput {
                                        id: replyField
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        verticalAlignment: Text.AlignVCenter
                                        text: root.replyDraft
                                        color: Appearance.colors.colOnLayer4
                                        onTextEdited: root.replyDraft = text
                                        Keys.onPressed: event => {
                                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                                sendReplyButton.clicked();
                                                event.accepted = true;
                                            }
                                        }
                                    }

                                    StyledText {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        visible: !replyField.activeFocus && root.replyDraft.length === 0
                                        verticalAlignment: Text.AlignVCenter
                                        text: root.modelData?.replyPlaceholder || Translation.tr("Send reply…")
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }

                                RippleButton {
                                    id: sendReplyButton
                                    Layout.preferredWidth: implicitHeight
                                    Layout.preferredHeight: 36
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: Appearance.colors.colPrimaryContainer
                                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                                    enabled: root.replyDraft.length > 0
                                    opacity: enabled ? 1.0 : 0.5
                                    contentItem: MaterialSymbol {
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnPrimaryContainer
                                        text: root.replyJustSent ? "check" : "send"
                                        animateChange: true
                                    }
                                    onClicked: {
                                        if (!root.replyDraft)
                                            return;
                                        KdeConnectService.replyNotification(root.publicId, root.replyDraft);
                                        root.replyDraft = "";
                                        replyField.text = "";
                                        root.replyJustSent = true;
                                        confirmTimer.restart();
                                    }
                                    Timer {
                                        id: confirmTimer
                                        interval: 1500
                                        repeat: false
                                        onTriggered: root.replyJustSent = false
                                    }
                                }
                            }

                            RowLayout {
                                width: parent.width
                                Layout.topMargin: 2
                                spacing: 6

                                NotificationActionButton {
                                    Layout.fillWidth: true
                                    visible: root.hasReply
                                    opacity: visible ? 1.0 : 0.0
                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                    buttonText: Translation.tr("Reply")
                                    onClicked: replyField.forceActiveFocus()
                                    contentItem: MaterialSymbol {
                                        iconSize: Appearance.font.pixelSize.larger
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance.colors.colOnLayer4
                                        text: "reply"
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Focus the inline reply field")
                                    }
                                }

                                NotificationActionButton {
                                    buttonText: Translation.tr("Close")
                                    Layout.fillWidth: true
                                    onClicked: root.destroyWithAnimation()
                                    contentItem: MaterialSymbol {
                                        iconSize: Appearance.font.pixelSize.larger
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance.colors.colOnLayer4
                                        text: "close"
                                    }
                                }

                                NotificationActionButton {
                                    buttonText: Translation.tr("Copy")
                                    Layout.fillWidth: true
                                    onClicked: {
                                        Quickshell.clipboardText = root.modelData?.body || "";
                                        copyIcon.text = "inventory";
                                        copyIconTimer.restart();
                                    }
                                    Timer {
                                        id: copyIconTimer
                                        interval: 1500
                                        repeat: false
                                        onTriggered: copyIcon.text = "content_copy"
                                    }
                                    contentItem: MaterialSymbol {
                                        id: copyIcon
                                        iconSize: Appearance.font.pixelSize.larger
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance.colors.colOnLayer4
                                        text: "content_copy"
                                    }
                                }

                                // "Open on phone" button — visible when the
                                // notification has a package name (extracted
                                // from internalId). Dispatches via ADB
                                // `adb shell monkey -p <pkg>` to launch the app.
                                NotificationActionButton {
                                    Layout.fillWidth: true
                                    visible: root.hasPackage
                                    opacity: visible ? 1.0 : 0.0
                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                    buttonText: Translation.tr("Open on phone")
                                    onClicked: {
                                        KdeConnectService.openNotificationIntent(root.publicId);
                                    }
                                    contentItem: MaterialSymbol {
                                        iconSize: Appearance.font.pixelSize.larger
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance.colors.colOnLayer4
                                        text: "open_in_phone"
                                    }
                                    StyledToolTip {
                                        text: Translation.tr("Open the app this notification belongs to on the phone via ADB")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
