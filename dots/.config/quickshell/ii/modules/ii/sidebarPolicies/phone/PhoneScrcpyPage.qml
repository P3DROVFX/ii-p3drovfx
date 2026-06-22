pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * scrcpy mirror sub-page — full configuration for launching the external
 * Android screen mirror window.
 *
 * This mirrors the structure of PhoneWebcamPage.qml / PhoneMicPage.qml:
 *   • Header with back button + status pill
 *   • Big primary Launch / Kill toggle
 *   • Quick actions (focus window, wireless ADB setup prompt)
 *   • Display settings (resolution, fps, bitrate, video buffer)
 *   • Behaviour toggles (stay awake, turn screen off, no power on,
 *     no audio, show touches, fullscreen, always on top, show terminal)
 *   • Wireless ADB section (only when enabled)
 */
ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    readonly property bool _ready: KdeConnectService.scrcpyAvailable
        && KdeConnectService.activeReachable

    // Slide-up entrance when the sub-page overlay loads.
    opacity: 0
    transform: Translate { id: pageTranslate; y: 18 }
    Component.onCompleted: pageEntranceAnim.start()
    SequentialAnimation {
        id: pageEntranceAnim
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                from: 0
                to: 1
                duration: 260
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: pageTranslate
                property: "y"
                from: 18
                to: 0
                duration: 380
                easing.type: Easing.OutBack
                easing.overshoot: 1.25
            }
        }
    }

    // ─── Header ─────────────────────────────────────────────
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

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("scrcpy Mirror")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }

        Item { Layout.fillWidth: true }

        // Status pill (running/idle/offline/unavailable)
        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: statusPill.implicitWidth + 22
            radius: Appearance.rounding.full
            color: KdeConnectService.scrcpyRunning
                ? Appearance.colors.colPrimaryContainer
                : (KdeConnectService.scrcpyAvailable ? Appearance.colors.colLayer3
                                                     : Appearance.colors.colErrorContainer)
            opacity: KdeConnectService.scrcpyRunning ? 1.0 : 0.8

            RowLayout {
                id: statusPill
                anchors.centerIn: parent
                spacing: 5

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "smart_display"
                    iconSize: 16
                    color: KdeConnectService.scrcpyRunning
                        ? Appearance.colors.colOnPrimaryContainer
                        : (KdeConnectService.scrcpyAvailable ? Appearance.colors.colOnLayer3
                                                             : Appearance.colors.colOnErrorContainer)
                    animateChange: true
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: KdeConnectService.scrcpyRunning
                        ? Translation.tr("Running")
                        : (KdeConnectService.scrcpyAvailable
                            ? (KdeConnectService.activeReachable
                                ? Translation.tr("Ready")
                                : Translation.tr("Offline"))
                            : Translation.tr("Unavailable"))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: KdeConnectService.scrcpyRunning
                        ? Appearance.colors.colOnPrimaryContainer
                        : (KdeConnectService.scrcpyAvailable ? Appearance.colors.colOnLayer3
                                                             : Appearance.colors.colOnErrorContainer)
                }
            }
        }
    }

    // ─── Error / offline banner ────────────────────────────
    WarningBox {
        Layout.fillWidth: true
        visible: !KdeConnectService.scrcpyAvailable || !KdeConnectService.activeReachable
        materialIcon: !KdeConnectService.scrcpyAvailable ? "download"
                    : "phonelink_off"
        text: !KdeConnectService.scrcpyAvailable
            ? Translation.tr("scrcpy is not installed. Install scrcpy and android-tools to mirror your phone screen.")
            : Translation.tr("No reachable KDE Connect device. Pair a device first.")

        RippleButton {
            visible: !KdeConnectService.scrcpyAvailable
            Layout.alignment: Qt.AlignRight
            Layout.preferredHeight: 32
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            contentItem: RowLayout {
                spacing: 6
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "download"
                    iconSize: 16
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Install")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            onClicked: {
                Quickshell.execDetached(["xdg-open",
                    "https://github.com/Genymobile/scrcpy"])
            }
        }
    }

    // ─── Status hero (big primary toggle) ──────────────────
    ContentSection {
        icon: "smart_display"
        title: Translation.tr("Mirror")

        // Big primary toggle button
        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            buttonRadius: Appearance.rounding.normal
            colBackground: KdeConnectService.scrcpyRunning
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colPrimaryContainer
            colBackgroundHover: KdeConnectService.scrcpyRunning
                ? Appearance.colors.colErrorContainerHover
                : Appearance.colors.colPrimaryContainerHover
            colRipple: KdeConnectService.scrcpyRunning
                ? Appearance.colors.colErrorContainerActive
                : Appearance.colors.colPrimaryContainerActive
            enabled: root._ready
            opacity: enabled ? 1.0 : 0.5

            contentItem: RowLayout {
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: KdeConnectService.scrcpyRunning ? "stop_circle" : "play_circle"
                    iconSize: 24
                    color: KdeConnectService.scrcpyRunning
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                    fill: KdeConnectService.scrcpyRunning ? 1.0 : 0.0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: KdeConnectService.scrcpyRunning
                        ? Translation.tr("Kill scrcpy")
                        : Translation.tr("Launch scrcpy")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: KdeConnectService.scrcpyRunning
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                }
            }

            onClicked: {
                if (KdeConnectService.scrcpyRunning)
                    KdeConnectService.killScrcpy()
                else
                    KdeConnectService.launchScrcpy(KdeConnectService.activeDeviceId)
            }
        }

        // Quick actions row
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                Layout.preferredHeight: 44
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: KdeConnectService.scrcpyRunning
                opacity: enabled ? 1.0 : 0.5
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "center_focus_strong"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Focus window")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
                onClicked: KdeConnectService.focusScrcpyWindow()
                StyledToolTip {
                    text: Translation.tr("Raise the existing scrcpy window")
                }
            }

            RippleButton {
                Layout.preferredHeight: 44
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: KdeConnectService.activeReachable
                opacity: enabled ? 1.0 : 0.5
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "wifi_tethering"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Wireless ADB")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
                onClicked: KdeConnectService.promptWirelessConnect(KdeConnectService.activeDeviceId)
                StyledToolTip {
                    text: Translation.tr("Prompt for IP:port and switch to wireless mode")
                }
            }

            RippleButton {
                Layout.preferredHeight: 44
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: KdeConnectService.activeReachable
                opacity: enabled ? 1.0 : 0.5
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "screenshot_monitor"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Screenshot")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
                onClicked: KdeConnectService.adbScreenshot()
                StyledToolTip {
                    text: Translation.tr("Screenshot the phone via ADB")
                }
            }
        }
    }

    // ─── Display settings ──────────────────────────────────
    ContentSection {
        icon: "video_settings"
        title: Translation.tr("Display")

        ConfigSlider {
            text: Translation.tr("Resolution limit (px)")
            buttonIcon: "crop_free"
            from: 0
            to: 1920
            stepSize: 240
            value: Config.options.phone.scrcpy.maxSize
            onValueChanged: Config.options.phone.scrcpy.maxSize = value
            usePercentTooltip: false
        }

        ConfigSlider {
            text: Translation.tr("Frame rate (fps)")
            buttonIcon: "speed"
            from: 0
            to: 120
            value: Config.options.phone.scrcpy.maxFps
            onValueChanged: Config.options.phone.scrcpy.maxFps = value
            usePercentTooltip: false
        }

        ConfigTextField {
            text: Translation.tr("Bitrate")
            icon: "network_check"
            placeholderText: "8M"
            inputText: Config.options.phone.scrcpy.bitRate
            onEditingFinished: {
                Config.options.phone.scrcpy.bitRate = inputText.trim()
            }
        }

        ConfigSlider {
            text: Translation.tr("Video buffer (ms)")
            buttonIcon: "timer"
            from: 0
            to: 200
            value: Config.options.phone.scrcpy.videoBuffer
            onValueChanged: Config.options.phone.scrcpy.videoBuffer = value
            usePercentTooltip: false
        }
    }

    // ─── Behaviour toggles ─────────────────────────────────
    ContentSection {
        icon: "settings_applications"
        title: Translation.tr("Behaviour")

        ConfigSwitch {
            buttonIcon: "coffee"
            text: Translation.tr("Stay awake")
            checked: Config.options.phone.scrcpy.stayAwake
            onCheckedChanged: Config.options.phone.scrcpy.stayAwake = checked
        }

        ConfigSwitch {
            buttonIcon: "phone_android"
            text: Translation.tr("Turn screen off")
            checked: Config.options.phone.scrcpy.turnScreenOff
            onCheckedChanged: Config.options.phone.scrcpy.turnScreenOff = checked
        }

        ConfigSwitch {
            buttonIcon: "power_off"
            text: Translation.tr("No power on")
            checked: Config.options.phone.scrcpy.noPowerOn
            onCheckedChanged: Config.options.phone.scrcpy.noPowerOn = checked
        }

        ConfigSwitch {
            buttonIcon: "volume_off"
            text: Translation.tr("No audio")
            checked: Config.options.phone.scrcpy.noAudio
            onCheckedChanged: Config.options.phone.scrcpy.noAudio = checked
        }

        ConfigSwitch {
            buttonIcon: "touch_app"
            text: Translation.tr("Show touches")
            checked: Config.options.phone.scrcpy.showTouches
            onCheckedChanged: Config.options.phone.scrcpy.showTouches = checked
        }

        ConfigSwitch {
            buttonIcon: "fullscreen"
            text: Translation.tr("Fullscreen")
            checked: Config.options.phone.scrcpy.fullscreen
            onCheckedChanged: Config.options.phone.scrcpy.fullscreen = checked
        }

        ConfigSwitch {
            buttonIcon: "push_pin"
            text: Translation.tr("Always on top")
            checked: Config.options.phone.scrcpy.alwaysOnTop
            onCheckedChanged: Config.options.phone.scrcpy.alwaysOnTop = checked
        }

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Show terminal")
            checked: Config.options.phone.scrcpy.showTerminal
            onCheckedChanged: Config.options.phone.scrcpy.showTerminal = checked
        }
    }

    // ─── Wireless ADB helper ──────────────────────────────────────
    ContentSection {
        icon: "wifi_tethering"
        title: Translation.tr("Wireless ADB Setup")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("1. Connect your phone via USB and allow ADB debugging.\n2. Enable TCP/IP mode.\n3. Disconnect USB and enter the phone's Wi-Fi IP below.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
            opacity: 0.85
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: KdeConnectService.activeReachable && KdeConnectService.adbReachable
                opacity: enabled ? 1.0 : 0.5
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "usb"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Enable over USB")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
                onClicked: KdeConnectService.enableWirelessAdb()
                StyledToolTip {
                    text: Translation.tr("Runs adb tcpip 5555 on the USB-connected phone")
                }
            }

            RippleButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: KdeConnectService.activeDevice
                            && (KdeConnectService.activeDevice.reachableAddresses || []).length > 0
                opacity: enabled ? 1.0 : 0.5
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "content_copy"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Copy IP")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
                onClicked: {
                    const ip = (KdeConnectService.activeDevice.reachableAddresses || [])[0] || ""
                    if (ip) Quickshell.clipboardText = ip
                }
                StyledToolTip {
                    text: Translation.tr("Copy the phone's LAN IP to the clipboard")
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.3
        }

        ConfigSwitch {
            buttonIcon: "wifi"
            text: Translation.tr("Use wireless ADB")
            checked: Config.options.phone.scrcpy.useWireless
            onCheckedChanged: Config.options.phone.scrcpy.useWireless = checked
        }

        ConfigTextField {
            visible: Config.options.phone.scrcpy.useWireless
            text: Translation.tr("Phone IP")
            icon: "ip"
            placeholderText: "192.168.1.42"
            inputText: Config.options.phone.scrcpy.wirelessIp
            onEditingFinished: {
                Config.options.phone.scrcpy.wirelessIp = inputText.trim()
            }
        }

        ConfigSpinBox {
            visible: Config.options.phone.scrcpy.useWireless
            text: Translation.tr("Port")
            icon: "router"
            value: Config.options.phone.scrcpy.wirelessPort
                    ? parseInt(Config.options.phone.scrcpy.wirelessPort, 10)
                    : 5555
            from: 1024
            to: 65535
            onValueChanged: Config.options.phone.scrcpy.wirelessPort = String(value)
        }
    }

    Item { Layout.preferredHeight: 24 }
}
