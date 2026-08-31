import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../ii/bar/widgets/media"

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

    // ── Back button row ───────────────────────────────────────────────────
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
            text: Translation.tr("Media Player")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "preview"
        title: Translation.tr("Live preview")

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        const style = Config.options.bar.styles.media ?? "default";
                        if (style === "ring")
                            return ringHorizontalPreview;
                        if (style === "tonal")
                            return tonalHorizontalPreview;
                        return null;
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !["ring", "tonal"].includes(Config.options.bar.styles.media ?? "default")
                    text: Translation.tr("Preview available for Ring and Tonal")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.6
                }
            }

            Rectangle {
                Layout.preferredWidth: Appearance.sizes.verticalBarWidth + 28
                Layout.fillHeight: true
                implicitHeight: Appearance.sizes.baseBarHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1

                Loader {
                    anchors.centerIn: parent
                    sourceComponent: {
                        const style = Config.options.bar.styles.media ?? "default";
                        if (style === "ring")
                            return ringVerticalPreview;
                        if (style === "tonal")
                            return tonalVerticalPreview;
                        return null;
                    }
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "lyrics"
            text: Translation.tr("Lyrics are a horizontal-bar feature. A 44px column cannot hold a line of text worth reading, so the vertical form shows artwork and progress instead.")
        }
    }

    // ── Settings ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Media Player")

        ContentSubsection {
            title: Translation.tr("Widget style")
            icon: "style"

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.media
                onSelected: newValue => Config.options.bar.styles.media = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Neural"), icon: "graphic_eq", value: "neural" },
                    { displayName: Translation.tr("Ring"), icon: "motion_photos_on", value: "ring" },
                    { displayName: Translation.tr("Tonal"), icon: "gradient", value: "tonal" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Popup style")
            icon: "style"

            ConfigSelectionArray {
                currentValue: Config.options.bar.mediaPlayer.popupStyle
                onSelected: newValue => {
                    Config.options.bar.mediaPlayer.popupStyle = newValue;
                }
                options: [
                    { displayName: Translation.tr("Default"),     icon: "dashboard",     value: "default" },
                    { displayName: Translation.tr("Expressive"),  icon: "auto_awesome",  value: "expressive" },
                    { displayName: Translation.tr("Android"),     icon: "smart_display", value: "android" }
                ]
            }
        }

        ConfigSwitch {
            buttonIcon: "crop_free"
            text: Translation.tr("Use fixed size")
            checked: Config.options.bar.mediaPlayer.useFixedSize
            onCheckedChanged: {
                Config.options.bar.mediaPlayer.useFixedSize = checked;
            }
        }

        ConfigSpinBox {
            enabled: !Config.options.bar.vertical && Config.options.bar.mediaPlayer.useFixedSize
            icon: "width_full"
            text: Translation.tr("Custom size")
            value: Config.options.bar.mediaPlayer.customSize
            from: 100
            to: 500
            stepSize: 25
            onValueChanged: {
                Config.options.bar.mediaPlayer.customSize = value;
            }
        }

        ConfigSwitch {
            enabled: !Config.options.bar.vertical
            buttonIcon: "image"
            text: Translation.tr("Enable artwork")
            checked: Config.options.bar.mediaPlayer.artwork.enable
            onCheckedChanged: {
                Config.options.bar.mediaPlayer.artwork.enable = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "volume_up"
            text: Translation.tr("Scroll to change player volume")
            checked: Config.options.bar.mediaPlayer.enableVolumeScroll
            onCheckedChanged: {
                Config.options.bar.mediaPlayer.enableVolumeScroll = checked;
            }
            StyledToolTip {
                text: Translation.tr("Scroll on the media widget to adjust the active player's volume")
            }
        }
    }

    ContentSection {
        icon: "subtitles"
        title: Translation.tr("Lyrics")

        ConfigSpinBox {
            enabled: !Config.options.bar.vertical
            icon: "width_full"
            text: Translation.tr("Lyrics width")
            value: Config.options.bar.mediaPlayer.lyrics.customSize
            from: 100
            to: 750
            stepSize: 25
            onValueChanged: {
                Config.options.bar.mediaPlayer.lyrics.customSize = value;
            }
        }

        ConfigSwitch {
            buttonIcon: "subtitles"
            text: Translation.tr("Enable lyrics")
            checked: Config.options.bar.mediaPlayer.lyrics.enable
            onCheckedChanged: {
                Config.options.bar.mediaPlayer.lyrics.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Lyrics will be visible when they are fetched with API")
            }
        }

        ContentSubsection {
            title: Translation.tr("Lyrics style")
            icon: "style"
            visible: Config.options.bar.mediaPlayer.lyrics.enable

            ConfigSelectionArray {
                currentValue: Config.options.bar.mediaPlayer.lyrics.style
                onSelected: newValue => {
                    Config.options.bar.mediaPlayer.lyrics.style = newValue;
                }
                options: [
                    { displayName: Translation.tr("Static"),   icon: "format_size",              value: "static" },
                    { displayName: Translation.tr("Scroller"), icon: "keyboard_double_arrow_up", value: "scroller" }
                ]
            }
        }

        ConfigSwitch {
            enabled: Config.options.bar.mediaPlayer.lyrics.enable && Config.options.bar.mediaPlayer.lyrics.style === "scroller"
            buttonIcon: "gradient"
            text: Translation.tr("Use gradient mask")
            checked: Config.options.bar.mediaPlayer.lyrics.useGradientMask
            onCheckedChanged: {
                Config.options.bar.mediaPlayer.lyrics.useGradientMask = checked;
            }
        }
    }

    Component {
        id: ringHorizontalPreview
        RingMedia {
            vertical: false
            previewMode: true
        }
    }

    Component {
        id: ringVerticalPreview
        RingMedia {
            vertical: true
            previewMode: true
        }
    }

    Component {
        id: tonalHorizontalPreview
        TonalMedia {
            vertical: false
            previewMode: true
        }
    }

    Component {
        id: tonalVerticalPreview
        TonalMedia {
            vertical: true
            previewMode: true
        }
    }
}
