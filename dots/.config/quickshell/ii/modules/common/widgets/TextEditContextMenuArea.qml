import qs.modules.common.widgets
import QtQuick

MouseArea {
    id: root
    required property Item editor

    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    onClicked: (mouse) => {
        contextMenu.x = mouse.x;
        contextMenu.y = mouse.y;
        contextMenu.open();
    }

    TextEditContextMenu {
        id: contextMenu
        editor: root.editor
    }
}
