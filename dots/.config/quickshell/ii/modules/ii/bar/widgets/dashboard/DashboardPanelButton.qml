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

    implicitWidth: indicatorsRowLayout.implicitWidth + 10
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

        Revealer {
            reveal: Config.options.bar.dashboardButton.showCaffeine && (Idle.inhibit ?? false)
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
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
            reveal: Audio.sink?.audio?.muted ?? false
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            VolumeIcon {
                id: volumeIcon
                iconSize: rightSidebarButton.iconPixelSize
                color: rightSidebarButton.colText
            }
        }
        Revealer {
            reveal: Audio.source?.audio?.muted ?? false
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
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
            reveal: Config.options.bar.dashboardButton.showCountdowns && iconDriver.countdownVisible
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
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
            reveal: Config.options.bar.dashboardButton.showAlarms && iconDriver.alarmVisible
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            Behavior on Layout.rightMargin {
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
            reveal: Notifications.silent || Notifications.unread > 0
            Layout.fillHeight: true
            Layout.rightMargin: reveal ? indicatorsRowLayout.realSpacing : 0
            implicitHeight: reveal ? notificationUnreadCount.implicitHeight : 0
            implicitWidth: reveal ? notificationUnreadCount.implicitWidth : 0
            Behavior on Layout.rightMargin {
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
            Layout.fillHeight: true
            implicitWidth: netFgIcon.implicitWidth
            implicitHeight: netFgIcon.implicitHeight

            MaterialSymbol {
                id: netFgIcon
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
            Layout.leftMargin: indicatorsRowLayout.realSpacing
            visible: BluetoothStatus.available
            iconSize: rightSidebarButton.iconPixelSize
            color: rightSidebarButton.colText
            connected: BluetoothStatus.connected
            poweredOff: !BluetoothStatus.enabled
        }
        VpnKeyIcon {
            id: vpnIcon
            Layout.leftMargin: indicatorsRowLayout.realSpacing
            visible: Config.options.bar.dashboardButton.showVpn && VpnService.active
            iconSize: rightSidebarButton.iconPixelSize
            color: rightSidebarButton.colText
            connected: VpnService.active
        }
        TailscaleIcon {
            id: tailscaleIcon
            Layout.leftMargin: indicatorsRowLayout.realSpacing
            visible: Config.options.bar.dashboardButton.showTailscale && TailscaleService.active
            iconSize: rightSidebarButton.iconPixelSize
            color: rightSidebarButton.colText
            connected: TailscaleService.active
        }
    }
}
