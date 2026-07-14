import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

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
            text: Translation.tr("Media Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Media Settings")
        icon: "music_note"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("media_circular") && !Config.isWidgetActive("media_expressive")

            PagePlaceholder {
                anchors.fill: parent
                icon: "music_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Media widget disabled")
                description: Translation.tr("Enable a media widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("media_circular") || Config.isWidgetActive("media_expressive")

            Item { Layout.preferredHeight: 16; visible: Config.isWidgetActive("media_circular") }

            // Circular Style Settings
            ColumnLayout {
                visible: Config.isWidgetActive("media_circular")
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel { text: Translation.tr("Circular Style Settings") }

                ConfigSwitch {
                    buttonIcon: "color_lens"
                    text: Translation.tr("Use album colors")
                    checked: Config.options.background.widgets.media.useAlbumColors
                    onCheckedChanged: {
                        Config.options.background.widgets.media.useAlbumColors = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "brush"
                    text: Translation.tr("Tint art cover")
                    checked: Config.options.background.widgets.media.tintArtCover
                    onCheckedChanged: {
                        Config.options.background.widgets.media.tintArtCover = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "visibility_off"
                    text: Translation.tr("Hide all controls")
                    checked: Config.options.background.widgets.media.hideAllButtons
                    onCheckedChanged: {
                        Config.options.background.widgets.media.hideAllButtons = checked;
                    }
                }

                ConfigSwitch {
                    enabled: !Config.options.background.widgets.media.hideAllButtons
                    buttonIcon: "skip_previous"
                    text: Translation.tr("Show previous toggle")
                    checked: Config.options.background.widgets.media.showPreviousToggle
                    onCheckedChanged: {
                        Config.options.background.widgets.media.showPreviousToggle = checked;
                    }
                }

                ContentSubsection {
                    title: Translation.tr("Background shape")
                    icon: "category"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.media.backgroundShape
                        onSelected: newValue => {
                            Config.options.background.widgets.media.backgroundShape = newValue;
                        }
                        options: [
                            { displayName: Translation.tr("Circle"), icon: "circle", value: "circle" },
                            { displayName: Translation.tr("Square"), icon: "square", value: "square" },
                            { displayName: Translation.tr("Cookie"), icon: "cookie", value: "cookie" }
                        ]
                    }
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Glow effect settings
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel { text: Translation.tr("Glow effect settings") }

                ConfigSwitch {
                    buttonIcon: "flare"
                    text: Translation.tr("Enable glow")
                    checked: Config.options.background.widgets.media.glow.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.media.glow.enable = checked;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.background.widgets.media.glow.enable
                    icon: "brightness_medium"
                    text: Translation.tr("Brightness")
                    value: Config.options.background.widgets.media.glow.brightness
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.background.widgets.media.glow.brightness = value;
                    }
                }
            }

            Item { Layout.preferredHeight: 16 }

            // Visualizer settings
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel { text: Translation.tr("Visualizer settings") }

                ConfigSwitch {
                    buttonIcon: "graphic_eq"
                    text: Translation.tr("Enable visualizer")
                    checked: Config.options.background.widgets.media.visualizer.enable
                    onCheckedChanged: {
                        Config.options.background.widgets.media.visualizer.enable = checked;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.background.widgets.media.visualizer.enable
                    icon: "opacity"
                    text: Translation.tr("Opacity")
                    value: Config.options.background.widgets.media.visualizer.opacity * 100
                    from: 0
                    to: 100
                    stepSize: 5
                    onValueChanged: {
                        Config.options.background.widgets.media.visualizer.opacity = value / 100;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.background.widgets.media.visualizer.enable
                    icon: "waves"
                    text: Translation.tr("Smoothing")
                    value: Config.options.background.widgets.media.visualizer.smoothing
                    from: 1
                    to: 20
                    stepSize: 1
                    onValueChanged: {
                        Config.options.background.widgets.media.visualizer.smoothing = value;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.background.widgets.media.visualizer.enable
                    icon: "blur_on"
                    text: Translation.tr("Blur")
                    value: Config.options.background.widgets.media.visualizer.blur
                    from: 0
                    to: 50
                    stepSize: 1
                    onValueChanged: {
                        Config.options.background.widgets.media.visualizer.blur = value;
                    }
                }
            }

            Item {
                Layout.preferredHeight: 16
            }

            // Visual Options (Shadows)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                ContentSubsectionLabel {
                    text: Translation.tr("Visual Options")
                }

                ConfigSwitch {
                    buttonIcon: "wb_sunny"
                    text: Translation.tr("Enable Shadows")
                    checked: Config.options.background.widgets.enableShadows ?? true
                    onCheckedChanged: {
                        Config.options.background.widgets.enableShadows = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "blur_on"
                    text: Translation.tr("Enable Inner Shadows")
                    checked: Config.options.background.widgets.enableInnerShadow ?? true
                    onCheckedChanged: {
                        Config.options.background.widgets.enableInnerShadow = checked;
                    }
                }
            }
        }
    }
}
