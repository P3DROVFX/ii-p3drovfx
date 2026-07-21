import qs.services
import qs.modules.common
import qs.modules.common.widgets
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

    readonly property real _badgeSize: Math.round(root.buttonSize * 0.38)
    readonly property real _fontSize: Math.round(_badgeSize * 0.58)

    Rectangle {
        visible: badgeRoot._notifCount > 0
        width: badgeRoot._notifCount >= 10 ? badgeRoot._badgeSize * 1.25 : badgeRoot._badgeSize
        height: badgeRoot._badgeSize
        radius: Appearance.rounding.full
        color: Appearance.colors.colTertiary
        border.width: Math.max(1.5, Math.round(root.buttonSize * 0.025))
        border.color: Appearance.colors.colLayer0

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -height * 0.22
        anchors.rightMargin: -width * 0.22

        Behavior on visible {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }

        StyledText {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: badgeRoot._notifCount.toString()
            font.pixelSize: badgeRoot._fontSize
            font.weight: Font.Bold
            color: Appearance.colors.colOnTertiary
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
