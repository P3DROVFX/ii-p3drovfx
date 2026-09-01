import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()

    ContentPage {
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
                text: Translation.tr("On-Screen Display")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("General")
            icon: "tune"

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Enable OSD")
                checked: Config.options.osd.enable
                onCheckedChanged: {
                    Config.options.osd.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Master switch. When off, no on-screen indicator is shown at all")
                }
            }
        }

        ContentSection {
            title: Translation.tr("Indicators")
            icon: "display_settings"
            tooltip: Translation.tr("Pick which value changes pop up an on-screen indicator.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                enabled: Config.options.osd.enable
                opacity: enabled ? 1.0 : 0.4

                ConfigSwitch {
                    buttonIcon: "volume_up"
                    text: Translation.tr("Volume")
                    checked: Config.options.osd.indicators.volume
                    onCheckedChanged: Config.options.osd.indicators.volume = checked

                    StyledToolTip {
                        text: Translation.tr("Show an indicator when the output volume or mute state changes")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "brightness_medium"
                    text: Translation.tr("Brightness")
                    checked: Config.options.osd.indicators.brightness
                    onCheckedChanged: Config.options.osd.indicators.brightness = checked

                    StyledToolTip {
                        text: Translation.tr("Show an indicator when the screen backlight changes")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "keyboard"
                    text: Translation.tr("Keyboard backlight")
                    description: KeyboardBacklight.available ? "" : Translation.tr("No keyboard backlight detected on this machine")
                    checked: Config.options.osd.indicators.keyboardBrightness
                    onCheckedChanged: Config.options.osd.indicators.keyboardBrightness = checked

                    StyledToolTip {
                        text: Translation.tr("Show an indicator when the keyboard backlight level changes")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "music_note"
                    text: Translation.tr("Media volume")
                    checked: Config.options.osd.indicators.playerVolume
                    onCheckedChanged: Config.options.osd.indicators.playerVolume = checked

                    StyledToolTip {
                        text: Translation.tr("Show an indicator when the active media player's own volume changes")
                    }
                }

                ConfigSwitch {
                    buttonIcon: "wb_twilight"
                    text: Translation.tr("Night Light")
                    checked: Config.options.osd.indicators.gamma
                    onCheckedChanged: Config.options.osd.indicators.gamma = checked

                    StyledToolTip {
                        text: Translation.tr("Show an indicator when the screen color temperature changes")
                    }
                }
            }
        }
    }
}
