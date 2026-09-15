pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

MouseArea {
    id: root
    required property SystemTrayItem item

    signal menuRequested(var trayItem, var iconItem)

    implicitWidth: 20
    implicitHeight: 20
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor

    onClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) {
            root.item.activate();
        } else if (mouse.button === Qt.MiddleButton) {
            root.item.secondaryActivate();
        } else if (mouse.button === Qt.RightButton) {
            root.menuRequested(root.item, root);
        }
    }

    IconImage {
        anchors.fill: parent
        source: root.item?.icon ?? ""
        asynchronous: true
        mipmap: true
    }
}
