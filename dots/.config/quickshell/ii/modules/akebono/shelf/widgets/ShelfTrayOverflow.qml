pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray

Item {
    id: root
    property real barHeight: 54
    property var shelf

    readonly property var items: TrayService.unpinnedItems
    readonly property real iconSize: Math.round(barHeight * 0.46)
    readonly property real pad: 14
    readonly property int maxCols: 4

    implicitWidth: grid.implicitWidth + pad * 2
    implicitHeight: grid.implicitHeight + pad * 2

    GridLayout {
        id: grid
        anchors.centerIn: parent
        columns: Math.max(1, Math.min(root.maxCols, root.items.length))
        columnSpacing: 14
        rowSpacing: 14

        Repeater {
            model: ScriptModel {
                objectProp: "id"
                values: root.items
            }
            delegate: ShelfTrayIcon {
                required property SystemTrayItem modelData
                item: modelData
                Layout.preferredWidth: root.iconSize
                Layout.preferredHeight: root.iconSize
                Layout.alignment: Qt.AlignCenter
                onMenuRequested: (trayItem, iconItem) => root.shelf.showTrayMenu(trayItem, iconItem)
            }
        }
    }
}
