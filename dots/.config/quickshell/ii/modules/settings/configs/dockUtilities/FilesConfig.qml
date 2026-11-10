import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

UtilityConfigPage {
    title: Translation.tr("Files")

    ContentSection {
        title: Translation.tr("Folder")
        icon: "folder"
        tooltip: Translation.tr("The widget shows the newest files of this folder and counts the ones that arrived since you last opened it")

        ConfigTextField {
            icon: "folder_open"
            text: Translation.tr("Folder path")
            placeholderText: Directories.downloads.replace("file://", "")
            inputText: Config.options.dock.utilities.files.folder
            textField.onEditingFinished: Config.options.dock.utilities.files.folder = textField.text.trim()
        }
        NoticeBox {
            Layout.fillWidth: true
            text: Translation.tr("Leave it empty to follow your Downloads folder.")
        }
    }
}
