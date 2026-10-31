import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.dock
import QtQuick

Item {
    id: badgeRoot
    width: root.buttonSize
    height: root.buttonSize
    anchors.centerIn: parent

    DockIcon {
        id: iconContainer
        appId: root.appToplevel?.appId ?? ""
        desktopEntry: root.desktopEntry
        isRunning: root.appIsRunning
        renderScale: root.dockContent?.magnificationRenderScale ?? 1
        width: root.buttonSize
        height: root.buttonSize
        anchors.centerIn: parent
    }

    // ── Notification badge ────────────────────────────────────────────────
    readonly property int _notifCount: {
        if (!(Config.options?.dock?.showNotificationBadges ?? false)) return 0
        if (!root.desktopEntry || !root.desktopEntry.name) return 0
        var targetName = root.desktopEntry.name.toLowerCase()
        var count = 0
        for (var i = 0; i < Notifications.list.length; i++) {
            if (Notifications.list[i].appName.toLowerCase() === targetName) count++
        }
        return count
    }

    AppNotificationBadge {
        count: badgeRoot._notifCount
    }
}
