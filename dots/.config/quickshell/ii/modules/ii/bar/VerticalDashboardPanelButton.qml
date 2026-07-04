import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton { // Right sidebar button
    id: rightSidebarButton

    Layout.alignment: Qt.AlignBottom | Qt.AlignHCenter
    Layout.fillWidth: true
    Layout.fillHeight: true

    property real startRadius: Appearance.rounding.full
    property real endRadius: Appearance.rounding.full

    topLeftRadius: startRadius
    topRightRadius: startRadius
    bottomLeftRadius: endRadius
    bottomRightRadius: endRadius

    implicitHeight: indicatorsColumnLayout.implicitHeight + 8 * 2
    implicitWidth: Appearance.sizes.verticalBarWidth

    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarRightOpen
    property color colText: toggled ? Appearance.m3colors.m3onSecondaryContainer : Appearance.colors.colOnLayer0

    Behavior on colText {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    onPressed: {
        GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
    }

    ColumnLayout {
        id: indicatorsColumnLayout
        anchors.centerIn: parent
        property real realSpacing: 6
        spacing: 0

        Revealer {
            vertical: true
            reveal: Idle.inhibit ?? false
            Layout.fillHeight: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                text: "coffee"
                iconSize: Appearance.font.pixelSize.larger
                color: rightSidebarButton.colText
            }
        }
        Revealer {
            vertical: true
            reveal: Audio.sink?.audio?.muted ?? false
            Layout.fillWidth: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                text: "volume_off"
                iconSize: Appearance.font.pixelSize.larger
                color: rightSidebarButton.colText
            }
        }
        Revealer {
            vertical: true
            reveal: Audio.source?.audio?.muted ?? false
            Layout.fillWidth: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            Behavior on Layout.topMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            MaterialSymbol {
                text: "mic_off"
                iconSize: Appearance.font.pixelSize.larger
                color: rightSidebarButton.colText
            }
        }
        Revealer {
            vertical: true
            reveal: Notifications.silent || Notifications.unread > 0
            Layout.fillWidth: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
            implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Loader {
                id: notificationUnreadCount
                sourceComponent: Config.options.bar.styles.notification === "expressive" ? expressiveNotificationComp : defaultNotificationComp
            }
            Component {
                id: defaultNotificationComp
                NotificationUnreadCount {}
            }
            Component {
                id: expressiveNotificationComp
                ExpressiveNotificationUnreadCount {}
            }
        }
        MaterialSymbol {
            text: Network.materialSymbol
            iconSize: Appearance.font.pixelSize.larger
            color: rightSidebarButton.colText
        }
        MaterialSymbol {
            Layout.topMargin: indicatorsColumnLayout.realSpacing
            visible: BluetoothStatus.available
            text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            iconSize: Appearance.font.pixelSize.larger
            color: rightSidebarButton.colText
        }
    }
}
