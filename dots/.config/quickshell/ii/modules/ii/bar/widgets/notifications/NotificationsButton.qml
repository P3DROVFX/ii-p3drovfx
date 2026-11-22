import qs
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.notifications
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Notifications — default bar style: the bell and, while something is unread, how many.
 * The BarGroup supplies the background. Hover (or click, per the bar setting) opens the notification center, right click
 * toggles Do Not Disturb.
 */
MouseArea {
    id: root

    property bool vertical: false
    // Keeps the right press away from the popup's click toggle.
    readonly property bool rightClickCycles: true
    // A block, not a bare `??` chain: while the bar window is torn down the attached
    // QsWindow can vanish mid-evaluation and the chain handed the string `undefined`.
    readonly property string screenName: {
        const name = root.QsWindow?.window?.screen?.name;
        return typeof name === "string" ? name : "";
    }
    readonly property int unread: Notifications.unread
    readonly property bool showCount: !Notifications.silent && root.unread > 0

    readonly property color contentColor: Appearance.colors.colOnLayer1

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : content.implicitWidth + 10
    implicitHeight: root.vertical ? content.implicitHeight + 10 : Appearance.sizes.baseBarHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            Notifications.silent = !Notifications.silent;
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
            iconSize: Appearance.font.pixelSize.larger
            fill: root.unread > 0 ? 1 : 0
            color: root.contentColor
        }

        StyledText {
            visible: root.showCount
            Layout.alignment: Qt.AlignCenter
            text: root.unread > 99 ? "99+" : String(root.unread)
            font.pixelSize: root.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            font.weight: Font.Bold
            color: root.contentColor
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
