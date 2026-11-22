import qs
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.notifications
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Notifications — expressive bar style: its own pill. Quiet (bar layer) with nothing to
 * read; the configured palette's surface, with the count, while something is unread.
 * Hover (or click, per the bar setting) opens the notification center, right click toggles Do Not Disturb.
 */
MouseArea {
    id: root

    property bool vertical: false
    readonly property bool rightClickCycles: true
    // A block, not a bare `??` chain: while the bar window is torn down the attached
    // QsWindow can vanish mid-evaluation and the chain handed the string `undefined`.
    readonly property string screenName: {
        const name = root.QsWindow?.window?.screen?.name;
        return typeof name === "string" ? name : "";
    }
    readonly property int unread: Notifications.unread
    readonly property bool hasUnread: !Notifications.silent && root.unread > 0
    readonly property real contentScale: root.vertical
        ? Appearance.sizes.verticalBarContentScale
        : Appearance.sizes.barContentScale

    BarWidgetPalette {
        id: palette
        colorMode: Config.options.bar.notificationButton.colorMode
    }

    readonly property color colSurface: root.hasUnread
        ? (root.containsMouse ? palette.colBackgroundHover : palette.colBackground)
        : (root.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1)
    readonly property color colContent: root.hasUnread ? palette.colOnBackground : Appearance.colors.colOnLayer1

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : pill.width
    implicitHeight: root.vertical ? pill.height : Appearance.sizes.baseBarHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            Notifications.silent = !Notifications.silent;
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        readonly property real thickness: (root.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) - 8
        // Never square while it carries a count: the vertical bar would follow width.
        width: root.vertical ? thickness : Math.max(thickness, content.implicitWidth + thickness * 0.6)
        height: root.vertical ? Math.max(thickness, content.implicitHeight + thickness * 0.6) : thickness
        radius: Appearance.rounding.full
        color: root.colSurface

        Behavior on width {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }
        Behavior on height {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        GridLayout {
            id: content
            anchors.centerIn: parent
            columns: root.vertical ? 1 : 2
            columnSpacing: 4
            rowSpacing: 0

            MaterialSymbol {
                Layout.alignment: Qt.AlignCenter
                text: Notifications.silent ? "notifications_paused"
                    : (root.unread > 0 ? "notifications_unread" : "notifications")
                iconSize: Math.round((root.vertical ? 18 : Appearance.font.pixelSize.larger) * root.contentScale)
                fill: root.hasUnread ? 1 : 0
                color: root.colContent
            }

            StyledText {
                visible: root.hasUnread
                Layout.alignment: Qt.AlignCenter
                text: root.unread > 99 ? "99+" : String(root.unread)
                font.pixelSize: Math.round((root.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small) * root.contentScale)
                font.weight: Font.Bold
                color: root.colContent
            }
        }
    }

    PopupLoader {
        active: BarInteraction.enablePopups
            && (BarInteraction.clickToShow || root.containsMouse || held
                || GlobalStates.isBarPopupOpen("notifications", root.screenName))
        sourceComponent: NotificationsPopup {
            hoverTarget: root
        }
    }
}
