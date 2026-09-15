import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
        id: root
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
                text: Translation.tr("Media Mode Background")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Media Mode Background")
            icon: "music_note"

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                text: Translation.tr("These settings apply exclusively to the full-screen Media Mode background overlay.")
            }

            ConfigSwitch {
                buttonIcon: "lyrics"
                text: Translation.tr("Show synchronized lyrics panel")
                checked: Config.options.background.mediaMode.showLyrics ?? true
                onCheckedChanged: {
                    Config.options.background.mediaMode.showLyrics = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "tune"
                text: Translation.tr("Show top media player switcher bar")
                checked: Config.options.background.mediaMode.showPlayerSwitcher ?? true
                onCheckedChanged: {
                    Config.options.background.mediaMode.showPlayerSwitcher = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "graphic_eq"
                text: Translation.tr("Show audio visualizers")
                checked: (Config.options.background.mediaMode.visualizerMode ?? 1) > 0
                onCheckedChanged: {
                    Config.options.background.mediaMode.visualizerMode = checked ? 1 : 0;
                }
            }

            ContentSubsection {
                title: Translation.tr("Default visualizer mode")
                icon: "equalizer"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.mediaMode.visualizerMode ?? 1
                    onSelected: newValue => {
                        Config.options.background.mediaMode.visualizerMode = newValue;
                    }
                    options: [
                        {
                            "displayName": Translation.tr("Off"),
                            "icon": "equalizer",
                            "value": 0
                        },
                        {
                            "displayName": Translation.tr("Waves"),
                            "icon": "waves",
                            "value": 1
                        },
                        {
                            "displayName": Translation.tr("Bars"),
                            "icon": "bar_chart",
                            "value": 2
                        },
                        {
                            "displayName": Translation.tr("Radial"),
                            "icon": "blur_circular",
                            "value": 3
                        }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "linear_scale"
                text: Translation.tr("Show track progress seekbar")
                checked: Config.options.background.mediaMode.showSeekBar ?? true
                onCheckedChanged: {
                    Config.options.background.mediaMode.showSeekBar = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("Show volume slider control")
                checked: Config.options.background.mediaMode.showVolumeSlider ?? true
                onCheckedChanged: {
                    Config.options.background.mediaMode.showVolumeSlider = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "animation"
                text: Translation.tr("Enable background animation")
                checked: Config.options.background.mediaMode.backgroundAnimation.enable
                onCheckedChanged: {
                    Config.options.background.mediaMode.backgroundAnimation.enable = checked;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.mediaMode.backgroundAnimation.enable
                icon: "speed"
                text: Translation.tr("Speed scale")
                value: Config.options.background.mediaMode.backgroundAnimation.speedScale
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.background.mediaMode.backgroundAnimation.speedScale = value;
                }

                MouseArea {
                    id: spinBoxMouseArea
                    z: -1
                    anchors.fill: parent
                    hoverEnabled: true
                }

                StyledToolTip {
                    extraVisibleCondition: spinBoxMouseArea.containsMouse
                    text: Translation.tr("1: very slow | 10: default | 20: 2x speed...")
                }
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Background album art opacity (%)")
                value: Config.options.background.mediaMode.backgroundOpacity
                from: 0
                to: 100
                stepSize: 10
                onValueChanged: {
                    Config.options.background.mediaMode.backgroundOpacity = value;
                }
            }

            ContentSubsection {
                title: Translation.tr("Background shape")
                icon: "category"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.mediaMode.backgroundShape
                    onSelected: newValue => {
                        Config.options.background.mediaMode.backgroundShape = newValue;
                    }
                    options: (["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]).map(icon => {
                        return {
                            "displayName": "",
                            "shape": icon,
                            "value": icon
                        };
                    })
                }
            }

            ConfigSwitch {
                buttonIcon: "format_color_fill"
                text: Translation.tr("Change shell color to match album art")
                checked: Config.options.background.mediaMode.changeShellColor
                onCheckedChanged: {
                    Config.options.background.mediaMode.changeShellColor = checked;
                }
            }

            ContentSubsection {
                title: Translation.tr("Text highlight style")
                icon: "highlight"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.mediaMode.syllable.textHighlightStyle
                    onSelected: newValue => {
                        Config.options.background.mediaMode.syllable.textHighlightStyle = newValue;
                    }
                    options: [
                        {
                            "displayName": Translation.tr("Vertical"),
                            "icon": "vertical_distribute",
                            "value": 0
                        },
                        {
                            "displayName": Translation.tr("Horizontal"),
                            "icon": "horizontal_distribute",
                            "value": 1
                        }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "monitor"
                text: Translation.tr("Toggle per monitor")
                checked: Config.options.background.mediaMode.togglePerMonitor
                onCheckedChanged: {
                    Config.options.background.mediaMode.togglePerMonitor = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "compare_arrows"
                text: Translation.tr("Enable track crossfade")
                checked: Config.options.background.mediaMode.crossfade.enable ?? false
                onCheckedChanged: {
                    Config.options.background.mediaMode.crossfade.enable = checked;
                }
            }

            ConfigSpinBox {
                enabled: Config.options.background.mediaMode.crossfade.enable ?? false
                icon: "timer"
                text: Translation.tr("Crossfade duration (seconds)")
                value: Config.options.background.mediaMode.crossfade.durationSec ?? 3
                from: 1
                to: 15
                stepSize: 1
                onValueChanged: {
                    Config.options.background.mediaMode.crossfade.durationSec = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "play_circle"
                text: Translation.tr("Replace blurred background with music video")
                checked: Config.options.background.mediaMode.musicVideo.enable ?? false
                onCheckedChanged: {
                    Config.options.background.mediaMode.musicVideo.enable = checked;
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Searches YouTube for the official music video and plays it behind the media mode overlay. Requires mpvpaper and yt-dlp.")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            ConfigSpinBox {
                icon: "high_quality"
                text: Translation.tr("Maximum video resolution (px)")
                value: Config.options.background.mediaMode.musicVideo.maxResolution ?? 1080
                from: 360
                to: 4320
                stepSize: 360
                onValueChanged: {
                    Config.options.background.mediaMode.musicVideo.maxResolution = value;
                }
            }

            ConfigSpinBox {
                icon: "opacity"
                text: Translation.tr("Background dim opacity (%)")
                value: Config.options.background.mediaMode.musicVideo.dimOpacity ?? 60
                from: 0
                to: 100
                stepSize: 10
                onValueChanged: {
                    Config.options.background.mediaMode.musicVideo.dimOpacity = value;
                }
            }

            ConfigSpinBox {
                icon: "timer"
                text: Translation.tr("Video color sampling interval (ms)")
                value: Config.options.background.mediaMode.musicVideo.videoSamplingInterval ?? 200
                from: 100
                to: 5000
                stepSize: 100
                onValueChanged: {
                    Config.options.background.mediaMode.musicVideo.videoSamplingInterval = value;
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("How much to dim the overlay so the video is visible. 0 = fully transparent, 100 = opaque (hides video).")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Dim background overlay")
                checked: Config.options.background.mediaMode.musicVideo.dimBackground ?? true
                onCheckedChanged: {
                    Config.options.background.mediaMode.musicVideo.dimBackground = checked;
                }
            }
        }
    }
}
