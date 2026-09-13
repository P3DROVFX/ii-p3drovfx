import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ListView {
    id: root
    required property var directory
    property var breadcrumbDirectory: ""
    Component.onCompleted: breadcrumbDirectory = directory;
    onDirectoryChanged: {
        breadcrumbDirectory = directory;
    }

    signal navigateToDirectory(string path)

    orientation: ListView.Horizontal
    clip: true
    spacing: 2

    model: breadcrumbDirectory.trim() === "/" ? [""] : breadcrumbDirectory.split("/")
    delegate: SelectionGroupButton {
        id: folderButton
        required property var modelData
        required property int index
        buttonText: index === 0 ? "/" : modelData
        toggled: {
            if (directory.trim() === "/") return index === 0;
            return index === directory.split("/").length - 1
        }
        leftmost: index === 0
        rightmost: {
            if (breadcrumbDirectory.trim() === "/") return true;
            return index === breadcrumbDirectory.split("/").length - 1;
        }

        onClicked: {
            if (index === 0) {
                root.navigateToDirectory("/");
                return;
            }
            const raw = breadcrumbDirectory.split("/").slice(0, index + 1).join("/");
            root.navigateToDirectory(raw === "" ? "/" : raw);
        }
    }
}
