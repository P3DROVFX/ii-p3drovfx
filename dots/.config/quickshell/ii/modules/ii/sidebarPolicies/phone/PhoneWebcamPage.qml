pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Phone Webcam sub-page — controls for using the phone's camera as a webcam
 * via DroidCam.
 *
 * Layout:
 *   ┌── Header (back button + title) ──────┐
 *   │ Status hero (toggle / state)          │
 *   ├── Camera Settings ──────────────────────┤
 *   │  • Camera facing (front/back)         │
 *   │  • Connection (wifi/usb)              │
 *   │  • Resolution                         │
 *   │  • FPS                                │
 *   │  • Mirror toggle                      │
 *   │  • Rotation                           │
 *   ├── Quick Actions ──────────────────────┤
 *   │  • Flip camera                        │
 *   │  • Toggle mirror                      │
 *   │  • Open in app                        │
 *   └───────────────────────────────────────┘
 *
 * Empty/error states:
 *   • DroidCam not installed → banner + install button.
 *   • No reachable KDE Connect device → offline banner.
 *   • Connecting → spinner.
 *   • Last error → red banner with the message.
 */
ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    readonly property bool _ready: PhoneCameraService.available
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
            text: Translation.tr("Phone Webcam")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }

        Item { Layout.fillWidth: true }

        // Status pill (active/idle/offline/unavailable)
        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: statusPill.implicitWidth + 22
            radius: Appearance.rounding.full
            color: PhoneCameraService.running
                ? Appearance.colors.colPrimaryContainer
                : (PhoneCameraService.available ? Appearance.colors.colLayer3
                                                : Appearance.colors.colErrorContainer)
            opacity: PhoneCameraService.connecting ? 0.6 : 1.0

            RowLayout {
                id: statusPill
                anchors.centerIn: parent
                spacing: 5

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: PhoneCameraService.connecting ? "sync"
                        : (PhoneCameraService.running ? "videocam" : "videocam_off")
                    iconSize: 16
                    color: PhoneCameraService.running
                        ? Appearance.colors.colOnPrimaryContainer
                        : (PhoneCameraService.available ? Appearance.colors.colOnLayer3
                                                        : Appearance.colors.colOnErrorContainer)
                    animateChange: true

                    RotationAnimation on rotation {
                        running: PhoneCameraService.connecting
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1100
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: PhoneCameraService.connecting
                        ? Translation.tr("Connecting…")
                        : (PhoneCameraService.running
                            ? Translation.tr("Active")
                            : (PhoneCameraService.available
                                ? Translation.tr("Ready")
                                : Translation.tr("Unavailable")))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: PhoneCameraService.running
                        ? Appearance.colors.colOnPrimaryContainer
                        : (PhoneCameraService.available ? Appearance.colors.colOnLayer3
                                                        : Appearance.colors.colOnErrorContainer)
                }
            }
        }
    }

    // ─── Error / offline banner ────────────────────────────
    WarningBox {
        Layout.fillWidth: true
        visible: !PhoneCameraService.available || !KdeConnectService.activeReachable
                || PhoneCameraService.lastError.length > 0
        materialIcon: !PhoneCameraService.available ? "download"
                    : !KdeConnectService.activeReachable ? "phonelink_off"
                    : "error"
        text: !PhoneCameraService.available
            ? Translation.tr("DroidCam is not installed. Install droidcam-cli and the DroidCam Android app to use your phone camera as a webcam.")
            : !KdeConnectService.activeReachable
                ? Translation.tr("No reachable KDE Connect device. Pair a device to use its camera.")
                : Translation.tr("Camera error: %1").arg(PhoneCameraService.lastError)

        // Inline install button (only when unavailable)
        RippleButton {
            visible: !PhoneCameraService.available
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
        icon: "videocam"
        title: Translation.tr("Camera")

        // Big primary toggle button
        RippleButton {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            buttonRadius: Appearance.rounding.normal
            colBackground: PhoneCameraService.running
                ? Appearance.colors.colErrorContainer
                : Appearance.colors.colPrimaryContainer
            colBackgroundHover: PhoneCameraService.running
                ? Appearance.colors.colErrorContainerHover
                : Appearance.colors.colPrimaryContainerHover
            colRipple: PhoneCameraService.running
                ? Appearance.colors.colErrorContainerActive
                : Appearance.colors.colPrimaryContainerActive
            enabled: root._ready
            opacity: enabled ? 1.0 : 0.5

            contentItem: RowLayout {
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: PhoneCameraService.connecting ? "sync"
                        : (PhoneCameraService.running ? "stop_circle" : "play_circle")
                    iconSize: 24
                    color: PhoneCameraService.running
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                    fill: PhoneCameraService.running ? 1.0 : 0.0

                    RotationAnimation on rotation {
                        running: PhoneCameraService.connecting
                        loops: Animation.Infinite
                        from: 0; to: 360
                        duration: 1100
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: PhoneCameraService.connecting
                        ? Translation.tr("Connecting…")
                        : (PhoneCameraService.running
                            ? Translation.tr("Stop camera")
                            : Translation.tr("Start camera"))
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: PhoneCameraService.running
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                }
                Loader {
                    Layout.alignment: Qt.AlignVCenter
                    active: PhoneCameraService.running && PhoneCameraService.videoDevice.length > 0
                    visible: active
                    sourceComponent: Component {
                        StyledText {
                            text: PhoneCameraService.videoDevice
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnErrorContainer
                            opacity: 0.7
                        }
                    }
                }
            }

            onClicked: PhoneCameraService.toggleCamera()
        }

        // Quick action row: Flip, Mirror, Open
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                Layout.preferredHeight: 44
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: root._ready
                opacity: enabled ? 1.0 : 0.5
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "cameraswitch"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                        animateChange: true
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Flip camera")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
                onClicked: PhoneCameraService.flipCamera()
                StyledToolTip {
                    text: Translation.tr("Switch between front and back camera")
                }
            }

            RippleButton {
                Layout.preferredHeight: 44
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: root._ready
                opacity: enabled ? 1.0 : 0.5
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "flip"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                        animateChange: true
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Config.options.phone.webcam.mirrorHorizontally
                            ? Translation.tr("Unmirror")
                            : Translation.tr("Mirror")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
                onClicked: PhoneCameraService.toggleMirror()
                StyledToolTip {
                    text: Translation.tr("Flip the image horizontally")
                }
            }

            RippleButton {
                Layout.preferredHeight: 44
                Layout.fillWidth: true
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                enabled: PhoneCameraService.running
                    && PhoneCameraService.videoDevice.length > 0
                opacity: enabled ? 1.0 : 0.5
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "open_in_new"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                        animateChange: true
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Test")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                }
                onClicked: {
                    Quickshell.execDetached(["bash", "-c",
                        "command -v cheese >/dev/null && cheese || " +
                        "command -v obs >/dev/null && obs || " +
                        "command -v guvcview >/dev/null && guvcview || " +
                        "xdg-open 'https://webcamtests.com'"])
                }
                StyledToolTip {
                    text: Translation.tr("Open a webcam app to test the camera")
                }
            }
        }
    }

    // ─── Camera settings ───────────────────────────────────
    ContentSection {
        icon: "video_settings"
        title: Translation.tr("Camera Settings")

        // Camera facing: front / back
        ConfigSelectionArray {
            text: Translation.tr("Camera")
            icon: "camera_front"
            options: [
                { displayName: Translation.tr("Front"), icon: "camera_front", value: "front" },
                { displayName: Translation.tr("Back"), icon: "camera_rear", value: "back" }
            ]
            currentValue: Config.options.phone.webcam.cameraFacing
            onSelected: (v) => {
                Config.options.phone.webcam.cameraFacing = v
                // DroidCam does not have a CLI flag to switch cameras.
                // Persist the preference so the next fresh start uses it,
                // but do NOT restart the running stream.
                // See AGENTS.md Phone Module Round 5.
                PhoneCameraService.flipCamera()
            }
        }

        // Connection
        ConfigSelectionArray {
            text: Translation.tr("Connection")
            icon: "cable"
            options: [
                { displayName: Translation.tr("Wi-Fi"), icon: "wifi", value: "wifi" },
                { displayName: Translation.tr("USB"), icon: "usb", value: "usb" }
            ]
            currentValue: Config.options.phone.webcam.connection
            onSelected: (v) => Config.options.phone.webcam.connection = v
        }

        // Resolution
        ConfigSelectionArray {
            text: Translation.tr("Resolution")
            icon: "aspect_ratio"
            options: [
                { displayName: "480p", value: "640x480" },
                { displayName: "720p", value: "1280x720" },
                { displayName: "1080p", value: "1920x1080" }
            ]
            currentValue: Config.options.phone.webcam.resolution
            onSelected: (v) => Config.options.phone.webcam.resolution = v
        }

        // Mirror toggle
        ConfigSwitch {
            buttonIcon: "flip"
            text: Translation.tr("Mirror horizontally")
            checked: Config.options.phone.webcam.mirrorHorizontally
            onCheckedChanged: {
                Config.options.phone.webcam.mirrorHorizontally = checked
            }
        }

        // Rotation
        ConfigSelectionArray {
            text: Translation.tr("Rotation")
            icon: "rotate_right"
            options: [
                { displayName: "0°", value: 0 },
                { displayName: "90°", value: 90 },
                { displayName: "180°", value: 180 },
                { displayName: "270°", value: 270 }
            ]
            currentValue: Config.options.phone.webcam.rotateDegrees
            onSelected: (v) => PhoneCameraService.setRotation(v)
        }
    }

    // ─── Wi-Fi settings (only visible in WiFi mode) ────────
    ContentSection {
        icon: "wifi"
        title: Translation.tr("Connection")
        visible: Config.options.phone.webcam.connection === "wifi"

        ConfigTextField {
            text: Translation.tr("Phone IP")
            icon: "ip"
            placeholderText: Translation.tr("Auto-detect from KDE Connect")
            inputText: Config.options.phone.webcam.wifiIp
            onEditingFinished: {
                Config.options.phone.webcam.wifiIp = inputText.trim()
            }
            tooltip: Translation.tr("Leave empty to auto-detect from KDE Connect. Set explicitly if auto-detect fails.")
        }

        ConfigSpinBox {
            text: Translation.tr("Port")
            icon: "router"
            value: Config.options.phone.webcam.port
            from: 1024
            to: 65535
            onValueChanged: Config.options.phone.webcam.port = value
        }
    }

    // ─── Quality ───────────────────────────────────────────
    ContentSection {
        icon: "tune"
        title: Translation.tr("Quality")

        ConfigSlider {
            text: Translation.tr("Frame rate (fps)")
            buttonIcon: "speed"
            from: 10
            to: 60
            value: Config.options.phone.webcam.fps
            onValueChanged: Config.options.phone.webcam.fps = value
            usePercentTooltip: false
        }
    }

    Item { Layout.preferredHeight: 24 }
}
