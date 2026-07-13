pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
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
    delegate: RemoteNotificationGroup {
        required property int index
        required property var modelData
        width: ListView.view.width
        notificationGroup: {
            const g = KdeConnectService.groupsByAppName[modelData]
            // Guard against the transient state where appNameList has been
            // updated but groupsByAppName hasn't finished recomputing yet
            // (or vice versa). Returning undefined would render an empty
            // delegate that still consumes spacing/height.
            return g || null
        }
    }

    PagePlaceholder {
        anchors.fill: parent
        shown: KdeConnectService.notifications.length === 0
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
