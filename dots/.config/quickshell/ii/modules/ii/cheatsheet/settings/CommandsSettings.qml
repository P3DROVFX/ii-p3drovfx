import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/** The Commands tab's settings. */
AppSettingsPage {
    title: Translation.tr("Commands settings")
    subtitle: Translation.tr("Layout")

    AppSettingsSection {
        title: Translation.tr("Layout")
        symbol: "table_rows_narrow"

        AppToggleRow {
            symbol: "table_rows_narrow"
            title: Translation.tr("Commands: sidebar tag layout")
            checked: Config.options.cheatsheet.commandsTagsSidebar
            onToggled: value => Config.options.cheatsheet.commandsTagsSidebar = value
        }
    }
}
