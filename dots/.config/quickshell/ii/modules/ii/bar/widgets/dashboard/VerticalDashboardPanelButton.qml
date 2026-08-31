import QtQuick
import "."
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.dashboard.icons

RippleButton { // Right sidebar button
    id: rightSidebarButton

    Layout.alignment: Qt.AlignBottom | Qt.AlignHCenter

    property real startRadius: Appearance.rounding.full
    property real endRadius: Appearance.rounding.full

    topLeftRadius: startRadius
    topRightRadius: startRadius
    bottomLeftRadius: endRadius
    bottomRightRadius: endRadius

    implicitHeight: indicatorsColumnLayout.implicitHeight + 8 * 2
    implicitWidth: Math.max(indicatorsColumnLayout.implicitWidth, Appearance.font.pixelSize.larger) + 12

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

    readonly property real iconPixelSize: {
        const size = Appearance.font.pixelSize.larger;
        return (typeof size === "number" && size > 0) ? size : 18;
    }

    DashboardIconDriver {
        id: iconDriver
        wifiIcon: wifiIcon
        bluetoothIcon: bluetoothIcon
        volumeIcon: volumeIcon
        micIcon: micIcon
        caffeineIcon: caffeineIcon
        vpnIcon: vpnIcon
        tailscaleIcon: tailscaleIcon
        alarmIcon: alarmIcon
        countdownIcon: countdownIcon
    }

    ColumnLayout {
        id: indicatorsColumnLayout
        anchors.centerIn: parent
        property real realSpacing: 6
        spacing: 0

        Revealer {
            vertical: true
            reveal: Config.options.bar.dashboardButton.showCaffeine && (Idle.inhibit ?? false)
            Layout.fillHeight: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            CoffeeIcon {
                id: caffeineIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                active: Idle.inhibit ?? false
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
            VolumeIcon {
                id: volumeIcon
                iconSize: rightSidebarButton.iconPixelSize
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
            MicIcon {
                id: micIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                muted: Audio.source?.audio?.muted ?? false
            }
        }
        Revealer {
            vertical: true
            reveal: Config.options.bar.dashboardButton.showCountdowns && iconDriver.countdownVisible
            Layout.fillWidth: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            HourglassIcon {
                id: countdownIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                running: iconDriver.countdownRunning
                paused: iconDriver.countdownPaused
                finished: iconDriver.countdownFinished
            }
        }
        Revealer {
            vertical: true
            reveal: Config.options.bar.dashboardButton.showAlarms && iconDriver.alarmVisible
            Layout.fillWidth: true
            Layout.bottomMargin: reveal ? indicatorsColumnLayout.realSpacing : 0
            Behavior on Layout.bottomMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            AlarmIcon {
                id: alarmIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                scheduled: iconDriver.alarmCount > 0
                ringing: iconDriver.alarmRinging
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
                sourceComponent: (Config.options.bar.styles.dashboard === "expressive") ? expressiveNotificationComp : defaultNotificationComp
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
        Item {
            implicitWidth: rightSidebarButton.iconPixelSize
            implicitHeight: rightSidebarButton.iconPixelSize

            MaterialSymbol {
                anchors.centerIn: parent
                visible: Network.ethernet
                text: "lan"
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
            }

            WifiIcon {
                id: wifiIcon
                anchors.centerIn: parent
                visible: !Network.ethernet
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                bars: {
                    if (!Network.ready || Network.wifiStatus !== "connected")
                        return 0;
                    const strength = Number(Network.networkStrength);
                    if (isNaN(strength))
                        return 1;
                    return strength > 67 ? 3 : strength > 33 ? 2 : 1;
                }
            }
        }
        BluetoothIcon {
            id: bluetoothIcon
            Layout.topMargin: indicatorsColumnLayout.realSpacing
            visible: BluetoothStatus.available
            iconSize: rightSidebarButton.iconPixelSize
            color: rightSidebarButton.colText
            connected: BluetoothStatus.connected
            poweredOff: !BluetoothStatus.enabled
        }
        VpnKeyIcon {
            id: vpnIcon
            Layout.topMargin: indicatorsColumnLayout.realSpacing
            visible: Config.options.bar.dashboardButton.showVpn && VpnService.active
            iconSize: rightSidebarButton.iconPixelSize
            color: rightSidebarButton.colText
            connected: VpnService.active
        }
        TailscaleIcon {
            id: tailscaleIcon
            Layout.topMargin: indicatorsColumnLayout.realSpacing
            visible: Config.options.bar.dashboardButton.showTailscale && TailscaleService.active
            iconSize: rightSidebarButton.iconPixelSize
            color: rightSidebarButton.colText
            connected: TailscaleService.active
        }
    }
}
