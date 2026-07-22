pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell

/**
 * Mirror of `NotificationListView` for KDE Connect (Android) notifications.
 *
 * Uses the same grouping pattern as the dashboard: delegates are
 * `RemoteNotificationGroup` instances backed by
 * `KdeConnectService.groupsByAppName` / `appNameList`. Each group
 * collapses multiple notifications from the same app into a single card
 * with a count badge and expand/collapse button.
 *
 * The `dragIndex` / `dragDistance` properties are consumed by the group
 * delegates to animate neighboring items during swipe-to-dismiss.
 *
 * Source of truth: `KdeConnectService.notifications` (only the active
 * device's notifications are retained).
 */
StyledListView {
    id: root

    property bool dismissToLeft: false
    property string deviceId: KdeConnectService.activeDeviceId || ""

    spacing: 3
    clip: true
    // Keep delegates alive for ~6 card heights off-screen so scrolling
    // doesn't create/destroy expensive RemoteNotificationGroup instances
    // (each containing an inner list + DragManagers + TextMetrics) on
    // every frame. Without this the ListView rebuilds every group as it
    // enters/leaves the viewport, causing visible lag with many groups.
    cacheBuffer: 600

    model: ScriptModel {
        values: KdeConnectService.appNameList
    }
    property int entranceTrigger: -1
    onEntranceTriggerChanged: {
        placeholder.animateIconOnShow = true
    }

    delegate: RemoteNotificationGroup {
        id: groupDelegate
        required property int index
        required property var modelData
        width: ListView.view.width
        opacity: delegateAnim.running ? opacity : (_validGroup ? 1.0 : 0.0)

        groupPosition: {
            const count = root.count
            if (count <= 1) return 0 // single
            if (index === 0) return 1 // top
            if (index === count - 1) return 3 // bottom
            return 2 // middle
        }
        notificationGroup: {
            const g = KdeConnectService.groupsByAppName[modelData]
            return g || null
        }

        property real itemBlurProgress: 0.0

        layer.enabled: itemBlurProgress > 0.01
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 128.0
            blur: groupDelegate.itemBlurProgress
        }

        transform: [
            Translate {
                id: groupTransform
                y: 0
            },
            Scale {
                id: groupScale
                origin.x: groupDelegate.width / 2
                origin.y: groupDelegate.height / 2
                xScale: 1.0
                yScale: 1.0
            }
        ]

        function startEntranceAnim() {
            delegateAnim.stop()
            groupDelegate.opacity = 0
            groupTransform.y = 35
            groupScale.xScale = 0.75
            groupScale.yScale = 0.75
            groupDelegate.itemBlurProgress = 1.0
            delegateAnim.start()
        }

        Component.onCompleted: {
            if (root.entranceTrigger >= 0) {
                Qt.callLater(startEntranceAnim)
            }
        }

        Connections {
            target: root
            function onEntranceTriggerChanged() {
                if (root.entranceTrigger >= 0) {
                    Qt.callLater(startEntranceAnim)
                }
            }
        }

        SequentialAnimation {
            id: delegateAnim
            PauseAnimation { duration: 120 + Math.min(250, groupDelegate.index * 45) }
            ParallelAnimation {
                NumberAnimation { target: groupDelegate; property: "opacity"; to: (groupDelegate._validGroup ? 1.0 : 0.0); duration: 380; easing.type: Easing.OutQuart }
                NumberAnimation { target: groupTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutQuart }
                NumberAnimation { target: groupScale; property: "xScale"; to: 1.0; duration: 380; easing.type: Easing.OutQuart }
                NumberAnimation { target: groupScale; property: "yScale"; to: 1.0; duration: 380; easing.type: Easing.OutQuart }
                NumberAnimation { target: groupDelegate; property: "itemBlurProgress"; to: 0.0; duration: 380; easing.type: Easing.OutQuart }
            }
        }
    }

    PagePlaceholder {
        id: placeholder
        anchors.fill: parent
        shown: KdeConnectService.notifications.length === 0
        animateIconOnShow: true
        icon: "notifications_off"
        description: {
            if (KdeConnectService.activeReachable
                    && KdeConnectService.activeDevice
                    && (KdeConnectService.activeDevice.supportedPlugins
                            || []).indexOf("kdeconnect_notifications") >= 0) {
                return Translation.tr(
                    "No notifications\nMake sure KDE Connect has \nNotification Access on your phone")
            }
            return Translation.tr("No notifications from phone")
        }
        shape: MaterialShape.Shape.Ghostish
        descriptionHorizontalAlignment: Text.AlignHCenter
    }
}
