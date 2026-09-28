import QtQuick
import qs.modules.common
import qs.services

/** The Commands tab's settings. */
CheatsheetSettingsPage {
    title: Translation.tr("Commands settings")
    subtitle: Translation.tr("Layout")

    CheatsheetSettingsSection {
        title: Translation.tr("Layout")
        symbol: "table_rows_narrow"

        CheatsheetToggleRow {
            symbol: "table_rows_narrow"
            title: Translation.tr("Commands: sidebar tag layout")
            checked: Config.options.cheatsheet.commandsTagsSidebar
            onToggled: value => Config.options.cheatsheet.commandsTagsSidebar = value
        }
    }
}
