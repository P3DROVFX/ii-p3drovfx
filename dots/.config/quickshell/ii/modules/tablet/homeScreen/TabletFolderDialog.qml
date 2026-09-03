pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Folder expansion dialog: opens when an App Folder on the home screen is tapped.
 *
 * Shows the apps contained within the folder in an M3 surface card, allowing launching,
 * inline renaming, ejecting apps back to the home screen, or picking more apps to add.
 */
Item {
    id: root

    property int workspaceId: TabletHomeIcons.currentWorkspace
    property var folderData: null
    property bool editing: false
    property bool pickingApp: false

    visible: root.folderData !== null
    anchors.fill: parent
    z: 200

    readonly property var folderApps: root.folderData?.apps ?? []
    readonly property string folderName: root.folderData?.name ?? Translation.tr("Folder")
    readonly property string folderId: root.folderData?.id ?? ""

    function close() {
        root.folderData = null;
        root.editing = false;
        root.pickingApp = false;
    }

    // Dimmed background: tapping outside closes the folder
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.width - 40, 420)
        implicitHeight: Math.min(root.height - 80, cardContent.implicitHeight + 40)
        radius: Appearance.rounding.verylarge
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Absorb clicks on the card so it doesn't dismiss
        MouseArea {
            anchors.fill: parent
            preventStealing: true
        }

        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            // Header: Title and action buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                TextInput {
                    id: titleInput
                    Layout.fillWidth: true
                    text: root.folderName
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.bold: true
                    color: Appearance.colors.colOnSurface
                    selectByMouse: true
                    onEditingFinished: {
                        if (titleInput.text.trim().length > 0) {
                            TabletHomeIcons.renameFolder(root.workspaceId, root.folderId, titleInput.text.trim());
                        }
                    }
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.editing = !root.editing
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.editing ? "done" : "edit"
                        iconSize: 20
                        color: Appearance.colors.colOnSurface
                    }
                }

                RippleButton {
                    implicitWidth: 36
                    implicitHeight: 36
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 20
                        color: Appearance.colors.colOnSurface
                    }
                }
            }

            // Normal mode: Grid of folder apps
            Flow {
                Layout.fillWidth: true
                visible: !root.pickingApp
                spacing: 16

                Repeater {
                    model: root.folderApps

                    delegate: Item {
                        id: appCell
                        required property string modelData
                        width: 76
                        height: 84

                        readonly property var entry: TaskbarApps.getCachedDesktopEntry(appCell.modelData)

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4

                            IconImage {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 52
                                source: Quickshell.iconPath(TaskbarApps.getCachedIcon(appCell.modelData), "image-missing")
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: appCell.entry?.name ?? appCell.modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        // Remove badge when editing
                        Rectangle {
                            visible: root.editing
                            anchors.right: parent.right
                            anchors.top: parent.top
                            width: 22
                            height: 22
                            radius: 11
                            color: Appearance.m3colors.m3error

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "remove"
                                iconSize: 14
                                color: Appearance.m3colors.m3onError
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    TabletHomeIcons.removeAppFromFolder(root.workspaceId, root.folderId, appCell.modelData);
                                    if (root.folderApps.length <= 1)
                                        root.close();
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            visible: !root.editing
                            onClicked: {
                                appCell.entry?.execute();
                                root.close();
                            }
                        }
                    }
                }

                // Add app button inside folder
                Item {
                    width: 76
                    height: 84

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 52
                            implicitHeight: 52
                            radius: 26
                            color: Appearance.colors.colSurfaceContainerHigh
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "add"
                                iconSize: 24
                                color: Appearance.colors.colPrimary
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Add")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.pickingApp = true
                    }
                }
            }

            // Picking app mode: pick an app to add to this folder
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.pickingApp
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Add app to folder")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.bold: true
                    }

                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.pickingApp = false
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "arrow_back"
                            iconSize: 20
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                StyledFlickable {
                    Layout.fillWidth: true
                    implicitHeight: 200
                    contentHeight: pickCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: pickCol
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: Array.from(AppSearch.list ?? []).filter(e => e && e.id && !e.noDisplay && (root.folderApps.indexOf(e.id) === -1))

                            delegate: Rectangle {
                                id: pickRow
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 48
                                radius: Appearance.rounding.normal
                                color: pickArea.pressed ? Appearance.colors.colLayer2Active : (pickArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 12

                                    IconImage {
                                        implicitSize: 32
                                        source: Quickshell.iconPath(AppSearch.guessIcon(pickRow.modelData.id), "image-missing")
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: pickRow.modelData.name ?? pickRow.modelData.id
                                        color: Appearance.colors.colOnSurface
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    MaterialSymbol {
                                        text: "add"
                                        iconSize: 20
                                        color: Appearance.colors.colPrimary
                                    }
                                }

                                MouseArea {
                                    id: pickArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        TabletHomeIcons.addAppToFolder(root.workspaceId, root.folderId, pickRow.modelData.id);
                                        root.pickingApp = false;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
