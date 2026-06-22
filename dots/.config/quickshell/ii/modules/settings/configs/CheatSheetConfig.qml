import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: false

    KeyboardShortcutBox {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        text: Translation.tr("Toggle the Cheatsheet")
        keys: ["Super", "/"]
    }

    ContentSection {
        title: Translation.tr("General Options")
        icon: "keyboard"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ContentSubsection {
                title: Translation.tr("Super key symbol")
                icon: "keyboard_command_key"
                Layout.fillWidth: true
                ConfigSelectionArray {
                    currentValue: Config.options.cheatsheet.superKey
                    onSelected: newValue => {
                        Config.options.cheatsheet.superKey = newValue;
                    }
                    options: (["󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "", "", "", "󱄛", "", "", "", "⌘", "󰀲", "󰟍", ""]).map(icon => {
                        return {
                            displayName: icon,
                            value: icon
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
        }

        Item { Layout.preferredHeight: 16 }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

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

    ContentSection {
        title: Translation.tr("Toggle Widgets")
        icon: "widgets"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                buttonIcon: "mail"
                text: Translation.tr("Enable Gmail")
                checked: Config.options.cheatsheet.enableGmail
                onCheckedChanged: {
                    Config.options.cheatsheet.enableGmail = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "calendar_month"
                text: Translation.tr("Enable Timetable")
                checked: Config.options.cheatsheet.enableTimetable
                onCheckedChanged: {
                    Config.options.cheatsheet.enableTimetable = checked;
                }
            }

            ConfigSwitch {
                enabled: Config.options.cheatsheet.enableTimetable
                buttonIcon: "calendar_today"
                text: Translation.tr("Timetable: start with today")
                checked: Config.options.cheatsheet.timetableTodayFirst
                onCheckedChanged: {
                    Config.options.cheatsheet.timetableTodayFirst = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "experiment"
                text: Translation.tr("Enable Elements")
                checked: Config.options.cheatsheet.enablePeriodicTable
                onCheckedChanged: {
                    Config.options.cheatsheet.enablePeriodicTable = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "terminal"
                text: Translation.tr("Enable Commands")
                checked: Config.options.cheatsheet.enableCommands
                onCheckedChanged: {
                    Config.options.cheatsheet.enableCommands = checked;
                }
            }
        }

        Item { Layout.preferredHeight: 16 }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            ConfigSwitch {
                enabled: Config.options.cheatsheet.enableCommands
                buttonIcon: "table_rows_narrow"
                text: Translation.tr("Commands: sidebar tag layout")
                checked: Config.options.cheatsheet.commandsTagsSidebar
                onCheckedChanged: {
                    Config.options.cheatsheet.commandsTagsSidebar = checked;
                }
            }
        }
    }
}
