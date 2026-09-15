pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.akebono

Item {
    id: root

    required property var modelData
    readonly property string fileName: modelData.fileName
    readonly property string filePath: modelData.filePath
    readonly property bool fileIsDir: modelData.fileIsDir
    readonly property string displayName: {
        if (root.fileIsDir || (desktop.cfg.showExtensions ?? false))
            return root.fileName;
        const stripped = FileUtils.trimFileExt(root.fileName);
        return stripped.length > 0 ? stripped : root.fileName;
    }

    property var desktop

    readonly property real iconSize: desktop.iconSize
    readonly property var cell: desktop.cellAssignments[fileName] ?? null
    readonly property real cellX: desktop.marginLeft + (cell ? cell.col : 0) * desktop.pitchX
    readonly property real cellY: desktop.marginTop + (cell ? cell.row : 0) * desktop.pitchY
    readonly property bool selected: desktop.selectedFiles.indexOf(fileName) >= 0
    readonly property bool renaming: desktop.renamingFile === fileName
    readonly property bool cutHeld: desktop.clipMode === "cut" && desktop.clipFiles.indexOf(filePath) >= 0
    property bool dragging: false
    property bool placed: false

    width: desktop.cellW
    height: desktop.cellH
    z: dragging ? 10 : (renaming ? 5 : 1)
    opacity: !placed ? 0 : ((dragging || (selected && desktop.dragActive)) ? 0.4 : 1)
    Behavior on opacity { NumberAnimation { duration: 120 } }

    function placeAtCell() {
        root.x = root.cellX;
        root.y = root.cellY;
        if (root.cell && !root.placed)
            Qt.callLater(() => root.placed = true);
    }
    onCellChanged: placeAtCell()
    onCellXChanged: placeAtCell()
    onCellYChanged: placeAtCell()
    Component.onCompleted: placeAtCell()

    function startSystemDrag(hotX, hotY) {
        const multi = root.selected && root.desktop.selectedFiles.length > 1;
        const names = multi ? root.desktop.selectedFiles.slice() : [root.fileName];
        root.Drag.mimeData = root.desktop.buildDragMime(names, root.fileName, hotX, hotY);
        root.Drag.supportedActions = Qt.MoveAction | Qt.CopyAction | Qt.LinkAction;
        root.Drag.proposedAction = Qt.MoveAction;
        root.Drag.dragType = Drag.Automatic;
        root.Drag.hotSpot = Qt.point(hotX, hotY);
        root.dragging = true;
        root.desktop.dragActive = true;
        const onGrab = function (result) {
            if (result)
                root.Drag.imageSource = result.url;
            root.Drag.active = true;
        };
        if (multi)
            root.desktop.grabDragStack(onGrab);
        else
            root.grabToImage(onGrab);
    }

    readonly property bool dragInFlight: Drag.active
    onDragInFlightChanged: {
        if (!root.dragInFlight && root.dragging) {
            root.dragging = false;
            root.desktop.dragActive = false;
            root.placeAtCell();
        }
    }

    Connections {
        target: root.desktop
        function onSettleTickChanged() {
            root.placeAtCell();
        }
    }

    Behavior on x { enabled: root.placed && !root.desktop.groupSnapping; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: root.placed && !root.desktop.groupSnapping; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    Squircle {
        id: highlight
        anchors.fill: parent
        anchors.margins: 3
        radius: Appearance.rounding.large
        visible: highlight.color.a > 0
        color: root.selected ? Qt.alpha(Appearance.colors.colPrimaryContainer, 0.85)
            : (iconMouse.containsMouse ? Qt.alpha(Appearance.colors.colOnLayer0, 0.1) : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    Column {
        anchors.top: parent.top
        anchors.topMargin: 8
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 8
        spacing: 4
        opacity: root.cutHeld ? 0.45 : 1
        Behavior on opacity { NumberAnimation { duration: 150 } }

        DirectoryIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.iconSize
            height: root.iconSize
            cache: false
            fileModelData: root.modelData
        }

        Item {
            visible: !root.renaming
            width: parent.width
            implicitHeight: nameLabel.implicitHeight

            StyledText {
                anchors.fill: nameLabel
                horizontalAlignment: Text.AlignHCenter
                text: nameLabel.text
                font.pixelSize: nameLabel.font.pixelSize
                wrapMode: nameLabel.wrapMode
                maximumLineCount: nameLabel.maximumLineCount
                elide: nameLabel.elide
                color: Appearance.colors.colShadow
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 0.5
                    blurMax: 16
                }
            }
            StyledText {
                id: nameLabel
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.displayName
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        Loader {
            active: root.renaming
            anchors.horizontalCenter: parent.horizontalCenter
            sourceComponent: Squircle {
                id: renameBg
                readonly property real maxW: root.desktop.cellW * 1.6
                implicitWidth: Math.min(Math.max(renameInput.implicitWidth + 14, 44), renameBg.maxW)
                implicitHeight: renameInput.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                TextInput {
                    id: renameInput
                    anchors.fill: parent
                    anchors.leftMargin: 7
                    anchors.rightMargin: 7
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    text: root.fileName
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.family: Appearance.font.family.main
                    selectByMouse: true
                    selectionColor: Appearance.colors.colPrimary
                    selectedTextColor: Appearance.colors.colOnPrimary
                    clip: true
                    Component.onCompleted: {
                        forceActiveFocus();
                        selectAll();
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.desktop.commitRename(root.fileName, text.trim());
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.desktop.cancelRename();
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: iconMouse
        anchors.fill: parent
        visible: !root.renaming
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        property real pressX: 0
        property real pressY: 0
        property bool mayDrag: false

        onPressed: mouse => {
            root.desktop.clicked = true;
            iconMouse.pressX = mouse.x;
            iconMouse.pressY = mouse.y;
            iconMouse.mayDrag = (mouse.button === Qt.LeftButton);
            if (iconMouse.mayDrag)
                root.desktop.dragStackLeader = root.fileName;
            if (mouse.button === Qt.RightButton)
                root.desktop.openIconMenu(root, mouse.x, mouse.y);
            else if (!(root.selected && root.desktop.selectedFiles.length > 1))
                root.desktop.selectFile(root.fileName);
        }
        onPositionChanged: mouse => {
            if (!iconMouse.mayDrag || root.dragging || !(mouse.buttons & Qt.LeftButton))
                return;
            if (Math.abs(mouse.x - iconMouse.pressX) > 8 || Math.abs(mouse.y - iconMouse.pressY) > 8)
                root.startSystemDrag(iconMouse.pressX, iconMouse.pressY);
        }
        onReleased: mouse => {
            iconMouse.mayDrag = false;
            if (!root.dragging && mouse.button === Qt.LeftButton && root.selected && root.desktop.selectedFiles.length > 1)
                root.desktop.selectFile(root.fileName);
        }
        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                root.desktop.openFile(root.filePath, root.fileIsDir);
        }
    }
}
