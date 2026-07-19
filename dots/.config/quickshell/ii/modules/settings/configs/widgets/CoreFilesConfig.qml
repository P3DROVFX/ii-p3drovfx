import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

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
                parent: recorderCodecSelector2
                text: Translation.tr("Auto automatically selects the best hardware encoder on your system. NVENC is for Nvidia, VA-API is for Intel/AMD, and AMF is for AMD. CPU encodes via software and uses more resources.")
            }

        }

        ConfigSlider {
            buttonIcon: "speed"
            text: Translation.tr("Bitrate (Mbps)")
            value: Config.options.screenRecord.bitrate
            from: 1
            to: 50
            stepSize: 1
            usePercentTooltip: false
            visible: Config.options.screenRecord.service === "wf-recorder"
            onValueChanged: {
                Config.options.screenRecord.bitrate = value;
            }

            StyledToolTip {
                text: Translation.tr("Higher bitrate increases video quality but uses more disk space. 6-12 Mbps is ideal for 1080p recording.")
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
            visible: Config.options.screenRecord.service === "wf-recorder"
            onValueChanged: {
                Config.options.screenRecord.framerate = value;
            }

            StyledToolTip {
                text: Translation.tr("Target frames per second for the recording. 60 FPS is standard for smooth desktop recordings.")
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

    }

}
