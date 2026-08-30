import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar.widgets.dashboard.icons

Item {
    id: root
    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    property bool borderless: Config.options.bar.borderless
    property bool showDate: Config.options.bar.verbose
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: true // Forced expressive

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : pill.implicitWidth
    implicitHeight: vertical ? pill.implicitHeight : Appearance.sizes.baseBarHeight

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: {
            GlobalStates.toggleRightSidebar(root.screenName);
        }
    }

    Canvas {
        id: pill
        visible: root.isMaterial
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.vertical ? 0 : -0

        property color pillColor: GlobalStates.sidebarRightOpen 
            ? (mouseArea.containsMouse ? Appearance.colors.colLayer4Hover : "transparent")
            : (mouseArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainer)

        property color borderColor: GlobalStates.sidebarRightOpen 
            ? Appearance.colors.colPrimary
            : "transparent"

        property real borderWidth: GlobalStates.sidebarRightOpen ? 1.5 : 0
        property real dashLength: GlobalStates.sidebarRightOpen ? 6 : 0
        property real gapLength: GlobalStates.sidebarRightOpen ? 4 : 0
        property real radius: Config.options.bar.barGroupStyle === 1 ? Appearance.rounding.windowRounding : Appearance.rounding.full
        property real dashOffset: 0

        implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth - 8 : flow.implicitWidth + 10
        implicitHeight: root.vertical ? flow.implicitHeight + 10 : Appearance.sizes.baseBarHeight - 8

        width: implicitWidth
        height: implicitHeight

        Behavior on implicitWidth {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }

        Behavior on implicitHeight {
            animation: Appearance.animation.barResize.numberAnimation.createObject(this)
        }

        onPillColorChanged: requestPaint()
        onBorderColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onDashOffsetChanged: requestPaint()

        Behavior on pillColor {
            ColorAnimation { duration: 150 }
        }

        onPaint: {
            if (width <= 0 || height <= 0) return;
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var w = width;
            var h = height;
            var bw = borderWidth;
            var r = Math.min(radius, (w - 2 * bw) / 2, (h - 2 * bw) / 2);

            ctx.save();

            ctx.beginPath();
            ctx.moveTo(bw + r, bw);
            ctx.arcTo(w - bw, bw, w - bw, h - bw, r);
            ctx.arcTo(w - bw, h - bw, bw, h - bw, r);
            ctx.arcTo(bw, h - bw, bw, bw, r);
            ctx.arcTo(bw, bw, w - bw, bw, r);
            ctx.closePath();

            ctx.fillStyle = pillColor;
            ctx.fill();

            if (bw > 0) {
                ctx.strokeStyle = borderColor;
                ctx.lineWidth = bw;
                ctx.setLineDash([dashLength, gapLength]);
                ctx.lineDashOffset = dashOffset;
                ctx.stroke();
            }

            ctx.restore();
        }
    }

    NumberAnimation {
        id: dashSlideAnim
        target: pill
        property: "dashOffset"
        from: 0
        to: 20
        duration: 800
        easing.type: Easing.OutCubic
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                dashSlideAnim.restart();
            } else {
                pill.dashOffset = 0;
            }
        }
    }

    // Appearance.font is a QtObject assigned during Appearance's own setup, so
    // the first evaluation of a binding that reaches into it can land before it
    // exists. Reading it through a guarded property keeps that from reaching a
    // typed `real` as undefined.
    readonly property real iconPixelSize: {
        const size = Appearance.font.pixelSize.larger;
        return (typeof size === "number" && size > 0) ? size : 18;
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
        anchors.verticalCenterOffset: root.vertical ? 0 : 0
        flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
        columns: root.vertical ? 1 : Math.max(1, flow.visibleChildren.length)
        spacing: isMaterial ? 6 : 10

        move: Transition {
            NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutQuint }
        }

        Revealer {
            reveal: Config.options.bar.dashboardButton.showCaffeine && (Idle.inhibit ?? false)
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: caffeineWrapper
                vertical: root.vertical
                CoffeeIcon {
                    id: caffeineIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: caffeineWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    active: Idle.inhibit ?? false
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showVolume
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: volumeWrapper
                vertical: root.vertical
                VolumeIcon {
                    id: volumeIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: volumeWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showMic && (Audio.source?.audio?.muted ?? false)
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: micWrapper
                vertical: root.vertical
                MicIcon {
                    id: micIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: micWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    muted: iconDriver.sourceMuted
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showNetwork
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: netWrapper
                vertical: root.vertical

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: Network.ethernet
                    text: "lan"
                    iconSize: root.iconPixelSize
                    color: netWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                }

                WifiIcon {
                    id: wifiIcon
                    anchors.centerIn: parent
                    visible: !Network.ethernet
                    iconSize: root.iconPixelSize
                    color: netWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
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
        Revealer {
            reveal: Config.options.bar.dashboardButton.showBluetooth && BluetoothStatus.available
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: btWrapper
                vertical: root.vertical
                BluetoothIcon {
                    id: bluetoothIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: btWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    connected: BluetoothStatus.connected
                    poweredOff: !BluetoothStatus.enabled
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showVpn && VpnService.active
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: vpnWrapper
                vertical: root.vertical
                VpnKeyIcon {
                    id: vpnIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: vpnWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    connected: VpnService.active
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showTailscale && TailscaleService.active
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: tailscaleWrapper
                vertical: root.vertical
                TailscaleIcon {
                    id: tailscaleIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: tailscaleWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    connected: TailscaleService.active
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showPomodoro && TimerService.pomodoroRunning
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: pomodoroWrapper
                vertical: root.vertical
                TimerIcon {
                    id: pomodoroIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: pomodoroWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    running: TimerService.pomodoroRunning
                    onBreak: TimerService.pomodoroBreak
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showStopwatch && TimerService.stopwatchRunning
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: stopwatchWrapper
                vertical: root.vertical
                StopwatchIcon {
                    id: stopwatchIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: stopwatchWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    running: TimerService.stopwatchRunning
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showCountdowns && iconDriver.countdownVisible
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: countdownWrapper
                vertical: root.vertical
                HourglassIcon {
                    id: countdownIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: countdownWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    running: iconDriver.countdownRunning
                    paused: iconDriver.countdownPaused
                    finished: iconDriver.countdownFinished
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showEasyEffects && EasyEffects.active
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: easyEffectsWrapper
                vertical: root.vertical
                EqualizerIcon {
                    id: easyEffectsIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: easyEffectsWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    active: EasyEffects.active
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showDns && DnsOverTls.active
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: dnsWrapper
                vertical: root.vertical
                EncryptedDnsIcon {
                    id: dnsIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: dnsWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    active: DnsOverTls.active
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showGameMode && iconDriver.gameModeOn
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: gameModeWrapper
                vertical: root.vertical
                GamepadIcon {
                    id: gameModeIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: gameModeWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    active: iconDriver.gameModeOn
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showMusicRecognition && SongRec.running
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: songRecWrapper
                vertical: root.vertical
                MusicRecognitionIcon {
                    id: songRecIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: songRecWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    listening: SongRec.running
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showAlarms && iconDriver.alarmVisible
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: alarmWrapper
                vertical: root.vertical
                AlarmIcon {
                    id: alarmIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: alarmWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    scheduled: iconDriver.alarmCount > 0
                    ringing: iconDriver.alarmRinging
                }
            }
        }
        Revealer {
            reveal: Config.options.bar.dashboardButton.showNotifications && (Notifications.silent || Notifications.unread > 0)
            vertical: root.vertical
            ExpressiveIconWrapper {
                id: notifWrapper
                vertical: root.vertical
                BellWithBadge {
                    id: notificationIcon
                    anchors.centerIn: parent
                    iconSize: root.iconPixelSize
                    color: notifWrapper.toggled ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
                    silent: Notifications.silent
                }
            }
        }
    }
}
