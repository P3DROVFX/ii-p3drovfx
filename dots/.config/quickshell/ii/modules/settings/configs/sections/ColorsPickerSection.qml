import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Search proxy for the Colors & Themes page's wallpaper picker pane, drawn there as a
// choice row and a field row. SearchRegistry indexes this file (see SettingsPageRegistry
// `searchSources`) so both stay searchable as the original controls.
ColumnLayout {
    ContentSection {
        icon: "imagesmode"
        title: Translation.tr("Wallpaper picker")

        ConfigSwitch {
            buttonIcon: "folder_shared"
            text: Translation.tr("Use the system file dialog")
            checked: Config.options.wallpaperSelector.useSystemFileDialog
            onCheckedChanged: Config.options.wallpaperSelector.useSystemFileDialog = checked
            StyledToolTip {
                text: Translation.tr("Open the system file dialog instead of the built-in picker when you change a wallpaper")
            }
        }

        ConfigTextField {
            Layout.fillWidth: true
            icon: "download"
            text: Translation.tr("Download folder")
            placeholderText: Translation.tr("Download path...")
            inputText: Config.options.wallpapers.paths.download
            tooltip: Translation.tr("Where the wallpaper browser saves images")
            textField.onEditingFinished: Config.options.wallpapers.paths.download = textField.text
        }
    }
}
