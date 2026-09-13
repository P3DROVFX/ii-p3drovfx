import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import "../../../common/functions/recordingQuality.js" as RecordingQuality

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    // The estimate is only ever as good as the screen it is made for, so it is
    // made for the one the settings window is on.
    readonly property var estimateScreen: (QsWindow.window as QsWindow)?.screen ?? (Quickshell.screens[0] ?? null)
    readonly property int sourceWidth: subPageRoot.estimateScreen
        ? Math.round(subPageRoot.estimateScreen.width * subPageRoot.estimateScreen.devicePixelRatio) : 1920
    readonly property int sourceHeight: subPageRoot.estimateScreen
        ? Math.round(subPageRoot.estimateScreen.height * subPageRoot.estimateScreen.devicePixelRatio) : 1080
    readonly property var outputSize: RecordingQuality.outputSize(subPageRoot.sourceWidth, subPageRoot.sourceHeight,
        Config.options.screenRecord.resolution)
    readonly property real estimatedMbps: RecordingQuality.estimateMbps(subPageRoot.outputSize[0], subPageRoot.outputSize[1],
        Config.options.screenRecord.framerate, Config.options.screenRecord.quality)
    readonly property string estimateSummary: Translation.tr("≈ %1 Mbps · %2×%3 · %4 fps on this screen")
        .arg(subPageRoot.estimatedMbps)
        .arg(subPageRoot.outputSize[0])
        .arg(subPageRoot.outputSize[1])
        .arg(Config.options.screenRecord.framerate)

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
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
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Screen Recording")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Provider & Notifications ─────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Recorder Provider")
            icon: "videocam"

            ContentSubsection {
                title: Translation.tr("Provider")
                icon: "video_settings"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.screenRecord.service
                    onSelected: (newValue) => {
                        Config.options.screenRecord.service = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("wf-recorder"),
                        "value": "wf-recorder",
                        "icon": "radio_button_checked"
                    }, {
                        "displayName": "OBS Studio",
                        "value": "obs",
                        "icon": "videocam"
                    }]
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: Config.options.screenRecord.service === "obs"
                materialIcon: "info"
                text: Translation.tr("OBS WebSocket Setup:\n1. Open OBS Studio -> Tools -> WebSocket Server Settings.\n2. Enable WebSocket server (default port: 4455).\n3. Disable Authentication (uncheck 'Enable Authentication') OR set the OBS_API_PASSWORD environment variable.\n4. When starting recording, a screen picker portal dialog will appear to select the recording source/screen.")
            }

            ConfigSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Show recording notifications")
                checked: Config.options.screenRecord.showNotifications
                onCheckedChanged: {
                    Config.options.screenRecord.showNotifications = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Shows system notifications when screen recording starts, finishes, or errors.")
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Video record path")
            }

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Video record path")
                text: Config.options.screenRecord.savePath
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.screenRecord.savePath = text;
                }
            }
        }

        // ── Post-Recording Actions ───────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Post-Recording")
            icon: "movie_edit"

            ContentSubsection {
                title: Translation.tr("After recording")
                icon: "output"
                tooltip: Translation.tr("Choose what happens automatically once a screen recording is saved")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: {
                        if (!Config.options.screenRecord.showEditPrompt) return "nothing";
                        if (Config.options.screenRecord.openInLosslessCut) return "losslesscut";
                        return "ask_edit";
                    }
                    onSelected: (newValue) => {
                        if (newValue === "nothing") {
                            Config.options.screenRecord.showEditPrompt = false;
                            Config.options.screenRecord.openInLosslessCut = false;
                        } else if (newValue === "ask_edit") {
                            Config.options.screenRecord.showEditPrompt = true;
                            Config.options.screenRecord.openInLosslessCut = false;
                        } else if (newValue === "losslesscut") {
                            Config.options.screenRecord.showEditPrompt = true;
                            Config.options.screenRecord.openInLosslessCut = true;
                        }
                    }
                    options: [{
                        "displayName": Translation.tr("Nothing"),
                        "icon": "block",
                        "value": "nothing"
                    }, {
                        "displayName": Translation.tr("Ask to edit"),
                        "icon": "movie_edit",
                        "value": "ask_edit"
                    }, {
                        "displayName": Translation.tr("Open in LosslessCut"),
                        "icon": "open_in_new",
                        "value": "losslesscut"
                    }]
                }
            }
        }

        // ── Local recorder settings (wf-recorder) ────────────────────────────
        ContentSection {
            title: Translation.tr("Local Recorder Engine")
            icon: "tune"
            visible: Config.options.screenRecord.service === "wf-recorder"

            ConfigSwitch {
                buttonIcon: "bolt"
                text: Translation.tr("GPU Hardware Acceleration")
                checked: Config.options.screenRecord.useGpu
                onCheckedChanged: {
                    Config.options.screenRecord.useGpu = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Uses hardware-accelerated video encoding for lower CPU usage.")
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Video Codec")
            }

            StyledComboBox {
                id: recorderCodecSelector
                buttonIcon: "movie"
                textRole: "displayName"
                model: [{
                    "displayName": Translation.tr("Auto (Recommended)"),
                    "value": "auto"
                }, {
                    "displayName": "H264 (NVIDIA GPU - NVENC)",
                    "value": "h264_nvenc"
                }, {
                    "displayName": "H264 (Intel/AMD GPU - VAAPI)",
                    "value": "h264_vaapi"
                }, {
                    "displayName": "H264 (AMD GPU - AMF)",
                    "value": "h264_amf"
                }, {
                    "displayName": "H264 (CPU - Compatibility)",
                    "value": "libx264"
                }, {
                    "displayName": "HEVC (NVIDIA GPU - NVENC)",
                    "value": "hevc_nvenc"
                }, {
                    "displayName": "HEVC (Intel/AMD GPU - VAAPI)",
                    "value": "hevc_vaapi"
                }, {
                    "displayName": "HEVC (AMD GPU - AMF)",
                    "value": "hevc_amf"
                }, {
                    "displayName": "HEVC (CPU - Compatibility)",
                    "value": "libx265"
                }]
                currentIndex: {
                    const index = model.findIndex((item) => {
                        return item.value === Config.options.screenRecord.codec;
                    });
                    return index !== -1 ? index : 0;
                }
                onActivated: (index) => {
                    Config.options.screenRecord.codec = model[index].value;
                }

                StyledToolTip {
                    parent: recorderCodecSelector
                    text: Translation.tr("Auto automatically selects the best hardware encoder on your system. NVENC is for Nvidia, VA-API is for Intel/AMD, and AMF is for AMD. CPU encodes via software and uses more resources.")
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Resolution")
            }

            StyledComboBox {
                id: recorderResolutionSelector
                buttonIcon: "aspect_ratio"
                textRole: "displayName"
                model: [{
                    "displayName": Translation.tr("Native (no scaling)"),
                    "value": "native"
                }, {
                    "displayName": "2160p — 3840×2160",
                    "value": "2160p"
                }, {
                    "displayName": "1440p — 2560×1440",
                    "value": "1440p"
                }, {
                    "displayName": "1080p — 1920×1080",
                    "value": "1080p"
                }, {
                    "displayName": "720p — 1280×720",
                    "value": "720p"
                }, {
                    "displayName": "480p — 854×480",
                    "value": "480p"
                }]
                currentIndex: {
                    const index = model.findIndex((item) => {
                        return item.value === Config.options.screenRecord.resolution;
                    });
                    return index !== -1 ? index : 0;
                }
                onActivated: (index) => {
                    Config.options.screenRecord.resolution = model[index].value;
                }

                StyledToolTip {
                    parent: recorderResolutionSelector
                    text: Translation.tr("The recording is fitted inside this size without distorting it, so a region or an ultrawide screen keeps its shape. Anything already smaller is left alone rather than scaled up.")
                }
            }

            ContentSubsection {
                title: Translation.tr("Quality")
                icon: "high_quality"
                tooltip: Translation.tr("Sets how many bits each pixel is worth. The resulting bitrate follows from the resolution and frame rate, so you never have to pick an Mbps figure yourself.")
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.screenRecord.quality
                    onSelected: (newValue) => {
                        Config.options.screenRecord.quality = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Low"),
                        "value": "low",
                        "icon": "data_saver_on"
                    }, {
                        "displayName": Translation.tr("Balanced"),
                        "value": "balanced",
                        "icon": "balance"
                    }, {
                        "displayName": Translation.tr("High"),
                        "value": "high",
                        "icon": "hd"
                    }]
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: subPageRoot.estimateSummary
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            ConfigSlider {
                enabled: Config.options.screenRecord.frameSync !== "vfr"
                opacity: enabled ? 1 : 0.5
                buttonIcon: "av_timer"
                text: Translation.tr("Target Frame Rate (FPS)")
                value: Config.options.screenRecord.framerate
                from: 15
                to: 120
                stepSize: 5
                usePercentTooltip: false
                onValueChanged: {
                    Config.options.screenRecord.framerate = value;
                }
                StyledToolTip {
                    text: Translation.tr("Target frames per second for the recording. 60 FPS is standard for smooth desktop recordings. Ignored while the frame timing is variable, where the screen itself decides when a frame exists.")
                }
            }

            ContentSubsection {
                title: Translation.tr("Frame timing")
                icon: "schedule"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.screenRecord.frameSync
                    onSelected: (newValue) => {
                        Config.options.screenRecord.frameSync = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Constant"),
                        "value": "cfr",
                        "icon": "straighten"
                    }, {
                        "displayName": Translation.tr("Variable"),
                        "value": "vfr",
                        "icon": "compress"
                    }]
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    text: Config.options.screenRecord.frameSync === "vfr"
                        ? Translation.tr("A frame is only recorded when the screen changes. Much smaller files, but some editors handle the uneven timing badly.")
                        : Translation.tr("Frames are held at the target rate even when nothing moves. Bigger files, and what video editors expect.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        // ── Keystroke display ────────────────────────────────────────────────
        ContentSection {
            title: Translation.tr("Keystroke Display")
            icon: "keyboard"

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Shows the keys you press on top of everything, so they are captured by the recording. It can also be turned on at any time from the quick toggles.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            ConfigSwitch {
                buttonIcon: "keyboard_alt"
                text: Translation.tr("Show keystrokes while recording")
                checked: Config.options.screenRecord.keypress.showWhileRecording
                onCheckedChanged: {
                    Config.options.screenRecord.keypress.showWhileRecording = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Applies to every new recording. Each recording can still be switched over on its own from the recording indicator.")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: KeypressService.lastError.length > 0
                materialIcon: "error"
                text: Translation.tr("Keystrokes cannot be read: %1").arg(KeypressService.lastError)
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: KeypressService.lastError.length === 0 && !KeypressService.layoutAware
                materialIcon: "warning"
                text: Translation.tr("Key labels assume a US layout. Install python-xkbcommon to have them follow the keyboard layout you actually use.")
            }

            ContentSubsection {
                title: Translation.tr("Position on screen")
                icon: "pin_drop"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.screenRecord.keypress.position
                    onSelected: (newValue) => {
                        Config.options.screenRecord.keypress.position = newValue;
                    }
                    options: [{
                        "displayName": Translation.tr("Top left"),
                        "value": "topLeft",
                        "icon": "north_west"
                    }, {
                        "displayName": Translation.tr("Top"),
                        "value": "top",
                        "icon": "north"
                    }, {
                        "displayName": Translation.tr("Top right"),
                        "value": "topRight",
                        "icon": "north_east"
                    }, {
                        "displayName": Translation.tr("Bottom left"),
                        "value": "bottomLeft",
                        "icon": "south_west"
                    }, {
                        "displayName": Translation.tr("Bottom"),
                        "value": "bottom",
                        "icon": "south"
                    }, {
                        "displayName": Translation.tr("Bottom right"),
                        "value": "bottomRight",
                        "icon": "south_east"
                    }]
                }
            }

            ConfigSlider {
                buttonIcon: "swap_horiz"
                text: Translation.tr("Distance from the side edge")
                value: Config.options.screenRecord.keypress.marginH
                from: 0
                to: 400
                stepSize: 8
                usePercentTooltip: false
                onValueChanged: {
                    Config.options.screenRecord.keypress.marginH = value;
                }
            }

            ConfigSlider {
                buttonIcon: "swap_vert"
                text: Translation.tr("Distance from the top or bottom edge")
                value: Config.options.screenRecord.keypress.marginV
                from: 0
                to: 400
                stepSize: 8
                usePercentTooltip: false
                onValueChanged: {
                    Config.options.screenRecord.keypress.marginV = value;
                }
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Size")
                value: Config.options.screenRecord.keypress.scale
                from: 0.6
                to: 2.0
                stepSize: 0.1
                usePercentTooltip: false
                onValueChanged: {
                    Config.options.screenRecord.keypress.scale = value;
                }
            }

            ConfigSlider {
                buttonIcon: "timer"
                text: Translation.tr("Time on screen (ms)")
                value: Config.options.screenRecord.keypress.hideDelayMs
                from: 500
                to: 8000
                stepSize: 250
                usePercentTooltip: false
                onValueChanged: {
                    Config.options.screenRecord.keypress.hideDelayMs = value;
                }
            }

            ConfigSlider {
                buttonIcon: "format_list_numbered"
                text: Translation.tr("Keys kept on screen")
                value: Config.options.screenRecord.keypress.maxKeys
                from: 1
                to: 12
                stepSize: 1
                usePercentTooltip: false
                onValueChanged: {
                    Config.options.screenRecord.keypress.maxKeys = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "text_fields"
                text: Translation.tr("Join typed letters into words")
                checked: Config.options.screenRecord.keypress.mergeTyping
                onCheckedChanged: {
                    Config.options.screenRecord.keypress.mergeTyping = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Typing fills one chip instead of flooding the screen with a chip per letter. Shortcuts always get their own.")
                }
            }

            ConfigSwitch {
                buttonIcon: "keyboard_command_key"
                text: Translation.tr("Only show shortcuts")
                checked: Config.options.screenRecord.keypress.onlyShortcuts
                onCheckedChanged: {
                    Config.options.screenRecord.keypress.onlyShortcuts = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Hides ordinary typing and reports only combinations with Ctrl, Alt or Super — useful when what you type is private.")
                }
            }

            ConfigSwitch {
                buttonIcon: "mouse"
                text: Translation.tr("Show mouse buttons")
                checked: Config.options.screenRecord.keypress.showMouseButtons
                onCheckedChanged: {
                    Config.options.screenRecord.keypress.showMouseButtons = checked;
                }
            }
        }
    }
}
