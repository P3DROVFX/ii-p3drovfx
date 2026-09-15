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
            text: Translation.tr("Utility Buttons")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "palette"
        title: Translation.tr("Design")

        ContentSubsection {
            title: Translation.tr("Visual style")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.utilButtons
                onSelected: newValue => Config.options.bar.styles.utilButtons = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Segments"), icon: "view_week", value: "segments" }
                ]
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.utilButtons === "segments"
            materialIcon: "view_week"
            text: Translation.tr("Segments joins the buttons into one track and lets the corners carry the state: square while they are part of the strip, lifting under the pointer, fully round and filled once a toggle is on. Nothing changes width, so the bar never shifts as you move across it.")
        }
    }

    ContentSection {
        icon: "widgets"
        title: Translation.tr("Utility Buttons")

        ConfigSwitch {
            buttonIcon: "content_cut"
            text: Translation.tr("Show Screen Snip")
            checked: Config.options.bar.utilButtons.showScreenSnip
            onCheckedChanged: {
                Config.options.bar.utilButtons.showScreenSnip = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "colorize"
            text: Translation.tr("Show Color Picker")
            checked: Config.options.bar.utilButtons.showColorPicker
            onCheckedChanged: {
                Config.options.bar.utilButtons.showColorPicker = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "keyboard"
            text: Translation.tr("Show Keyboard Toggle")
            checked: Config.options.bar.utilButtons.showKeyboardToggle
            onCheckedChanged: {
                Config.options.bar.utilButtons.showKeyboardToggle = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "mic"
            text: Translation.tr("Show Mic Toggle")
            checked: Config.options.bar.utilButtons.showMicToggle
            onCheckedChanged: {
                Config.options.bar.utilButtons.showMicToggle = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "dark_mode"
            text: Translation.tr("Show Dark/Light Toggle")
            checked: Config.options.bar.utilButtons.showDarkModeToggle
            onCheckedChanged: {
                Config.options.bar.utilButtons.showDarkModeToggle = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "speed"
            text: Translation.tr("Show Performance Profile Toggle")
            checked: Config.options.bar.utilButtons.showPerformanceProfileToggle
            onCheckedChanged: {
                Config.options.bar.utilButtons.showPerformanceProfileToggle = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "videocam"
            text: Translation.tr("Show Record")
            checked: Config.options.bar.utilButtons.showScreenRecord
            onCheckedChanged: {
                Config.options.bar.utilButtons.showScreenRecord = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "imagesmode"
            text: Translation.tr("Show Wallpaper Selector")
            checked: Config.options.bar.utilButtons.showWallpaperToggle
            onCheckedChanged: {
                Config.options.bar.utilButtons.showWallpaperToggle = checked;
            }
        }
    }
}
