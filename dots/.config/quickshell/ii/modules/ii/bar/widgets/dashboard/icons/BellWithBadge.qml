pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The animated bell plus the unread-count badge that used to live on the
 * MaterialSymbol version. The badge is deliberately outside the bell's
 * transform: it marks a count, it should not swing with the hood.
 */
Item {
    id: root

    property real iconSize: Appearance.font.pixelSize.larger
    property color color: Appearance.colors.colOnLayer0
    property bool silent: false
    readonly property bool showUnreadCount: Config.options.bar.indicators.notifications.showUnreadCount

    implicitWidth: root.iconSize
    implicitHeight: root.iconSize

    function play(cue: string): void {
        bell.play(cue);
    }

    BellIcon {
        id: bell
        anchors.centerIn: parent
        iconSize: root.iconSize
        color: root.color
        silent: root.silent
    }

    Rectangle {
        id: notifPing
        visible: !Notifications.silent && Notifications.unread > 0
        anchors {
            right: parent.right
            top: parent.top
            rightMargin: root.showUnreadCount ? 0 : 1
            topMargin: root.showUnreadCount ? 0 : 3
        }
        radius: Appearance.rounding.full
        color: Appearance.colors.colTertiary
        z: 1

        implicitHeight: root.showUnreadCount ? Math.max(counter.implicitWidth, counter.implicitHeight) : 8
        implicitWidth: implicitHeight

        StyledText {
            id: counter
            visible: root.showUnreadCount
            anchors.centerIn: parent
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnTertiary
            text: Notifications.unread
        }
    }
}
