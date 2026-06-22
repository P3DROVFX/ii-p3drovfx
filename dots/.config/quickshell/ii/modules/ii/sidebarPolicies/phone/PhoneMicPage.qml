pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Phone Microphone sub-page — controls for using the phone as a microphone
 * input via DroidCam audio mode + PipeWire/PulseAudio null-sink routing.
 *
 * Layout:
 *   ┌── Header (back button + title) ──────────┐
 *   │ Status pill (active/disconnected/...)     │
 *   ├── Error / offline banner (conditional) ──┤
 *   ├── Status hero (big toggle + mute button)  │
 *   │  Active source shown when running          │
 *   ├── Microphone Control ─────────────────────┤
 *   │  • Mute toggle                            │
 *   │  • Gain slider (0-200%)                   │
 *   │  • Set as default input                   │
 *   ├── Audio Effects ──────────────────────────┤
 *   │  • Noise suppression                      │
 *   │  • Echo cancellation                      │
 *   │  • Auto gain control                      │
 *   ├── Connection ────────────────────────────┤
 *   │  • Wi-Fi IP                               │
 *   │  • Port                                   │
 *   └───────────────────────────────────────────┘
 */
ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    readonly property bool _ready: PhoneMicService.available
        && KdeConnectService.activeReachable

    property list<var> _peakHistory: []

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
            text: Translation.tr("Phone Microphone")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }

        Item { Layout.fillWidth: true }

        // Status pill
        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: micStatusPill.implicitWidth + 22
            radius: Appearance.rounding.full
            color: PhoneMicService.running
                ? (PhoneMicService.muted
                    ? Appearance.colors.colTertiaryContainer
                    : Appearance.colors.colPrimaryContainer)
                : (PhoneMicService.available ? Appearance.colors.colLayer3
                                            : Appearance.colors.colErrorContainer)
            opacity: PhoneMicService.connecting ? 0.6 : 1.0

            RowLayout {
                id: micStatusPill
                anchors.centerIn: parent
                spacing: 5

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: PhoneMicService.connecting ? "sync"
                        : (PhoneMicService.running
                            ? (PhoneMicService.muted ? "mic_off" : "mic")
                            : "mic_off")
                    iconSize: 16
                    color: PhoneMicService.running
                        ? (PhoneMicService.muted
                            ? Appearance.colors.colOnTertiaryContainer
                            : Appearance.colors.colOnPrimaryContainer)
                        : (PhoneMicService.available ? Appearance.colors.colOnLayer3
                                                    : Appearance.colors.colOnErrorContainer)
                    animateChange: true

                    RotationAnimation on rotation {
                        running: PhoneMicService.connecting
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 1100
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: PhoneMicService.connecting
                        ? Translation.tr("Connecting…")
                        : (PhoneMicService.running
                            ? (PhoneMicService.muted ? Translation.tr("Muted") : Translation.tr("Active"))
                            : (PhoneMicService.available
                                ? Translation.tr("Ready")
                                : Translation.tr("Unavailable")))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: PhoneMicService.running
                        ? (PhoneMicService.muted
                            ? Appearance.colors.colOnTertiaryContainer
                            : Appearance.colors.colOnPrimaryContainer)
                        : (PhoneMicService.available ? Appearance.colors.colOnLayer3
                                                    : Appearance.colors.colOnErrorContainer)
                }
            }
        }
    }

    // ─── Error / offline banner ────────────────────────────
    WarningBox {
        Layout.fillWidth: true
        visible: !PhoneMicService.available
                || !KdeConnectService.activeReachable
                || PhoneMicService.lastError.length > 0
        materialIcon: !PhoneMicService.available ? "download"
                    : !KdeConnectService.activeReachable ? "phonelink_off"
                    : "error"
        text: !PhoneMicService.available
            ? Translation.tr("DroidCam or pactl is not installed. Install droidcam-cli and pactl, plus the DroidCam Android app, to use your phone as a microphone.")
            : !KdeConnectService.activeReachable
                ? Translation.tr("No reachable KDE Connect device. Pair a device to use its microphone.")
                : Translation.tr("Microphone error: %1").arg(PhoneMicService.lastError)

        RippleButton {
            visible: !PhoneMicService.available
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
                const terminal = (Config.options.apps && Config.options.apps.terminal) || "kitty -1"
                const scriptPath = Directories.scriptPath + "/phone/install_droidcam.sh"
                Quickshell.execDetached(["bash", "-c",
                    terminal + " -e bash " + scriptPath + " &"])
            }
        }
    }

    // ─── Status hero (big primary toggle) ──────────────────
    ContentSection {
        icon: "mic"
        title: Translation.tr("Microphone")

        // Big primary toggle button
        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            buttonRadius: Appearance.rounding.normal
            colBackground: PhoneMicService.running
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colPrimaryContainer
            colBackgroundHover: PhoneMicService.running
                ? Appearance.colors.colErrorContainerHover
                : Appearance.colors.colPrimaryContainerHover
            colRipple: PhoneMicService.running
                ? Appearance.colors.colErrorContainerActive
                : Appearance.colors.colPrimaryContainerActive
            enabled: root._ready
            opacity: enabled ? 1.0 : 0.5

            contentItem: RowLayout {
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: PhoneMicService.connecting ? "sync"
                        : (PhoneMicService.running ? "stop_circle" : "play_circle")
                    iconSize: 24
                    color: PhoneMicService.running
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                    fill: PhoneMicService.running ? 1.0 : 0.0

                    RotationAnimation on rotation {
                        running: PhoneMicService.connecting
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 1100
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: PhoneMicService.connecting
                        ? Translation.tr("Connecting…")
                        : (PhoneMicService.running
                            ? Translation.tr("Stop microphone")
                            : Translation.tr("Start microphone"))
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: PhoneMicService.running
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                }
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    active: PhoneMicService.running && PhoneMicService.pulseSource.length > 0
                    visible: active
                    sourceComponent: Component {
                        StyledText {
                            text: PhoneMicService.pulseSource.split(".").slice(-2).join(".")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnErrorContainer
                            opacity: 0.7
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }
            }

            onClicked: PhoneMicService.toggleMic()
        }

        // Quick mute toggle (only when running)
        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            buttonRadius: Appearance.rounding.normal
            colBackground: PhoneMicService.muted
                ? Appearance.colors.colTertiaryContainer
                : Appearance.colors.colLayer2
            colBackgroundHover: PhoneMicService.muted
                ? Appearance.colors.colTertiaryContainerHover
                : Appearance.colors.colLayer2Hover
            enabled: PhoneMicService.running
            opacity: enabled ? 1.0 : 0.5

            contentItem: RowLayout {
                spacing: 8
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: PhoneMicService.muted ? "mic_off" : "mic"
                    iconSize: 22
                    color: PhoneMicService.muted
                        ? Appearance.colors.colOnTertiaryContainer
                        : Appearance.colors.colOnLayer2
                    fill: PhoneMicService.muted ? 1.0 : 0.0
                    animateChange: true
                }
                StyledText {
                    Layout.fillWidth: true
                    text: PhoneMicService.muted
                        ? Translation.tr("Unmute microphone")
                        : Translation.tr("Mute microphone")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: PhoneMicService.muted
                        ? Appearance.colors.colOnTertiaryContainer
                        : Appearance.colors.colOnLayer2
                }
            }

            onClicked: PhoneMicService.toggleMute()
        }
    }

    // ─── Microphone Control ────────────────────────────────
    ContentSection {
        icon: "tune"
        title: Translation.tr("Microphone Control")

        // Gain slider (0-200%)
        ConfigSlider {
            text: Translation.tr("Input volume")
            buttonIcon: "volume_up"
            from: 0
            to: 200
            value: Config.options.phone.microphone.micGain
            usePercentTooltip: true
            onValueChanged: {
                Config.options.phone.microphone.micGain = value
                PhoneMicService.setGain(value)
            }
            enabled: PhoneMicService.running
            opacity: enabled ? 1.0 : 0.5
        }

        // Set as default input
        ConfigSwitch {
            buttonIcon: "star"
            text: Translation.tr("Set as default input")
            checked: PhoneMicService.defaultOverridden
            enabled: PhoneMicService.running
            opacity: enabled ? 1.0 : 0.5
            onCheckedChanged: {
                if (checked) PhoneMicService.overrideDefaultSource()
                else PhoneMicService.restoreDefaultSource()
            }
            StyledToolTip {
                text: Translation.tr("Sets the phone as the default audio input while running. Other apps will use it automatically.")
            }
        }
    }

    // ─── Audio Effects ─────────────────────────────────────
    ContentSection {
        icon: "graphic_eq"
        title: Translation.tr("Audio Effects")

        ConfigSwitch {
            buttonIcon: "noise_aware"
            text: Translation.tr("Noise suppression")
            checked: Config.options.phone.microphone.noiseSuppression
            onCheckedChanged: {
                Config.options.phone.microphone.noiseSuppression = checked
            }
            StyledToolTip {
                text: Translation.tr("Reduces background noise from the microphone stream")
            }
        }

        ConfigSwitch {
            buttonIcon: "record_voice_over"
            text: Translation.tr("Echo cancellation")
            checked: Config.options.phone.microphone.echoCancellation
            onCheckedChanged: {
                Config.options.phone.microphone.echoCancellation = checked
            }
            StyledToolTip {
                text: Translation.tr("Cancels echo so speakers don't feed back into the mic")
            }
        }

        ConfigSwitch {
            buttonIcon: "trending_up"
            text: Translation.tr("Auto gain control")
            checked: Config.options.phone.microphone.autoGainControl
            onCheckedChanged: {
                Config.options.phone.microphone.autoGainControl = checked
            }
            StyledToolTip {
                text: Translation.tr("Automatically adjusts the input level based on signal volume")
            }
        }
    }

    // ─── Input level visualizer ────────────────────────────
    ContentSection {
        icon: "equalizer"
        title: Translation.tr("Input level")
        visible: PhoneMicService.running
        height: visible ? implicitHeight : 0

        Timer {
            interval: 80
            repeat: true
            running: PhoneMicService.running
            onTriggered: {
                const arr = root._peakHistory.slice()
                arr.push(PhoneMicService.peakVolumePercent)
                if (arr.length > 40) arr.shift()
                root._peakHistory = arr
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            WaveVisualizer {
                anchors.fill: parent
                maxVisualizerValue: 100
                color: Appearance.m3colors.m3primary
                points: root._peakHistory
            }
        }
    }

    // ─── Connection ────────────────────────────────────────
    ContentSection {
        icon: "cable"
        title: Translation.tr("Connection")

        ConfigSelectionArray {
            text: Translation.tr("Connection type")
            icon: "router"
            options: [
                { displayName: Translation.tr("Wi-Fi"), icon: "wifi", value: "wifi" },
                { displayName: Translation.tr("USB"), icon: "usb", value: "usb" }
            ]
            currentValue: Config.options.phone.microphone.connection
            onSelected: (v) => Config.options.phone.microphone.connection = v
        }

        ConfigTextField {
            visible: Config.options.phone.microphone.connection === "wifi"
            text: Translation.tr("Phone IP")
            icon: "ip"
            placeholderText: Translation.tr("Auto-detect from KDE Connect")
            inputText: Config.options.phone.microphone.wifiIp
            onEditingFinished: {
                Config.options.phone.microphone.wifiIp = inputText.trim()
            }
            tooltip: Translation.tr("Leave empty to auto-detect from KDE Connect")
        }

        ConfigSpinBox {
            text: Translation.tr("Port")
            icon: "router"
            value: Config.options.phone.microphone.port
            from: 1024
            to: 65535
            onValueChanged: Config.options.phone.microphone.port = value
        }
    }

    Item { Layout.preferredHeight: 24 }
}
