pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Floating M3 Expressive multi-selection action bar (lazy-loaded only while
 * store.selectionMode is active). Replaces the bottom navbar with:
 *   - Close (X) to cancel selection
 *   - Count pill
 *   - Favorite / Move to folder / Send to phone / Move to trash
 */
Item {
    id: root

    required property var store
    required property var phoneBridge

    property bool moveMenuOpen: false
    property bool confirmTrash: false

    implicitWidth: barRect.implicitWidth
    implicitHeight: barRect.implicitHeight

    Process {
        id: movePickerProc
        command: ["python3", store.scanScriptPath, "pick-folder", "--title", Translation.tr("Move selected items to…")]
        stdout: StdioCollector {
            onStreamFinished: {
                const dest = String(this.text ?? "").trim();
                if (dest.length > 0) {
                    root.moveMenuOpen = false;
                    store.moveSelectedTo(dest);
                }
            }
        }
    }

    // Move-to-folder floating popover above the bar
    Rectangle {
        visible: root.moveMenuOpen
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: barRect.top
        anchors.bottomMargin: 10
        width: 280
        implicitHeight: moveCol.implicitHeight + 20
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh

        ColumnLayout {
            id: moveCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            StyledText {
                Layout.leftMargin: 8
                Layout.topMargin: 2
                Layout.bottomMargin: 4
                text: Translation.tr("MOVE TO FOLDER")
                font.family: Appearance.font.family.main
                font.pixelSize: 11
                font.letterSpacing: 0.8
                font.variableAxes: ({ "wght": 720, "wdth": 100, "ROND": 100 })
                color: Appearance.colors.colOnSurfaceVariant
            }

            Repeater {
                model: store.folders

                delegate: RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 40
                    leftPadding: 10
                    rightPadding: 12
                    buttonRadius: Appearance.rounding.small
                    colBackground: "transparent"
                    colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.90)
                    onClicked: {
                        root.moveMenuOpen = false;
                        store.moveSelectedTo(modelData.path);
                    }
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            text: store.folderIcon(parent.parent.modelData.name)
                            iconSize: 18
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: parent.parent.modelData.name
                            font.family: Appearance.font.family.main
                            font.pixelSize: 14
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: parent.parent.modelData.path
                            font.family: Appearance.font.family.main
                            font.pixelSize: 11
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideMiddle
                            Layout.maximumWidth: 110
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Appearance.colors.colOutlineVariant
                opacity: 0.5
            }

            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 40
                leftPadding: 10
                rightPadding: 12
                buttonRadius: Appearance.rounding.small
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.90)
                onClicked: {
                    if (!movePickerProc.running)
                        movePickerProc.running = true;
                }
                contentItem: RowLayout {
                    spacing: 10
                    MaterialSymbol {
                        text: "folder_open"
                        iconSize: 18
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Choose another folder…")
                        font.family: Appearance.font.family.main
                        font.pixelSize: 14
                        color: Appearance.colors.colOnSurface
                    }
                }
            }
        }
    }

    // Main floating action bar
    Rectangle {
        id: barRect
        implicitWidth: barRow.implicitWidth + 18
        implicitHeight: 62
        radius: Appearance.rounding.full
        color: Appearance.m3colors.m3surfaceContainerHigh

        RowLayout {
            id: barRow
            anchors.centerIn: parent
            spacing: 6

            // Close (X) button to cancel multi-selection
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: hovered ? 14 : 22
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.86)
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                onClicked: store.clearSelection()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 20
                    color: Appearance.colors.colOnSurface
                }
                StyledToolTip { requireOverlay: false; text: Translation.tr("Cancel selection (Esc)") }
            }

            // Selected count pill
            Rectangle {
                implicitWidth: countTxt.implicitWidth + 22
                implicitHeight: 38
                radius: 19
                color: Appearance.colors.colPrimary

                StyledText {
                    id: countTxt
                    anchors.centerIn: parent
                    text: store.selectedCount === 1
                        ? Translation.tr("1 selected")
                        : Translation.tr("%1 selected").arg(store.selectedCount)
                    font.family: Appearance.font.family.main
                    font.pixelSize: 14
                    font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                    color: Appearance.colors.colOnPrimary
                }
            }

            // Divider
            Rectangle {
                implicitWidth: 1
                implicitHeight: 24
                color: Appearance.colors.colOutlineVariant
                opacity: 0.5
            }

            // Favorite batch
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: hovered ? 14 : 22
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.88)
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                onClicked: store.favoriteSelected()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "favorite"
                    iconSize: 21
                    color: Appearance.colors.colOnSurface
                }
                StyledToolTip { requireOverlay: false; text: Translation.tr("Favorite selected") }
            }

            // Move to folder batch
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: (root.moveMenuOpen || hovered) ? 14 : 22
                colBackground: root.moveMenuOpen ? Appearance.colors.colSecondaryContainer : "transparent"
                colBackgroundHover: root.moveMenuOpen
                    ? Appearance.colors.colSecondaryContainerHover
                    : ColorUtils.transparentize(Appearance.colors.colOnSurface, 0.88)
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                onClicked: {
                    root.confirmTrash = false;
                    root.moveMenuOpen = !root.moveMenuOpen;
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "drive_file_move"
                    iconSize: 21
                    color: root.moveMenuOpen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                }
                StyledToolTip { requireOverlay: false; text: Translation.tr("Move to folder") }
            }

            // Send to phone batch (via ii tools)
            RippleButton {
                implicitWidth: 44
                implicitHeight: 44
                buttonRadius: hovered ? 14 : 22
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                onClicked: {
                    root.moveMenuOpen = false;
                    root.confirmTrash = false;
                    phoneBridge.sendFilesToPhone(store.selectedPaths);
                    store.clearSelection();
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "send_to_mobile"
                    iconSize: 20
                    color: Appearance.colors.colOnSecondaryContainer
                }
                StyledToolTip { requireOverlay: false; text: Translation.tr("Send selected to phone") }
            }

            // Trash batch (click once to arm confirm, click again to move to trash)
            RippleButton {
                implicitWidth: root.confirmTrash ? (trashConfRow.implicitWidth + 24) : 44
                implicitHeight: 44
                buttonRadius: (root.confirmTrash || hovered) ? 14 : 22
                colBackground: root.confirmTrash ? Appearance.m3colors.m3errorContainer : "transparent"
                colBackgroundHover: Appearance.m3colors.m3errorContainer
                Behavior on buttonRadius { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on implicitWidth { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                onClicked: {
                    root.moveMenuOpen = false;
                    if (root.confirmTrash) {
                        root.confirmTrash = false;
                        store.trashSelected();
                    } else {
                        root.confirmTrash = true;
                    }
                }
                contentItem: RowLayout {
                    id: trashConfRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: "delete"
                        iconSize: 21
                        color: (root.confirmTrash || parent.parent.hovered)
                            ? Appearance.m3colors.m3onErrorContainer
                            : Appearance.colors.colOnSurface
                    }
                    StyledText {
                        visible: root.confirmTrash
                        text: Translation.tr("Confirm")
                        font.family: Appearance.font.family.main
                        font.pixelSize: 13
                        font.variableAxes: ({ "wght": 660, "wdth": 100, "ROND": 100 })
                        color: Appearance.m3colors.m3onErrorContainer
                    }
                }
                StyledToolTip {
                    requireOverlay: false
                    text: root.confirmTrash ? Translation.tr("Click again to move to trash") : Translation.tr("Move selected to trash")
                }
            }
        }
    }
}
