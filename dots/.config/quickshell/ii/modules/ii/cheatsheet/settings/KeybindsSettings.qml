import QtQuick
import qs.modules.common
import qs.services

/** The Keybinds tab's settings: key glyphs, symbols and font sizes. */
CheatsheetSettingsPage {
    id: root

    readonly property var cheatsheet: Config.options.cheatsheet

    title: Translation.tr("Keybinds settings")
    subtitle: Translation.tr("Key symbols & typography")

    CheatsheetSettingsSection {
        title: Translation.tr("Key Symbols & Display")
        symbol: "keyboard"

        CheatsheetChoiceRow {
            symbol: "keyboard_command_key"
            title: Translation.tr("Super key symbol")
            currentValue: root.cheatsheet.superKey
            onSelected: value => root.cheatsheet.superKey = value
            options: (["󰖳", "", "󰨡", "", "󰌽", "󰣇", "", "", "", "", "", "󱄛", "", "", "", "⌘", "󰀲", "󰟍", ""]).map(icon => ({
                "label": icon,
                "value": icon,
                "fontFamily": Appearance.font.family.iconNerd
            }))
        }
        CheatsheetToggleRow {
            symbol: "keyboard_option_key"
            title: Translation.tr("Use macOS-like symbols for mods keys")
            checked: root.cheatsheet.useMacSymbol
            onToggled: value => root.cheatsheet.useMacSymbol = value
        }
        CheatsheetToggleRow {
            symbol: "function"
            title: Translation.tr("Use symbols for function keys")
            checked: root.cheatsheet.useFnSymbol
            onToggled: value => root.cheatsheet.useFnSymbol = value
        }
        CheatsheetToggleRow {
            symbol: "mouse"
            title: Translation.tr("Use symbols for mouse")
            checked: root.cheatsheet.useMouseSymbol
            onToggled: value => root.cheatsheet.useMouseSymbol = value
        }
        CheatsheetToggleRow {
            symbol: "highlight_keyboard_focus"
            title: Translation.tr("Split buttons")
            checked: root.cheatsheet.splitButtons
            onToggled: value => root.cheatsheet.splitButtons = value
        }
        CheatsheetToggleRow {
            symbol: "filter_alt"
            title: Translation.tr("Filter unbinds")
            checked: root.cheatsheet.filterUnbinds
            onToggled: value => root.cheatsheet.filterUnbinds = value
        }
    }

    secondary: CheatsheetSettingsSection {
        title: Translation.tr("Typography & Font Size")
        symbol: "format_size"

        CheatsheetStepperRow {
            symbol: "format_size"
            title: Translation.tr("Keybind font size")
            value: root.cheatsheet.fontSize.key
            from: 8
            to: 30
            onMoved: value => root.cheatsheet.fontSize.key = value
        }
        CheatsheetStepperRow {
            symbol: "text_fields"
            title: Translation.tr("Description font size")
            value: root.cheatsheet.fontSize.comment
            from: 8
            to: 30
            onMoved: value => root.cheatsheet.fontSize.comment = value
        }
    }
}
