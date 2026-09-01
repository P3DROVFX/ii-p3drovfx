import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Io
import org.kde.kirigami as Kirigami
import "./widgets"

DockButton {
    id: root

    property var dockContent: null
    property int delegateIndex: -1
    property string filePath: ""

    property int buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: root.dockContent?.dotMargin ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    readonly property real slotWidth: root.dockContent?.buttonSlotSize ?? (root.buttonSize + root.dotMargin * 2)
    readonly property real slotHeight: root.dockContent
        ? (root.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : (root.buttonSize + root.dotMarginV * 2)

    readonly property bool isVertical: dockContent?.isVertical ?? false

    readonly property string fileName: {
        const parts = filePath.split("/").filter(s => s.length > 0);
        return parts[parts.length - 1] ?? filePath;
    }

    readonly property string containingDir: {
        const idx = filePath.lastIndexOf("/");
        return idx > 0 ? filePath.substring(0, idx) : filePath;
    }

    readonly property string mimeIcon: dockContent?.mimeIconFromPath(filePath) ?? "insert_drive_file"

    readonly property bool isDirectory: {
        const lastPart = filePath.toString().split("/").filter(s => s).pop() ?? "";
        return !lastPart.includes(".") || filePath.endsWith("/");
    }

    readonly property bool isImage: /\.(png|jpe?g|webp|gif|svg|bmp|ico)$/i.test(filePath)

    property string cachedXdgIcon: ""

    Process {
        id: mimeQueryProcess
        command: ["xdg-mime", "query", "filetype", root.filePath]
        stdout: SplitParser {
            onRead: line => {
                const mime = line.trim();
                if (mime !== "")
                    root.cachedXdgIcon = mime.replace("/", "-");
            }
        }
    }

    Component.onCompleted: {
        if (!root.isImage && root.filePath !== "" && !root.isDirectory)
            mimeQueryProcess.running = true;
    }

    onFilePathChanged: {
        if (!root.isImage && root.filePath !== "" && !root.isDirectory) {
            root.cachedXdgIcon = "";
            mimeQueryProcess.running = true;
        }
    }

    readonly property string resolvedXdgIcon: {
        TaskbarApps.iconThemeRevision;
        const dirs = TaskbarApps.xdgUserDirs;

        if (root.isDirectory) {
            const map = {
                [dirs.downloads]: "folder-downloads",
                [dirs.documents]: "folder-documents",
                [dirs.pictures]: "folder-pictures",
                [dirs.music]: "folder-music",
                [dirs.videos]: "folder-videos",
                [dirs.desktop]: "folder-desktop",
                [dirs.publicshare]: "folder-publicshare",
                [dirs.templates]: "folder-templates"
            };
            return Quickshell.iconPath(map[filePath.toString()] ?? "folder", "folder");
        }

        if (root.isImage)
            return "";
        if (root.cachedXdgIcon !== "")
            return Quickshell.iconPath(root.cachedXdgIcon, "text-x-generic");
        return Quickshell.iconPath("text-x-generic", "application-x-generic");
    }

    width: root.slotWidth
    height: root.slotHeight
    readonly property real magScale: root.dockMagnificationScale

    transformOrigin: {
        let pos = root.dockContent?.dockPos ?? "bottom";
        if (pos === "top")
            return Item.Top;
        if (pos === "left")
            return Item.Left;
        if (pos === "right")
            return Item.Right;
        return Item.Bottom;
    }

    scale: (_pressed ? 0.88 : 1.0) * magScale
    z: Math.round(magScale * 10)

    property bool _pressed: false
    property bool fileHovered: false

    // Hover tracking for tooltip (separate from drag overlay, matches DockAppButton pattern)
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
        onEntered: {
            root.fileHovered = true;
            if (dockContent?.suppressHover)
                return;
            dockContent?.onButtonEntered(root);
        }
        onExited: {
            root.fileHovered = false;
            dockContent?.onButtonExited(root);
        }
    }

    // Drag overlay (dots-hyprland pattern)
    Loader {
        anchors.fill: parent
        z: 10
        active: true
        sourceComponent: MouseArea {
            id: dragOverlay
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            property real pressCoord: 0
            property bool dragActive: false

            onPressed: event => {
                root._pressed = true;
                if (event.button === Qt.LeftButton) {
                    pressCoord = root.isVertical ? event.y : event.x;
                }
            }
            onPositionChanged: event => {
                if (!pressed || event.button !== Qt.LeftButton)
                    return;
                var cur = root.isVertical ? event.y : event.x;
                var dist = Math.abs(cur - pressCoord);
                if (!dragActive && dist > 5) {
                    dragActive = true;
                    root._pressed = false;
                    if (dockContent) {
                        dockContent.buttonHovered = false;
                        dockContent.lastHoveredButton = null;
                        dockContent.startItemDrag(root.delegateIndex, dragOverlay, event.x, event.y);
                    }
                }
                if (dragActive) {
                    if (dockContent)
                        dockContent.moveItemDrag(dragOverlay, event.x, event.y);
                }
            }
            onReleased: event => {
                root._pressed = false;
                if (dragActive) {
                    dragActive = false;
                    if (dockContent)
                        dockContent.endItemDrag();
                    return;
                }
                if (event.button === Qt.RightButton) {
                    if (dockContent) {
                        dockContent.buttonHovered = false;
                        dockContent.lastHoveredButton = null;
                    }
                    fileContextMenu.open();
                    return;
                }
                if (root.isDirectory) {
                    stackPopup.open();
                    return;
                }
                Quickshell.execDetached({
                    command: ["xdg-open", root.filePath]
                });
            }
            onCanceled: {
                root._pressed = false;
                if (dragActive) {
                    dragActive = false;
                    if (dockContent)
                        dockContent.cancelDrag();
                }
            }
        }
    }

    DockStackPopup {
        id: stackPopup
        folderPath: root.filePath
        anchorItem: root
    }

    DockFileContextMenu {
        id: fileContextMenu
        filePath: root.filePath
        anchorItem: root
    }

    Connections {
        target: fileContextMenu
        function onActiveChanged() {
            if (!dockContent)
                return;
            if (fileContextMenu.active)
                dockContent.registerContextMenuOpen();
            else
                dockContent.registerContextMenuClose();
        }
    }

    // Safety: if this button is destroyed while menu is open, clean up the counter
    Component.onDestruction: {
        if (dockContent && fileContextMenu.active)
            dockContent.registerContextMenuClose();
    }

    DockTooltip {
        id: fileTooltip
        parentItem: root
        text: root.fileName
        showTooltip: root.fileHovered
        tooltipOffset: -root.dotMargin
    }

    contentItem: Item {
        anchors.fill: parent

        Item {
            id: fileIconContainer
            width: root.buttonSize
            height: root.buttonSize
            anchors.centerIn: parent

            MaterialShape {
                id: iconMask
                width: Math.max(1, fileIconContainer.width)
                height: Math.max(1, fileIconContainer.height)
                shapeString: Config.options.appearance.icons.shapeMask
                visible: false
            }

            layer.enabled: Config.options.appearance.icons.enableShapeMask
            layer.effect: OpacityMask {
                maskSource: iconMask
            }

            Image {
                id: thumbnailImage
                anchors.fill: parent
                visible: root.isImage
                source: root.isImage ? ("file://" + root.filePath) : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize: Qt.size(root.buttonSize * 2, root.buttonSize * 2)

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: thumbnailImage.width
                        height: thumbnailImage.height
                        radius: Appearance.rounding.small
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.isImage && thumbnailImage.status !== Image.Ready
                text: "image"
                iconSize: root.buttonSize
                color: Appearance.colors.colOnLayer0
            }

            IconImage {
                id: xdgIconImage
                anchors.fill: parent
                visible: !root.isImage && root.resolvedXdgIcon !== ""
                source: root.resolvedXdgIcon

                // Force reload when the icon theme regenerates. Resolved on this thread: the
                // shared icon loader is not safe to read from Qt's image thread while the
                // theme is changing under it.
                asynchronous: false
                backer.cache: false
                backer.sourceSize: Qt.size(xdgIconImage.actualSize + TaskbarApps.iconThemeRevision,
                                           xdgIconImage.actualSize + TaskbarApps.iconThemeRevision)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !root.isImage && root.resolvedXdgIcon === "" && root.isDirectory
                text: "folder"
                iconSize: root.buttonSize
                color: Appearance.colors.colOnLayer0
            }
        }
    }
}
