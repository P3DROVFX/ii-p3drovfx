import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.bar.widgets.dashboard.icons

ContentPage {
    id: root

    signal goBack()

    forceWidth: false

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

        }

        StyledText {
            text: Translation.tr("Dashboard Panel Button")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }

    }

    ContentSection {
        icon: "space_dashboard"
        title: Translation.tr("Visible Indicators")

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            text: Translation.tr("Choose which quick status indicators appear inside the dashboard panel button on the bar.")
        }

        ConfigSwitch {
            buttonIcon: "coffee"
            text: Translation.tr("Show Keep Awake")
            checked: Config.options.bar.dashboardButton.showCaffeine
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showCaffeine = checked;
            }
            StyledToolTip { text: Translation.tr("Show the coffee icon while the idle inhibitor is on") }
        }

        ConfigSwitch {
            buttonIcon: "volume_up"
            text: Translation.tr("Show Volume")
            checked: Config.options.bar.dashboardButton.showVolume
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showVolume = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "mic"
            text: Translation.tr("Show Microphone")
            checked: Config.options.bar.dashboardButton.showMic
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showMic = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "wifi"
            text: Translation.tr("Show Network")
            checked: Config.options.bar.dashboardButton.showNetwork
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showNetwork = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "bluetooth"
            text: Translation.tr("Show Bluetooth")
            checked: Config.options.bar.dashboardButton.showBluetooth
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showBluetooth = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "vpn_lock"
            text: Translation.tr("Show VPN status")
            checked: Config.options.bar.dashboardButton.showVpn
            onCheckedChanged: Config.options.bar.dashboardButton.showVpn = checked
            StyledToolTip { text: Translation.tr("Show the VPN icon when a VPN connection is active") }
        }

        ConfigSwitch {
            buttonIcon: "hub"
            text: Translation.tr("Show Tailscale status")
            checked: Config.options.bar.dashboardButton.showTailscale
            onCheckedChanged: Config.options.bar.dashboardButton.showTailscale = checked
            StyledToolTip { text: Translation.tr("Show the Tailscale icon when the mesh is connected") }
        }

        ConfigSwitch {
            buttonIcon: "timer"
            text: Translation.tr("Show Pomodoro")
            checked: Config.options.bar.dashboardButton.showPomodoro
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showPomodoro = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "timer"
            text: Translation.tr("Show Stopwatch")
            checked: Config.options.bar.dashboardButton.showStopwatch
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showStopwatch = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "hourglass_top"
            text: Translation.tr("Show Countdown Timers")
            checked: Config.options.bar.dashboardButton.showCountdowns
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showCountdowns = checked;
            }
            StyledToolTip { text: Translation.tr("Show the hourglass while at least one countdown timer exists") }
        }

        ConfigSwitch {
            buttonIcon: "alarm"
            text: Translation.tr("Show System Alarms")
            checked: Config.options.bar.dashboardButton.showAlarms
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showAlarms = checked;
            }
            StyledToolTip { text: Translation.tr("Show the alarm icon while at least one system alarm is defined") }
        }

        ConfigSwitch {
            buttonIcon: "graphic_eq"
            text: Translation.tr("Show EasyEffects")
            checked: Config.options.bar.dashboardButton.showEasyEffects
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showEasyEffects = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "encrypted"
            text: Translation.tr("Show Encrypted DNS")
            checked: Config.options.bar.dashboardButton.showDns
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showDns = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "gamepad"
            text: Translation.tr("Show Game mode")
            checked: Config.options.bar.dashboardButton.showGameMode
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showGameMode = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "music_cast"
            text: Translation.tr("Show Identify Music")
            checked: Config.options.bar.dashboardButton.showMusicRecognition
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showMusicRecognition = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show Notifications")
            checked: Config.options.bar.dashboardButton.showNotifications
            onCheckedChanged: {
                Config.options.bar.dashboardButton.showNotifications = checked;
            }
        }

    }

    ContentSection {
        icon: "animation"
        title: Translation.tr("Icon animations")

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            materialIcon: "play_circle"
            text: Translation.tr("Each button fires the same cue a real state change fires. The icon beside it previews the animation, and the button on the bar plays it at the same time.")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                model: DashboardIconCues.catalog.length

                delegate: Rectangle {
                    id: cueRow

                    required property int index
                    readonly property var cueGroup: DashboardIconCues.catalog[cueRow.index]

                    Layout.fillWidth: true
                    implicitHeight: rowLayout.implicitHeight + 24
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        id: rowLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 14

                        // Live preview. The icons listen to the cue bus
                        // themselves, so nothing here has to wire them up.
                        Rectangle {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            Layout.alignment: Qt.AlignVCenter
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colSurfaceContainerHighest

                            Loader {
                                anchors.centerIn: parent
                                sourceComponent: {
                                    switch (String(cueRow.cueGroup.channel)) {
                                    case "wifi":
                                        return wifiPreview;
                                    case "bluetooth":
                                        return bluetoothPreview;
                                    case "volume":
                                        return volumePreview;
                                    case "mic":
                                        return micPreview;
                                    case "caffeine":
                                        return coffeePreview;
                                    case "vpn":
                                        return vpnPreview;
                                    case "tailscale":
                                        return tailscalePreview;
                                    case "pomodoro":
                                        return timerPreview;
                                    case "stopwatch":
                                        return stopwatchPreview;
                                    case "countdown":
                                        return countdownPreview;
                                    case "easyeffects":
                                        return equalizerPreview;
                                    case "dns":
                                        return dnsPreview;
                                    case "warp":
                                        return warpPreview;
                                    case "gamemode":
                                        return gamepadPreview;
                                    case "songrec":
                                        return songrecPreview;
                                    case "alarm":
                                        return alarmPreview;
                                    default:
                                        return bellPreview;
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledText {
                                text: Translation.tr(String(cueRow.cueGroup.title))
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.bold: true
                                color: Appearance.colors.colOnLayer2
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: cueRow.cueGroup.cues.length

                                    delegate: RippleButton {
                                        id: cueButton

                                        required property int index
                                        readonly property var cue: cueRow.cueGroup.cues[cueButton.index]

                                        implicitHeight: 32
                                        implicitWidth: cueLabel.implicitWidth + 26
                                        buttonRadius: Appearance.rounding.full
                                        colBackground: Appearance.colors.colSecondaryContainer
                                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                                        colRipple: Appearance.colors.colSecondaryContainerActive
                                        onClicked: DashboardIconCues.play(String(cueRow.cueGroup.channel), String(cueButton.cue.name))

                                        contentItem: StyledText {
                                            id: cueLabel
                                            anchors.centerIn: parent
                                            text: Translation.tr(String(cueButton.cue.label))
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnSecondaryContainer
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: wifiPreview
        WifiIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: bluetoothPreview
        BluetoothIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: volumePreview
        VolumeIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: micPreview
        MicIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: coffeePreview
        CoffeeIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: vpnPreview
        VpnKeyIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: tailscalePreview
        TailscaleIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: timerPreview
        TimerIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: stopwatchPreview
        StopwatchIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: countdownPreview
        HourglassIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: equalizerPreview
        EqualizerIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: dnsPreview
        EncryptedDnsIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: warpPreview
        CloudLockIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: gamepadPreview
        GamepadIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: songrecPreview
        MusicRecognitionIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: alarmPreview
        AlarmIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }
    Component {
        id: bellPreview
        BellIcon {
            iconSize: 26
            color: Appearance.colors.colOnSurface
        }
    }

    ShortcutBox {
        Layout.fillWidth: true
        text: Translation.tr("Looking for Sidebars settings?")
        value: Translation.tr("Sidebars")
        targetPageId: "sidebars"
        materialIcon: "side_navigation"
    }

}
