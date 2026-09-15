import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.lunae
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

MouseArea {
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    property bool elevated: popup
    property real padding: 10
    implicitHeight: background.implicitHeight

    property real dragConfirmThreshold: 70
    property real dismissOvershoot: 20
    property var qmlParent: root?.parent?.parent
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance :
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    property bool isExiting: false
    signal exitComplete()

    onIsExitingChanged: if (isExiting) exitAnim.start()

    SequentialAnimation {
        id: exitAnim
        ParallelAnimation {
            NumberAnimation {
                target: background
                property: "anchors.leftMargin"
                to: root.width + root.dismissOvershoot
                duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: LunaeAppearance.popupCurve
            }
            NumberAnimation {
                target: background
                property: "opacity"
                to: 0
                duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: LunaeAppearance.popupCurve
            }
        }
        ScriptAction {
            script: root.implicitHeight = root.implicitHeight
        }
        NumberAnimation {
            target: root
            property: "implicitHeight"
            to: 0
            duration: LunaeAppearance.notifExpansionDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: LunaeAppearance.notifExpansionCurve
        }
        ScriptAction {
            script: root.exitComplete()
        }
    }

    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin;
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    hoverEnabled: false

    SequentialAnimation {
        id: destroyAnimation
        property bool left: true
        running: false

        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: () => {
            root.notifications.forEach((notif) => {
                Qt.callLater(() => {
                    Notifications.discardNotification(notif.notificationId);
                });
            });
        }
    }

    function toggleExpanded() {
        implicitHeightAnim.enabled = true
        root.expanded = !root.expanded;
    }

    DragManager {
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: {
            if (mouse.button === Qt.RightButton)
                root.toggleExpanded();
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton)
                root.destroyWithAnimation();
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
        visible: elevated
    }
    Rectangle {
        id: background
        anchors.left: parent.left
        width: parent.width
        color: elevated ? Appearance.colors.colBackgroundSurfaceContainer
            : popup ? Appearance.colors.colLayer0
            : Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
        anchors.leftMargin: root.xOffset

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging && !root.isExiting
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }

        clip: true
        implicitHeight: root.expanded ?
            row.implicitHeight + padding * 2 :
            Math.min(80, row.implicitHeight + padding * 2)

        Behavior on implicitHeight {
            id: implicitHeightAnim
            NumberAnimation {
                duration: LunaeAppearance.notifExpansionDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: LunaeAppearance.notifExpansionCurve
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
                image: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.image ?? ""
                appIcon: root.notificationGroup?.appIcon
                summary: root.notificationGroup?.notifications[root.notificationCount - 1]?.summary
                urgency: root.notifications.some(n => n.urgency === NotificationUrgency.Critical.toString()) ?
                    NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: expanded ? (root.multipleNotifications ?
                    (notificationGroup?.notifications[root.notificationCount - 1].image != "") ? 35 :
                    5 : 0) : 0
                Behavior on spacing {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item {
                    id: topRow
                    Layout.fillWidth: true
                    property real fontSize: Appearance.font.pixelSize.smaller
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
                            text: (topRow.showAppName ?
                                notificationGroup?.appName :
                                notificationGroup?.notifications[0]?.summary) || ""
                            font.pixelSize: topRow.showAppName ?
                                topRow.fontSize :
                                Appearance.font.pixelSize.small
                            color: topRow.showAppName ?
                                Appearance.colors.colSubtext :
                                Config.options.lunae.colorful ? Appearance.colors.colTertiary : Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            id: timeText
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
                        fontSize: topRow.fontSize
                        onClicked: { root.toggleExpanded() }
                        altAction: () => { root.toggleExpanded() }

                        StyledToolTip {
                            text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                        }
                    }
                }

                StyledListView {
                    id: notificationsColumn
                    implicitHeight: contentHeight
                    Layout.fillWidth: true
                    spacing: expanded ? 5 : 3
                    interactive: false
                    Behavior on spacing {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    model: ScriptModel {
                        values: root.expanded ? root.notifications.slice().reverse() :
                            root.notifications.slice().reverse().slice(0, 2)
                    }
                    delegate: LunaeNotificationItem {
                        required property int index
                        required property var modelData
                        notificationObject: modelData
                        expanded: root.expanded
                        elevated: root.elevated
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
