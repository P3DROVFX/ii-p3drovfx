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
    id: page

    forceWidth: false

    // ── Selection ─────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Selection")
        icon: "highlight_alt"

        ConfigSwitch {
            buttonIcon: "monitor"
            text: Translation.tr("Show only on focused monitor")
            checked: Config.options.regionSelector.showOnlyOnFocusedMonitor
            onCheckedChanged: {
                Config.options.regionSelector.showOnlyOnFocusedMonitor = checked;
            }
        }

        ContentSubsection {
            title: Translation.tr("Hint target regions")
            icon: "center_focus_strong"
            Layout.fillWidth: true

            ConfigSwitch {
                buttonIcon: "desktop_windows"
                text: Translation.tr("Windows")
                checked: Config.options.regionSelector.targetRegions.windows
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.windows = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "layers"
                text: Translation.tr("Layers")
                checked: Config.options.regionSelector.targetRegions.layers
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.layers = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "article"
                text: Translation.tr("Content")
                checked: Config.options.regionSelector.targetRegions.content
                onCheckedChanged: {
                    Config.options.regionSelector.targetRegions.content = checked;
                }
            }

        }

    }

    // ── Google Lens ───────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Google Lens")
        icon: "search"

        ContentSubsection {
            title: Translation.tr("Selection mode")
            icon: "highlight_alt"
            Layout.fillWidth: true

            ConfigSelectionArray {
                currentValue: Config.options.search.imageSearch.useCircleSelection ? "circle" : "rectangles"
                onSelected: (newValue) => {
                    Config.options.search.imageSearch.useCircleSelection = (newValue === "circle");
                }
                options: [{
                    "displayName": Translation.tr("Rectangular selection"),
                    "value": "rectangles",
                    "icon": "activity_zone"
                }, {
                    "displayName": Translation.tr("Circle to Search"),
                    "value": "circle",
                    "icon": "gesture"
                }]
            }

        }

        ContentSubsection {
            title: Translation.tr("Rectangular selection")
            icon: "crop_square"
            visible: !Config.options.search.imageSearch.useCircleSelection
            Layout.fillWidth: true

            ConfigSwitch {
                buttonIcon: "border_inner"
                text: Translation.tr("Show aim lines")
                checked: Config.options.regionSelector.rect.showAimLines
                onCheckedChanged: {
                    Config.options.regionSelector.rect.showAimLines = checked;
                }
            }

        }

        ContentSubsection {
            title: Translation.tr("Circle selection")
            icon: "panorama_fish_eye"
            visible: Config.options.search.imageSearch.useCircleSelection
            Layout.fillWidth: true

            ConfigSpinBox {
                icon: "line_weight"
                text: Translation.tr("Stroke width")
                value: Config.options.regionSelector.circle.strokeWidth
                from: 1
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.regionSelector.circle.strokeWidth = value;
                }
            }

            ConfigSpinBox {
                icon: "padding"
                text: Translation.tr("Padding")
                value: Config.options.regionSelector.circle.padding
                from: 0
                to: 100
                stepSize: 1
                onValueChanged: {
                    Config.options.regionSelector.circle.padding = value;
                }
            }

        }

    }

    // ── Editor & screenshots ──────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Editor & screenshots")
        icon: "transform"

        ConfigSwitch {
            buttonIcon: "edit"
            text: Translation.tr("Enable built-in right click screenshot editor")
            checked: Config.options.regionSelector.annotation.enableInlineEditor
            onCheckedChanged: {
                Config.options.regionSelector.annotation.enableInlineEditor = checked;
            }

            StyledToolTip {
                text: Translation.tr("Enable this if you want to use the built-in screenshot editor when using right click to select are, replacing swappy.")
            }

        }

        ContentSubsectionLabel {
            text: Translation.tr("Screenshot path")
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

    }

    // ── Recording ─────────────────────────────────────────────────────────
    ContentSection {
        title: Translation.tr("Recording")
        icon: "screen_record"

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

    }

}
