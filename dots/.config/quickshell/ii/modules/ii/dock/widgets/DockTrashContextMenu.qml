import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import qs
import ".."

DockContextMenuBase {
    id: root

    property int trashCount: 0

    headerText: Translation.tr("Trash")
    headerSubtitle: root.trashCount === 1 ? Translation.tr("1 item")
        : root.trashCount > 0 ? Translation.tr("%1 items").arg(root.trashCount)
        : Translation.tr("Empty")
    headerSymbol: root.trashCount > 0 ? "delete" : "delete_outline"
    headerIcon: (root.anchorItem?.customImageSource ?? "") !== "" ? trashImage : null

    Component {
        id: trashImage
        Image {
            source: root.anchorItem?.customImageSource ?? ""
            sourceSize: Qt.size(96, 96)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
    }

    menuGroups: root.menuOpen ? [
        [
            { id: "open", icon: "folder_open", text: Translation.tr("Open Trash") }
        ],
        [
            { id: "empty", icon: "delete_sweep", text: Translation.tr("Empty Trash"), destructive: true, visible: root.trashCount > 0 }
        ]
    ] : []

    onActionTriggered: actionId => {
        if (actionId === "open")
            Quickshell.execDetached(["xdg-open", "trash:///"]);
        else if (actionId === "empty" && root.anchorItem && root.anchorItem.dockContent)
            root.anchorItem.dockContent.emptyTrash();
        root.close();
    }
}
