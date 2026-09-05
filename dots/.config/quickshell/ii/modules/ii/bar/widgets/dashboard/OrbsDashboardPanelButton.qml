import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.dashboard.icons

/**
 * Orbs dashboard panel button.
 *
 * The Expressive family puts the indicators in a row of assorted shapes inside
 * one pill. This one gives **every indicator its own circle** and nothing else:
 * no container behind them, no shape lottery, no connecting body. What a status
 * appearing does is add a circle; what the panel opening does is change what
 * the circles are made of.
 *
 *   filled    solid discs — the neutral container closed, the filled accent open
 *   outline   rings only, the bar showing through them
 *
 * The two treatments are one property apart because the geometry is identical:
 * only the fill and the stroke change, so switching between them cannot move
 * anything in the bar.
 */
Item {
    id: root

    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    property bool vertical: BarPlacement.vertical

    readonly property bool open: GlobalStates.sidebarRightOpen
    readonly property bool outlined: (Config.options.bar.dashboardButton.orbVariant ?? "filled") === "outline"
    readonly property bool hovered: mouseArea.containsMouse

    readonly property real orbSize: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8

    // Appearance.font is a QtObject assigned during Appearance's own setup, so
    // the first evaluation of a binding that reaches into it can land before it
    // exists. Reading it through a guarded property keeps that from reaching a
    // typed `real` as undefined.
    readonly property real iconPixelSize: {
        const size = Appearance.font.pixelSize.larger;
        return (typeof size === "number" && size > 0) ? size : 18;
    }

    implicitWidth: root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Math.max(0, flow.implicitWidth - flow.itemSpacing) + 6
    implicitHeight: root.vertical
        ? Math.max(0, flow.implicitHeight - flow.itemSpacing) + 6
        : Appearance.sizes.baseBarHeight

    // ── Colour ───────────────────────────────────────────────────────────────
    // Filled discs use two Material pairs, one per state. Rings have no surface
    // to pair with, so they take the bar's own content colour and the accent —
    // the same rule the bare bar widgets follow.
    readonly property color colOrb: {
        if (root.outlined) {
            if (root.open)
                return root.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary;
            return root.hovered ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnLayer1;
        }
        if (root.open)
            return root.hovered ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary;
        return root.hovered ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer;
    }
    readonly property color colInk: {
        if (root.outlined)
            return root.colOrb;
        return root.open ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer;
    }

    // Hover thickens the ring instead of filling it: a fill would be the other
    // treatment, and the point of this one is that it never has a background.
    property real ringWidth: Math.max(1.5, Math.round(root.orbSize * (root.hovered ? 0.085 : 0.06)))
    Behavior on ringWidth {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: GlobalStates.toggleRightSidebar(root.screenName)
    }

    // All three dashboard buttons share one state → cue mapping.
    DashboardIconDriver {
        id: iconDriver
        wifiIcon: wifiIcon
        bluetoothIcon: bluetoothIcon
        volumeIcon: volumeIcon
        micIcon: micIcon
        notificationIcon: notificationIcon
        caffeineIcon: caffeineIcon
        vpnIcon: vpnIcon
        tailscaleIcon: tailscaleIcon
        pomodoroIcon: pomodoroIcon
        stopwatchIcon: stopwatchIcon
        easyEffectsIcon: easyEffectsIcon
        dnsIcon: dnsIcon
        gameModeIcon: gameModeIcon
        songRecIcon: songRecIcon
        alarmIcon: alarmIcon
        countdownIcon: countdownIcon
    }

    Grid {
        id: flow
        anchors.centerIn: parent
        flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
        columns: root.vertical ? 1 : Math.max(1, flow.visibleChildren.length)
        // Orbs are separate objects and have to read as separate objects, so the
        // gap is a real gap — wide enough that two neighbouring rings never
        // look like one figure-eight.
        property real itemSpacing: root.outlined ? 6 : 4
        spacing: 0

        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showCaffeine && (Idle.inhibit ?? false)
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: caffeineWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                CoffeeIcon {
                    id: caffeineIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    active: Idle.inhibit ?? false
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showVolume
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: volumeWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                VolumeIcon {
                    id: volumeIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showMic && (Audio.source?.audio?.muted ?? false)
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: micWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                MicIcon {
                    id: micIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    muted: iconDriver.sourceMuted
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showNetwork
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: netWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: Network.ethernet && !GlobalStates.dashboardWifiDialogOpen
                    text: "lan"
                    iconSize: root.iconPixelSize
                    color: root.colInk
                }

                WifiIcon {
                    id: wifiIcon
                    anchors.centerIn: parent
                    visible: !Network.ethernet || GlobalStates.dashboardWifiDialogOpen
                    iconSize: root.iconPixelSize
                    color: root.colInk
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
            reveal: Config.options.bar.dashboardButton.showBluetooth && BluetoothStatus.available
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: btWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                BluetoothIcon {
                    id: bluetoothIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    connected: BluetoothStatus.connected
                    poweredOff: !BluetoothStatus.enabled
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showVpn && VpnService.active
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: vpnWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                VpnKeyIcon {
                    id: vpnIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    connected: VpnService.active
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showTailscale && TailscaleService.active
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: tailscaleWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                TailscaleIcon {
                    id: tailscaleIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    connected: TailscaleService.active
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showPomodoro && TimerService.pomodoroRunning
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: pomodoroWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                TimerIcon {
                    id: pomodoroIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    running: TimerService.pomodoroRunning
                    onBreak: TimerService.pomodoroBreak
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showStopwatch && TimerService.stopwatchRunning
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: stopwatchWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                StopwatchIcon {
                    id: stopwatchIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    running: TimerService.stopwatchRunning
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showCountdowns && iconDriver.countdownVisible
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: countdownWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                HourglassIcon {
                    id: countdownIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    running: iconDriver.countdownRunning
                    paused: iconDriver.countdownPaused
                    finished: iconDriver.countdownFinished
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showEasyEffects && EasyEffects.active
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: easyEffectsWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                EqualizerIcon {
                    id: easyEffectsIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    active: EasyEffects.active
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showDns && DnsOverTls.active
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: dnsWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                EncryptedDnsIcon {
                    id: dnsIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    active: DnsOverTls.active
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showGameMode && iconDriver.gameModeOn
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: gameModeWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                GamepadIcon {
                    id: gameModeIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    active: iconDriver.gameModeOn
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showMusicRecognition && SongRec.running
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: songRecWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                MusicRecognitionIcon {
                    id: songRecIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    listening: SongRec.running
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showAlarms && iconDriver.alarmVisible
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: alarmWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                AlarmIcon {
                    id: alarmIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    scheduled: iconDriver.alarmCount > 0
                    ringing: iconDriver.alarmRinging
                }
            }
        }
        DashboardIconRevealer {
            reveal: Config.options.bar.dashboardButton.showNotifications && (Notifications.silent || Notifications.unread > 0)
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            OrbIconWrapper {
                id: notifWrapper
                vertical: root.vertical
                outlined: root.outlined
                colOrb: root.colOrb
                ringWidth: root.ringWidth
                BellWithBadge {
                    id: notificationIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: root.colInk
                    silent: Notifications.silent
                }
            }
        }
    }
}
