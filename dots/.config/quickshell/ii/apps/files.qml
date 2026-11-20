//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// ii Files: standalone file explorer. Runs in its own process so the shell keeps
// nothing after it closes: qs -p ~/.config/quickshell/ii/apps/files.qml [ipc call files open <dir>]
// Imports resolve against apps/ (slim Appearance/Config/GlobalStates; see apps/README.md).

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

ApplicationWindow {
    id: root
    visible: true
    width: 960
    height: 620
    title: "Files"
    color: Appearance.m3colors.m3background

    property string currentDir: Directories.home

    // One process for every window: the launcher calls this instead of starting a second qs.
    IpcHandler {
        target: "files"
        function open(dir: string): void {
            root.currentDir = dir.length > 0 ? dir : Directories.home;
            root.raise();
            root.requestActivate();
        }
        function quit(): void {
            Qt.quit();
        }
    }

    onClosing: Qt.quit()

    FolderListModel {
        id: folderModel
        folder: "file://" + root.currentDir
        showDirsFirst: true
        showHidden: false
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // Places
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 220
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4

                Repeater {
                    model: [
                        ["home", "Home", Directories.home],
                        ["download", "Downloads", Directories.downloads],
                        ["image", "Pictures", Directories.pictures],
                        ["description", "Documents", Directories.documents],
                        ["music_note", "Music", Directories.music]
                    ]
                    delegate: RippleButtonWithIcon {
                        required property var modelData
                        readonly property string path: modelData[2].replace("file://", "")
                        Layout.fillWidth: true
                        implicitHeight: 44
                        buttonRadius: Appearance.rounding.full
                        materialIcon: modelData[0]
                        mainText: Translation.tr(modelData[1])
                        toggled: root.currentDir === path
                        onClicked: root.currentDir = path
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Toolbar {
                Layout.alignment: Qt.AlignHCenter
                IconToolbarButton {
                    implicitWidth: height
                    text: "arrow_upward"
                    onClicked: root.currentDir = root.currentDir.replace(/\/[^\/]+\/?$/, "") || "/"
                }
                ToolbarTextField {
                    implicitWidth: 420
                    text: root.currentDir
                    onAccepted: root.currentDir = text
                }
            }

            GridView {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 112
                cellHeight: 112
                model: folderModel
                delegate: RippleButton {
                    required property string fileName
                    required property string filePath
                    required property bool fileIsDir
                    width: grid.cellWidth - 8
                    height: grid.cellHeight - 8
                    buttonRadius: Appearance.rounding.normal
                    onDoubleClicked: if (fileIsDir) root.currentDir = filePath
                    contentItem: ColumnLayout {
                        spacing: 4
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: fileIsDir ? "folder" : "draft"
                            fill: fileIsDir ? 1 : 0
                            iconSize: 40
                            color: fileIsDir ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: fileName
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                }
            }
        }
    }
}
