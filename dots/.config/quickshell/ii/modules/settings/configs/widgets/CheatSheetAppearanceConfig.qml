import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
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
                text: Translation.tr("Cheatsheet Key Symbols & Font")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            title: Translation.tr("Key Symbols & Display")
            icon: "keyboard"
            tooltip: Translation.tr("Customize key glyphs, modifier symbols and font scaling.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ContentSubsection {
                    title: Translation.tr("Super key symbol")
                    icon: "keyboard_command_key"
                    Layout.fillWidth: true

                    ConfigSelectionArray {
                        currentValue: Config.options.cheatsheet.superKey
                        onSelected: (newValue) => {
                            Config.options.cheatsheet.superKey = newValue;
                        }
                        options: (["󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "", "", "", "󱄛", "", "", "", "⌘", "󰀲", "󰟍", ""]).map((icon) => {
                            return {
                                "displayName": icon,
                                "value": icon
                            };
                        })
                    }
                }

                ConfigSwitch {
                    buttonIcon: "󰘵"
                    text: Translation.tr("Use macOS-like symbols for mods keys")
                    checked: Config.options.cheatsheet.useMacSymbol
                    onCheckedChanged: {
                        Config.options.cheatsheet.useMacSymbol = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "󱊶"
                    text: Translation.tr("Use symbols for function keys")
                    checked: Config.options.cheatsheet.useFnSymbol
                    onCheckedChanged: {
                        Config.options.cheatsheet.useFnSymbol = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "󰍽"
                    text: Translation.tr("Use symbols for mouse")
                    checked: Config.options.cheatsheet.useMouseSymbol
                    onCheckedChanged: {
                        Config.options.cheatsheet.useMouseSymbol = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "highlight_keyboard_focus"
                    text: Translation.tr("Split buttons")
                    checked: Config.options.cheatsheet.splitButtons
                    onCheckedChanged: {
                        Config.options.cheatsheet.splitButtons = checked;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "filter_alt"
                    text: Translation.tr("Filter unbinds")
                    checked: Config.options.cheatsheet.filterUnbinds
                    onCheckedChanged: {
                        Config.options.cheatsheet.filterUnbinds = checked;
                    }
                }
            }
        }

        ContentSection {
            title: Translation.tr("Typography & Font Size")
            icon: "format_size"
            tooltip: Translation.tr("Adjust the font size of key labels and descriptions.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSpinBox {
                    icon: "format_size"
                    text: Translation.tr("Keybind font size")
                    value: Config.options.cheatsheet.fontSize.key
                    from: 8
                    to: 30
                    stepSize: 1
                    onValueChanged: {
                        Config.options.cheatsheet.fontSize.key = value;
                    }
                }

                ConfigSpinBox {
                    icon: "text_fields"
                    text: Translation.tr("Description font size")
                    value: Config.options.cheatsheet.fontSize.comment
                    from: 8
                    to: 30
                    stepSize: 1
                    onValueChanged: {
                        Config.options.cheatsheet.fontSize.comment = value;
                    }
                }
            }
        }
    }
}
