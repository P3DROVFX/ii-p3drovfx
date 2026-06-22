import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
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
            text: Translation.tr("Work Safety & Policies")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }
    ContentSection {
        icon: "policy"
        title: Translation.tr("Work Safety & Policies")

        ContentSubsectionLabel { text: Translation.tr("Hiding Suspects") }

        ConfigSwitch {
            buttonIcon: "assignment"
            text: Translation.tr("Hide clipboard images")
            checked: Config.options.workSafety.enable.clipboard
            onCheckedChanged: {
                Config.options.workSafety.enable.clipboard = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "wallpaper"
            text: Translation.tr("Hide suspect/anime wallpapers")
            checked: Config.options.workSafety.enable.wallpaper
            onCheckedChanged: {
                Config.options.workSafety.enable.wallpaper = checked;
            }
        }

    }

    ContentSection {
        icon: "smartphone"
        title: Translation.tr("Phone & scrcpy Integration")

        ContentSubsectionLabel { text: Translation.tr("Connection Settings") }

        ConfigSwitch {
            buttonIcon: "wifi"
            text: Translation.tr("Use wireless debugging")
            checked: Config.options.phone.scrcpy.useWireless
            onCheckedChanged: {
                Config.options.phone.scrcpy.useWireless = checked;
            }
        }

        ConfigTextField {
            icon: "dns"
            text: Translation.tr("Wireless IP")
            placeholderText: Translation.tr("e.g. 192.168.1.50")
            inputText: Config.options.phone.scrcpy.wirelessIp
            textField.onTextChanged: {
                Config.options.phone.scrcpy.wirelessIp = textField.text;
            }
            enabled: Config.options.phone.scrcpy.useWireless
        }

        ConfigTextField {
            icon: "tag"
            text: Translation.tr("Wireless Port")
            placeholderText: Translation.tr("Default: 5555")
            inputText: Config.options.phone.scrcpy.wirelessPort
            textField.onTextChanged: {
                Config.options.phone.scrcpy.wirelessPort = textField.text;
            }
            enabled: Config.options.phone.scrcpy.useWireless
        }

        ConfigSwitch {
            buttonIcon: "terminal"
            text: Translation.tr("Show terminal window")
            checked: Config.options.phone.scrcpy.showTerminal
            onCheckedChanged: {
                Config.options.phone.scrcpy.showTerminal = checked;
            }
        }

        ContentSubsectionLabel { text: Translation.tr("scrcpy Options") }

        ConfigSwitch {
            buttonIcon: "lock"
            text: Translation.tr("Stay awake")
            checked: Config.options.phone.scrcpy.stayAwake
            onCheckedChanged: {
                Config.options.phone.scrcpy.stayAwake = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "phone_android"
            text: Translation.tr("Turn screen off")
            checked: Config.options.phone.scrcpy.turnScreenOff
            onCheckedChanged: {
                Config.options.phone.scrcpy.turnScreenOff = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("No power on device")
            checked: Config.options.phone.scrcpy.noPowerOn
            onCheckedChanged: {
                Config.options.phone.scrcpy.noPowerOn = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "volume_off"
            text: Translation.tr("No audio forwarding")
            checked: Config.options.phone.scrcpy.noAudio
            onCheckedChanged: {
                Config.options.phone.scrcpy.noAudio = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "gesture"
            text: Translation.tr("Show touches")
            checked: Config.options.phone.scrcpy.showTouches
            onCheckedChanged: {
                Config.options.phone.scrcpy.showTouches = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "fullscreen"
            text: Translation.tr("Fullscreen")
            checked: Config.options.phone.scrcpy.fullscreen
            onCheckedChanged: {
                Config.options.phone.scrcpy.fullscreen = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "vertical_align_top"
            text: Translation.tr("Always on top")
            checked: Config.options.phone.scrcpy.alwaysOnTop
            onCheckedChanged: {
                Config.options.phone.scrcpy.alwaysOnTop = checked;
            }
        }

        ConfigSlider {
            buttonIcon: "speed"
            text: Translation.tr("Max FPS")
            value: Config.options.phone.scrcpy.maxFps
            from: 0
            to: 120
            stepSize: 5
            usePercentTooltip: false
            onValueChanged: {
                Config.options.phone.scrcpy.maxFps = value;
            }
        }

        ConfigTextField {
            icon: "wifi_tethering"
            text: Translation.tr("Bitrate")
            placeholderText: Translation.tr("e.g. 8M, 4M")
            inputText: Config.options.phone.scrcpy.bitRate
            textField.onTextChanged: {
                Config.options.phone.scrcpy.bitRate = textField.text;
            }
        }

        ConfigSlider {
            buttonIcon: "aspect_ratio"
            text: Translation.tr("Max Size (0 for unrestricted)")
            value: Config.options.phone.scrcpy.maxSize
            from: 0
            to: 3840
            stepSize: 120
            usePercentTooltip: false
            onValueChanged: {
                Config.options.phone.scrcpy.maxSize = value;
            }
        }

        ConfigSlider {
            buttonIcon: "av_timer"
            text: Translation.tr("Video Buffer (ms)")
            value: Config.options.phone.scrcpy.videoBuffer
            from: 0
            to: 1000
            stepSize: 10
            usePercentTooltip: false
            onValueChanged: {
                Config.options.phone.scrcpy.videoBuffer = value;
            }
        }
    }
}

