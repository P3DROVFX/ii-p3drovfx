import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

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

    // ── Settings ──────────────────────────────────────────────────────────
    ContentSection {
        icon: "music_cast"
        title: Translation.tr("Media Player")

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
}
