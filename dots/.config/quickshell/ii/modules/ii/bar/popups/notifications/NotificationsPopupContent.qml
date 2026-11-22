import QtQuick
import qs.modules.common
import qs.modules.common.notifications
import qs.services

/**
 * The dashboard's notification list at popup size, as wide as the sidebar's content.
 * No card of its own: the popup's surface is the only background, so the notification
 * groups sit straight on it. Short while there is nothing to show, taller once there is.
 */
Item {
    id: root

    readonly property bool empty: (Notifications.list?.length ?? 0) === 0

    implicitWidth: Appearance.sizes.sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2 - 20
    implicitHeight: root.empty ? Appearance.sizes.sidebarWidth * 0.55 : Appearance.sizes.sidebarWidth * 1.1

    NotificationList {
        anchors.fill: parent
    }
}
