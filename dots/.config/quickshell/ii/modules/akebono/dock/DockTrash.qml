pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell

Item {
    id: root
    property int iconSize: 36
    signal menuRequested(real centerX)

    readonly property string trashFilesDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/Trash/files"
    readonly property bool full: trashModel.count > 0
    property bool dragHover: false

    implicitWidth: root.iconSize + 18
    implicitHeight: root.iconSize + 18

    transformOrigin: Item.Bottom
    scale: root.dragHover ? 1.15 : (trashMouse.containsMouse ? 1.1 : 1.0)
    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

    FolderListModel {
        id: trashModel
        folder: "file://" + root.trashFilesDir
        showHidden: true
        showDirsFirst: false
    }

    Squircle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Appearance.rounding.normal
        visible: color.a > 0
        color: root.dragHover ? Qt.alpha(Appearance.colors.colError, 0.22)
            : (trashMouse.containsMouse ? Qt.alpha(Appearance.colors.colOnLayer0, 0.1) : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MaterialSymbol {
        id: trashIcon
        anchors.centerIn: parent
        text: "glass_cup"
        fill: 1
        iconSize: root.iconSize
        color: root.dragHover ? Appearance.colors.colError : Appearance.colors.colOnLayer0
    }

    Rectangle {
        visible: root.full && !root.dragHover
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.rightMargin: 6
        anchors.topMargin: 6
        width: 9
        height: 9
        radius: width / 2
        color: Appearance.colors.colPrimary
        border.width: 2
        border.color: Appearance.colors.colLayer0
    }

    MouseArea {
        id: trashMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.menuRequested(root.width / 2);
            else
                Quickshell.execDetached(["dolphin", "trash:/"]);
        }
    }

    DropArea {
        anchors.fill: parent
        onEntered: root.dragHover = true
        onExited: root.dragHover = false
        onDropped: drop => {
            root.dragHover = false;
            if (!drop.hasUrls || drop.urls.length === 0)
                return;
            drop.accept();
            Quickshell.execDetached(["gio", "trash"].concat(drop.urls.map(u => "" + u)));
        }
    }
}
