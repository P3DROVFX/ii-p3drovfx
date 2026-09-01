import QtQuick
import "."
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.dashboard.icons

RippleButton { // Right sidebar button
    id: rightSidebarButton

    readonly property string screenName: QsWindow.window?.screen?.name ?? ""

    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter

    property real startRadius: Appearance.rounding.full
    property real endRadius: Appearance.rounding.full

    topLeftRadius: startRadius
    bottomLeftRadius: startRadius
    topRightRadius: endRadius
    bottomRightRadius: endRadius

    implicitWidth: Math.max(0, indicatorsRowLayout.implicitWidth - indicatorsRowLayout.realSpacing) + 10
    implicitHeight: Math.max(indicatorsRowLayout.implicitHeight, Appearance.font.pixelSize.larger) + 10

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
        GlobalStates.toggleRightSidebar(screenName);
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

    RowLayout {
        id: indicatorsRowLayout
        anchors.centerIn: parent
        property real realSpacing: 15
        spacing: 0

        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showCaffeine && (Idle.inhibit ?? false)
            layoutSpacing: indicatorsRowLayout.realSpacing
            Layout.fillHeight: true
            CoffeeIcon {
                id: caffeineIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                active: Idle.inhibit ?? false
            }
        }
        DashboardIconRevealer {
            reveal: Audio.sink?.audio?.muted ?? false
            layoutSpacing: indicatorsRowLayout.realSpacing
            Layout.fillHeight: true
            VolumeIcon {
                id: volumeIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
            }
        }
        DashboardIconRevealer {
            reveal: Audio.source?.audio?.muted ?? false
            layoutSpacing: indicatorsRowLayout.realSpacing
            Layout.fillHeight: true
            MicIcon {
                id: micIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                muted: Audio.source?.audio?.muted ?? false
            }
        }

        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showCountdowns && iconDriver.countdownVisible
            layoutSpacing: indicatorsRowLayout.realSpacing
            Layout.fillHeight: true
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
            reveal: Config.options.bar.dashboardButton.showAlarms && iconDriver.alarmVisible
            layoutSpacing: indicatorsRowLayout.realSpacing
            Layout.fillHeight: true
            AlarmIcon {
                id: alarmIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                scheduled: iconDriver.alarmCount > 0
                ringing: iconDriver.alarmRinging
            }
        }

        DashboardIconRevealer {
            reveal: Notifications.silent || Notifications.unread > 0
            layoutSpacing: indicatorsRowLayout.realSpacing
            Layout.fillHeight: true
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
            reveal: true
            layoutSpacing: indicatorsRowLayout.realSpacing
            Layout.fillHeight: true

            Item {
                implicitWidth: netFgIcon.implicitWidth
                implicitHeight: netFgIcon.implicitHeight

                MaterialSymbol {
                    id: netFgIcon
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
            reveal: BluetoothStatus.available
            layoutSpacing: indicatorsRowLayout.realSpacing
            BluetoothIcon {
                id: bluetoothIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                connected: BluetoothStatus.connected
                poweredOff: !BluetoothStatus.enabled
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showVpn && VpnService.active
            layoutSpacing: indicatorsRowLayout.realSpacing
            VpnKeyIcon {
                id: vpnIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                connected: VpnService.active
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showTailscale && TailscaleService.active
            layoutSpacing: indicatorsRowLayout.realSpacing
            TailscaleIcon {
                id: tailscaleIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
                connected: TailscaleService.active
            }
        }
    }
}
