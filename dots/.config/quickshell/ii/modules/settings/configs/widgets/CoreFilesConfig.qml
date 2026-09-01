import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "../../../common/functions/recordingQuality.js" as RecordingQuality

ContentPage {
    id: root
    forceWidth: false
    signal goBack

    // Same estimate the Screen Recording page shows, for the screen this window
    // is on: a bitrate only means something next to the pixels it pays for.
    readonly property var estimateScreen: (QsWindow.window as QsWindow)?.screen ?? (Quickshell.screens[0] ?? null)
    readonly property int sourceWidth: root.estimateScreen
        ? Math.round(root.estimateScreen.width * root.estimateScreen.devicePixelRatio) : 1920
    readonly property int sourceHeight: root.estimateScreen
        ? Math.round(root.estimateScreen.height * root.estimateScreen.devicePixelRatio) : 1080
    readonly property var outputSize: RecordingQuality.outputSize(root.sourceWidth, root.sourceHeight,
        Config.options.screenRecord.resolution)
    readonly property string estimateSummary: Translation.tr("≈ %1 Mbps · %2×%3 · %4 fps on this screen")
        .arg(RecordingQuality.estimateMbps(root.outputSize[0], root.outputSize[1],
            Config.options.screenRecord.framerate, Config.options.screenRecord.quality))
        .arg(root.outputSize[0])
        .arg(root.outputSize[1])
        .arg(Config.options.screenRecord.framerate)

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
            text: Translation.tr("File Paths & Transfers")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }
    ContentSection {
        icon: "save"
        title: Translation.tr("File Paths & Transfers")

        ContentSubsectionLabel {
            text: Translation.tr("Save paths")
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

        ConfigSwitch {
            buttonIcon: "videocam"
            text: Translation.tr("Use OBS for recording")
            checked: Config.options.screenRecord.service === "obs"
            onCheckedChanged: {
                Config.options.screenRecord.service = checked ? "obs" : "wf-recorder";
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.screenRecord.service === "obs"
            text: Translation.tr("OBS WebSocket Setup:\n1. Open OBS Studio -> Tools -> WebSocket Server Settings.\n2. Enable WebSocket server (default port: 4455).\n3. Disable Authentication (uncheck 'Enable Authentication') OR set the OBS_API_PASSWORD environment variable.\n4. When starting recording, a screen picker portal dialog will appear to select the recording source/screen.")
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show recording notifications")
            checked: Config.options.screenRecord.showNotifications
            onCheckedChanged: {
                Config.options.screenRecord.showNotifications = checked;
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("Local recorder settings (wf-recorder)")
            visible: Config.options.screenRecord.service === "wf-recorder"
        }

        ConfigSwitch {
            buttonIcon: "bolt"
            text: Translation.tr("GPU Hardware Acceleration")
            checked: Config.options.screenRecord.useGpu
            visible: Config.options.screenRecord.service === "wf-recorder"
            onCheckedChanged: {
                Config.options.screenRecord.useGpu = checked;
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("Video Codec")
            visible: Config.options.screenRecord.service === "wf-recorder"
        }

        StyledComboBox {
            id: recorderCodecSelector2
            buttonIcon: "movie"
            textRole: "displayName"
            visible: Config.options.screenRecord.service === "wf-recorder"
            model: [
                {
                    displayName: Translation.tr("Auto (Recommended)"),
                    value: "auto"
                },
                {
                    displayName: "H264 (NVIDIA GPU - NVENC)",
                    value: "h264_nvenc"
                },
                {
                    displayName: "H264 (Intel/AMD GPU - VAAPI)",
                    value: "h264_vaapi"
                },
                {
                    displayName: "H264 (AMD GPU - AMF)",
                    value: "h264_amf"
                },
                {
                    displayName: "H264 (CPU - Compatibility)",
                    value: "libx264"
                },
                {
                    displayName: "HEVC (NVIDIA GPU - NVENC)",
                    value: "hevc_nvenc"
                },
                {
                    displayName: "HEVC (Intel/AMD GPU - VAAPI)",
                    value: "hevc_vaapi"
                },
                {
                    displayName: "HEVC (AMD GPU - AMF)",
                    value: "hevc_amf"
                },
                {
                    displayName: "HEVC (CPU - Compatibility)",
                    value: "libx265"
                }
            ]
            currentIndex: {
                const index = model.findIndex(item => item.value === Config.options.screenRecord.codec);
                return index !== -1 ? index : 0;
            }
            onActivated: index => {
                Config.options.screenRecord.codec = model[index].value;
            }
            StyledToolTip {
                parent: recorderCodecSelector2
                text: Translation.tr("Auto automatically selects the best hardware encoder on your system. NVENC is for Nvidia, VA-API is for Intel/AMD, and AMF is for AMD. CPU encodes via software and uses more resources.")
            }
        }

        StyledComboBox {
            id: recorderResolutionSelector2
            buttonIcon: "aspect_ratio"
            textRole: "displayName"
            visible: Config.options.screenRecord.service === "wf-recorder"
            model: [
                {
                    displayName: Translation.tr("Native (no scaling)"),
                    value: "native"
                },
                {
                    displayName: "2160p — 3840×2160",
                    value: "2160p"
                },
                {
                    displayName: "1440p — 2560×1440",
                    value: "1440p"
                },
                {
                    displayName: "1080p — 1920×1080",
                    value: "1080p"
                },
                {
                    displayName: "720p — 1280×720",
                    value: "720p"
                },
                {
                    displayName: "480p — 854×480",
                    value: "480p"
                }
            ]
            currentIndex: {
                const index = model.findIndex(item => item.value === Config.options.screenRecord.resolution);
                return index !== -1 ? index : 0;
            }
            onActivated: index => {
                Config.options.screenRecord.resolution = model[index].value;
            }
            StyledToolTip {
                parent: recorderResolutionSelector2
                text: Translation.tr("The recording is fitted inside this size without distorting it. Anything already smaller is left alone rather than scaled up.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Quality")
            icon: "high_quality"
            visible: Config.options.screenRecord.service === "wf-recorder"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.quality
                onSelected: newValue => {
                    Config.options.screenRecord.quality = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Low"),
                        value: "low",
                        icon: "data_saver_on"
                    },
                    {
                        displayName: Translation.tr("Balanced"),
                        value: "balanced",
                        icon: "balance"
                    },
                    {
                        displayName: Translation.tr("High"),
                        value: "high",
                        icon: "hd"
                    }
                ]
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                text: root.estimateSummary
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        ConfigSlider {
            buttonIcon: "av_timer"
            text: Translation.tr("Target Frame Rate (FPS)")
            value: Config.options.screenRecord.framerate
            from: 15
            to: 120
            stepSize: 5
            usePercentTooltip: false
            enabled: Config.options.screenRecord.frameSync !== "vfr"
            opacity: enabled ? 1 : 0.5
            visible: Config.options.screenRecord.service === "wf-recorder"
            onValueChanged: {
                Config.options.screenRecord.framerate = value;
            }
            StyledToolTip {
                text: Translation.tr("Target frames per second for the recording. 60 FPS is standard for smooth desktop recordings. Ignored while the frame timing is variable.")
            }
        }

        ContentSubsection {
            title: Translation.tr("Frame timing")
            icon: "schedule"
            visible: Config.options.screenRecord.service === "wf-recorder"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.screenRecord.frameSync
                onSelected: newValue => {
                    Config.options.screenRecord.frameSync = newValue;
                }
                options: [
                    {
                        displayName: Translation.tr("Constant"),
                        value: "cfr",
                        icon: "straighten"
                    },
                    {
                        displayName: Translation.tr("Variable"),
                        value: "vfr",
                        icon: "compress"
                    }
                ]
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Screenshot path")
            text: Config.options.screenSnip.savePath
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.screenSnip.savePath = text;
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("LocalSend CLI")
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Auto-start")
            checked: Config.options.localsend.autoStart
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.autoStart = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show notifications")
            checked: Config.options.localsend.showNotifications
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.showNotifications = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "branding_watermark"
            text: Translation.tr("Prefer popup over notification")
            checked: Config.options.localsend.preferPopupOverNotification
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.preferPopupOverNotification = checked;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Download path")
            text: Config.options.localsend.downloadPath
            wrapMode: TextEdit.Wrap
            enabled: LocalSend.available
            onTextChanged: {
                Config.options.localsend.downloadPath = text;
            }
        }

        ContentSubsectionLabel {
            text: Translation.tr("Wallpaper Browser")
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Wallpaper Browser download path")
            text: Config.options.wallpapers.paths.download
            wrapMode: TextEdit.Wrap
            onTextChanged: {
                Config.options.wallpapers.paths.download = text;
            }
        }
    }
}
