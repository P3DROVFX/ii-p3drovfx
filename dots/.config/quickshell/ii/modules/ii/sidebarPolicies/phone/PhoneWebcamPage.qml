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
 * via ii tools or DroidCam.
 */
ContentPage {
    id: root
    forceWidth: false
    signal goBack()

    readonly property bool _iiBackend: PhoneCameraService.backend === "ii"
    readonly property var _iiStatus: IiCameraService.phoneStatus || ({})
    readonly property bool _noCameraCap: root._iiBackend && IiCameraService.connected && !IiCameraService.hasCameraCap
    readonly property bool _ready: PhoneCameraService.available
        && KdeConnectService.activeReachable
        && !root._noCameraCap
    property string _selectedDistro: PhoneCameraService.detectedDistro !== "unknown"
        ? PhoneCameraService.detectedDistro : "arch"

    Connections {
        target: PhoneCameraService
        function onDetectedDistroChanged() {
            if (PhoneCameraService.detectedDistro && PhoneCameraService.detectedDistro !== "unknown")
                root._selectedDistro = PhoneCameraService.detectedDistro
        }
    }

    function _lensLabel(lens: string): string {
        switch (lens) {
        case "front": return Translation.tr("Front");
        case "main": return Translation.tr("Main");
        case "wide": return Translation.tr("Wide");
        case "tele": return Translation.tr("Tele");
        default: return lens;
        }
    }

    function _lensIcon(lens: string): string {
        return lens === "front" ? "camera_front" : "camera_rear";
    }

    readonly property var _lensOptions: {
        const raw = (root._iiStatus && Array.isArray(root._iiStatus.lenses) && root._iiStatus.lenses.length > 0)
            ? root._iiStatus.lenses
            : ["front", "main"];
        return raw.map(l => {
            const name = String(l);
            return { displayName: root._lensLabel(name), icon: root._lensIcon(name), value: name };
        });
    }

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

                AnimatedMaterialSymbol {
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
                    text: (root._iiBackend && IiCameraService.state === "asking")
                        ? Translation.tr("Confirm on phone…")
                        : PhoneCameraService.connecting
                            ? Translation.tr("Connecting…")
                            : (PhoneCameraService.running
                                ? Translation.tr("Active")
                                : (!PhoneCameraService.available
                                    ? Translation.tr("Unavailable")
                                    : (!KdeConnectService.activeReachable
                                        ? Translation.tr("Offline")
                                        : (root._noCameraCap
                                            ? Translation.tr("Update app")
                                            : Translation.tr("Ready")))))
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
                || root._noCameraCap || PhoneCameraService.lastError.length > 0
        materialIcon: !PhoneCameraService.available ? "download"
                    : !KdeConnectService.activeReachable ? "phonelink_off"
                    : root._noCameraCap ? "system_update"
                    : "error"
        text: !PhoneCameraService.available
            ? (root._iiBackend
                ? (!IiCameraService.ffmpegPresent
                    ? Translation.tr("Install FFmpeg and %1 using the commands below, then click Re-check.")
                        .arg(IiCameraService.output === "pipewire" ? Translation.tr("GStreamer's PipeWire plugin") : "v4l2loopback")
                    : !IiCameraService.ffmpegHasH264
                        ? Translation.tr("Your FFmpeg build cannot decode H.264. Replace it using the command below, then click Re-check.")
                        : IiCameraService.output === "pipewire"
                            ? Translation.tr("Install GStreamer's PipeWire and bad plugins using the command below, then click Re-check.")
                            : Translation.tr("Install the v4l2loopback kernel module using the command below, then click Re-check."))
                : Translation.tr("DroidCam is not installed. Install droidcam-cli and the DroidCam Android app to use your phone camera as a webcam."))
            : !KdeConnectService.activeReachable
                ? (root._iiBackend
                    ? (!IiLinkService.hasPeers
                        ? Translation.tr("No phone paired. Pair one in Settings → ii tools to use its camera.")
                        : Translation.tr("Phone is offline. Open ii tools on your phone or connect both devices to the same network."))
                    : Translation.tr("No reachable phone. Pair one to use its camera."))
                : root._noCameraCap
                    ? Translation.tr("Update ii tools on your phone to use its camera.")
                    : (root._iiBackend
                        ? PhoneCameraService.lastError
                        : Translation.tr("Camera error: %1").arg(PhoneCameraService.lastError))

        // Inline action button (only when unavailable)
        RippleButton {
            visible: !PhoneCameraService.available && !root._iiBackend
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

        RippleButton {
            visible: root._iiBackend && (!PhoneCameraService.available || (PhoneCameraService.lastError.length > 0 && PhoneCameraService.missingDeps.length > 0))
            Layout.alignment: Qt.AlignRight
            Layout.preferredHeight: 32
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            contentItem: RowLayout {
                spacing: 6
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "refresh"
                    iconSize: 16
                    color: Appearance.colors.colOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Re-check")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            onClicked: PhoneCameraService.refresh()
        }
    }

    // ─── ii tools missing dependency commands ──────────────
    ContentSection {
        visible: root._iiBackend && (!PhoneCameraService.available || PhoneCameraService.lastError.length > 0) && PhoneCameraService.missingDeps.length > 0
        icon: "terminal"
        title: Translation.tr("Required Packages")

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { key: "arch", label: "Arch" },
                    { key: "fedora", label: "Fedora" },
                    { key: "debian", label: "Debian" },
                    { key: "opensuse", label: "openSUSE" }
                ]
                delegate: RippleButton {
                    required property var modelData
                    height: 28
                    leftPadding: 12
                    rightPadding: 12
                    buttonRadius: Appearance.rounding.full
                    colBackground: root._selectedDistro === modelData.key
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colLayer2
                    colBackgroundHover: root._selectedDistro === modelData.key
                        ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colLayer2Hover
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: modelData.label
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: root._selectedDistro === modelData.key ? Font.DemiBold : Font.Normal
                        color: root._selectedDistro === modelData.key
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnLayer2
                    }
                    onClicked: root._selectedDistro = modelData.key
                }
            }
        }

        Repeater {
            model: PhoneCameraService.missingDeps
            delegate: ColumnLayout {
                id: depCard
                required property var modelData
                readonly property string installCmd: {
                    const cmds = depCard.modelData.installCommands;
                    if (!cmds) return "";
                    return cmds[root._selectedDistro] || "";
                }
                Layout.fillWidth: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    text: depCard.modelData.name || depCard.modelData.key || ""
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: (depCard.modelData.description || "").length > 0
                    text: depCard.modelData.description || ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                RippleButton {
                    Layout.fillWidth: true
                    visible: depCard.installCmd.length > 0
                    implicitHeight: cmdText.implicitHeight + 16
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: Quickshell.clipboardText = depCard.installCmd
                    contentItem: RowLayout {
                        spacing: 8
                        StyledText {
                            id: cmdText
                            Layout.fillWidth: true
                            text: depCard.installCmd
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer2
                            wrapMode: Text.Wrap
                        }
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "content_copy"
                            iconSize: 16
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                    StyledToolTip {
                        text: Translation.tr("Copy install command")
                    }
                }
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
                    text: (root._iiBackend && IiCameraService.state === "asking")
                        ? Translation.tr("Confirm on your phone…")
                        : PhoneCameraService.connecting
                            ? (root._iiBackend ? Translation.tr("Starting…") : Translation.tr("Connecting…"))
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
                    AnimatedMaterialSymbol {
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
                    AnimatedMaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "flip"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer2
                        animateChange: true
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: PhoneCameraService.mirrored
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
                    AnimatedMaterialSymbol {
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

        // ii tools: Lens selector
        ContentSubsection {
            visible: root._iiBackend
            title: Translation.tr("Lens")
            icon: "camera_front"

            ConfigSelectionArray {
                options: root._lensOptions
                currentValue: String(root._iiStatus.lens || "front")
                onSelected: (v) => IiCameraService.set({ lens: v })
            }
        }

        // ii tools: Aspect ratio
        ContentSubsection {
            visible: root._iiBackend
            title: Translation.tr("Aspect ratio")
            icon: "aspect_ratio"

            ConfigSelectionArray {
                options: [
                    { displayName: "4:3", value: "4:3" },
                    { displayName: "16:9", value: "16:9" }
                ]
                currentValue: String(root._iiStatus.aspect || "16:9")
                onSelected: (v) => IiCameraService.set({ aspect: v })
            }
        }

        // ii tools: Quality
        ContentSubsection {
            visible: root._iiBackend
            title: Translation.tr("Quality")
            icon: "hd"

            ConfigSelectionArray {
                options: [
                    { displayName: "720p", value: "720p" },
                    { displayName: "1080p", value: "1080p" }
                ]
                currentValue: String(root._iiStatus.quality || "720p")
                onSelected: (v) => IiCameraService.set({ quality: v })
            }
        }

        // ii tools: Torch (shown only when current lens has a torch)
        ConfigSwitch {
            visible: root._iiBackend && Boolean(root._iiStatus.hasTorch)
            buttonIcon: "flashlight_on"
            text: Translation.tr("Torch")
            property bool _syncing: false
            readonly property bool remoteChecked: Boolean(root._iiStatus.torch)
            Component.onCompleted: {
                _syncing = true
                checked = remoteChecked
                _syncing = false
            }
            onRemoteCheckedChanged: {
                _syncing = true
                checked = remoteChecked
                _syncing = false
            }
            onCheckedChanged: {
                if (!_syncing) IiCameraService.set({ torch: checked })
            }
        }

        // ii tools: Stabilization
        ConfigSwitch {
            visible: root._iiBackend
            buttonIcon: "video_stable"
            text: Translation.tr("Stabilize")
            property bool _syncing: false
            readonly property bool remoteChecked: Boolean(root._iiStatus.stabilize)
            Component.onCompleted: {
                _syncing = true
                checked = remoteChecked
                _syncing = false
            }
            onRemoteCheckedChanged: {
                _syncing = true
                checked = remoteChecked
                _syncing = false
            }
            onCheckedChanged: {
                if (!_syncing) IiCameraService.set({ stabilize: checked })
            }
        }

        // DroidCam: Camera facing: front / back
        ContentSubsection {
            visible: !root._iiBackend
            title: Translation.tr("Camera")
            icon: "camera_front"

            ConfigSelectionArray {
                options: [
                    { displayName: Translation.tr("Front"), icon: "camera_front", value: "front" },
                    { displayName: Translation.tr("Back"), icon: "camera_rear", value: "back" }
                ]
                currentValue: Config.options.phone.webcam.cameraFacing
                onSelected: (v) => {
                    // DroidCam does not have a CLI flag to switch cameras.
                    // Persist the preference so the next fresh start uses it,
                    // but do NOT restart the running stream (AGENTS.md Phone
                    // Module Round 5). Not flipCamera(): it toggles, which
                    // undid the value just picked.
                    Config.options.phone.webcam.cameraFacing = v
                }
            }
        }

        // DroidCam: Connection
        ContentSubsection {
            visible: !root._iiBackend
            title: Translation.tr("Connection")
            icon: "cable"

            ConfigSelectionArray {
                options: [
                    { displayName: Translation.tr("Wi-Fi"), icon: "wifi", value: "wifi" },
                    { displayName: Translation.tr("USB"), icon: "usb", value: "usb" }
                ]
                currentValue: Config.options.phone.webcam.connection
                onSelected: (v) => Config.options.phone.webcam.connection = v
            }
        }

        // DroidCam: Resolution
        ContentSubsection {
            visible: !root._iiBackend
            title: Translation.tr("Resolution")
            icon: "aspect_ratio"

            ConfigSelectionArray {
                options: [
                    { displayName: "480p", value: "640x480" },
                    { displayName: "720p", value: "1280x720" },
                    { displayName: "1080p", value: "1920x1080" }
                ]
                currentValue: Config.options.phone.webcam.resolution
                onSelected: (v) => Config.options.phone.webcam.resolution = v
            }
        }

        // Mirror toggle
        ConfigSwitch {
            buttonIcon: "flip"
            text: Translation.tr("Mirror horizontally")
            checked: PhoneCameraService.mirrored
            onCheckedChanged: {
                if (checked !== PhoneCameraService.mirrored)
                    PhoneCameraService.toggleMirror()
            }
        }

        // Rotation
        ContentSubsection {
            title: Translation.tr("Rotation")
            icon: "rotate_right"

            ConfigSelectionArray {
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
    }

    // ─── Wi-Fi settings (only visible in DroidCam WiFi mode)
    ContentSection {
        icon: "wifi"
        title: Translation.tr("Connection")
        visible: !root._iiBackend && Config.options.phone.webcam.connection === "wifi"

        ConfigTextField {
            text: Translation.tr("Phone IP")
            icon: "ip"
            placeholderText: Translation.tr("Auto-detect from the paired phone")
            inputText: Config.options.phone.webcam.wifiIp
            textField.onEditingFinished: Config.options.phone.webcam.wifiIp = textField.text.trim()
            tooltip: Translation.tr("Leave empty to auto-detect from the paired phone. Set explicitly if auto-detect fails.")
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

    // ─── Quality (DroidCam only) ───────────────────────────
    ContentSection {
        icon: "tune"
        title: Translation.tr("Quality")
        visible: !root._iiBackend

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
