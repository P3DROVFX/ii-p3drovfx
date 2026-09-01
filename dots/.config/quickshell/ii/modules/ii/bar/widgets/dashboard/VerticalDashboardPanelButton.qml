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

    implicitHeight: Math.max(0, indicatorsColumnLayout.implicitHeight - indicatorsColumnLayout.realSpacing) + 8 * 2
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

        DashboardIconRevealer {
            vertical: true
            reveal: Config.options.bar.dashboardButton.showCaffeine && (Idle.inhibit ?? false)
            layoutSpacing: indicatorsColumnLayout.realSpacing
            Layout.fillHeight: true
            CoffeeIcon {
                id: caffeineIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                active: Idle.inhibit ?? false
            }
        }
        DashboardIconRevealer {
            vertical: true
            reveal: Audio.sink?.audio?.muted ?? false
            layoutSpacing: indicatorsColumnLayout.realSpacing
            Layout.fillWidth: true
            VolumeIcon {
                id: volumeIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
            }
        }
        DashboardIconRevealer {
            vertical: true
            reveal: Audio.source?.audio?.muted ?? false
            layoutSpacing: indicatorsColumnLayout.realSpacing
            Layout.fillWidth: true
            MicIcon {
                id: micIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                muted: Audio.source?.audio?.muted ?? false
            }
        }
        DashboardIconRevealer {
            vertical: true
            reveal: Config.options.bar.dashboardButton.showCountdowns && iconDriver.countdownVisible
            layoutSpacing: indicatorsColumnLayout.realSpacing
            Layout.fillWidth: true
            HourglassIcon {
                id: countdownIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                running: iconDriver.countdownRunning
                paused: iconDriver.countdownPaused
                finished: iconDriver.countdownFinished
            }
        }
        DashboardIconRevealer {
            vertical: true
            reveal: Config.options.bar.dashboardButton.showAlarms && iconDriver.alarmVisible
            layoutSpacing: indicatorsColumnLayout.realSpacing
            Layout.fillWidth: true
            AlarmIcon {
                id: alarmIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                scheduled: iconDriver.alarmCount > 0
                ringing: iconDriver.alarmRinging
            }
        }
        DashboardIconRevealer {
            vertical: true
            reveal: Notifications.silent || Notifications.unread > 0
            layoutSpacing: indicatorsColumnLayout.realSpacing
            Layout.fillWidth: true
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
        DashboardIconRevealer {
            vertical: true
            reveal: true
            layoutSpacing: indicatorsColumnLayout.realSpacing

            Item {
                implicitWidth: rightSidebarButton.iconPixelSize
                implicitHeight: rightSidebarButton.iconPixelSize

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: Network.ethernet && !GlobalStates.dashboardWifiDialogOpen
                    text: "lan"
                    iconSize: rightSidebarButton.iconPixelSize
                    color: rightSidebarButton.colText
                }

                WifiIcon {
                    id: wifiIcon
                    anchors.centerIn: parent
                    visible: !Network.ethernet || GlobalStates.dashboardWifiDialogOpen
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
        }
        DashboardIconRevealer {
            vertical: true
            reveal: BluetoothStatus.available
            layoutSpacing: indicatorsColumnLayout.realSpacing
            BluetoothIcon {
                id: bluetoothIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                connected: BluetoothStatus.connected
                poweredOff: !BluetoothStatus.enabled
            }
        }
        DashboardIconRevealer {
            vertical: true
            reveal: Config.options.bar.dashboardButton.showVpn && VpnService.active
            layoutSpacing: indicatorsColumnLayout.realSpacing
            VpnKeyIcon {
                id: vpnIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                connected: VpnService.active
            }
        }
        DashboardIconRevealer {
            vertical: true
            reveal: Config.options.bar.dashboardButton.showTailscale && TailscaleService.active
            layoutSpacing: indicatorsColumnLayout.realSpacing
            TailscaleIcon {
                id: tailscaleIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                connected: TailscaleService.active
            }
        }
    }
}
