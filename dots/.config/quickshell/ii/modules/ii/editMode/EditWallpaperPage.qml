import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The wallpaper folder, as a grid of thumbnails on Edit Mode's panel.
 *
 * A compact cut of the full selector: the folder the shell already watches,
 * in the order it is already sorted, three to a row. A click applies and the
 * card follows; the applied one carries a mark. Sorting, search, sub-folders
 * and the online browser stay with the selector, which the Style page hands
 * off to.
 *
 * Which wallpaper a pick sets is the page's `target`, decided by the Style
 * page from the tab and the variants: the lock's own, the light mode's, or
 * the desktop's.
 */
Item {
    id: root

    // "desktop", "lockscreen" or "lightmode".
    property string target: "desktop"
    readonly property string appliedPath: {
        const background = Config.options.background;
        const raw = root.target === "lockscreen" ? background.lockscreenWallpaperPath
            : root.target === "lightmode" ? background.lightModeWallpaperPath
            : background.wallpaperPath;
        return FileUtils.trimFileProtocol(String(raw ?? ""));
    }

    readonly property int columns: 3
    readonly property real cellGap: 6
    readonly property real cellWidth: Math.floor((root.width - root.cellGap * (root.columns - 1)) / root.columns)
    readonly property real cellHeight: Math.round(root.cellWidth * 10 / 16)

    // The folder's files, in the service's sorted order. Directories are the
    // selector's navigation, not a wallpaper, so they are left out here.
    readonly property var files: {
        const model = Wallpapers.sortedFolderModel;
        const out = [];
        // Read so the binding follows the model's refills.
        const count = model.count;
        for (let i = 0; i < count; i++) {
            const entry = model.get(i);
            if (!entry || entry.fileIsDir)
                continue;
            const name = String(entry.fileName ?? "");
            if (!Images.isValidImageByName(name) && !Wallpapers.isVideoFile(name))
                continue;
            out.push({
                "filePath": FileUtils.trimFileProtocol(String(entry.filePath ?? "")),
                "fileName": name
            });
        }
        return out;
    }

    function apply(path) {
        if (root.target === "lockscreen") {
            Wallpapers.selectLockscreen(path);
            return;
        }
        if (root.target === "lightmode") {
            Wallpapers.selectLightmode(path);
            return;
        }
        Wallpapers.select(path);
    }

    // The thumbnails are made once for the size the cells draw at, the same
    // way the selector asks for its own.
    Component.onCompleted: {
        Wallpapers.load();
        const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
        Wallpapers.generateThumbnail(Images.thumbnailSizeNameForDimensions(
            Math.ceil(root.cellWidth * dpr), Math.ceil(root.cellHeight * dpr)));
    }

    GridView {
        id: grid
        anchors.fill: parent
        clip: true
        cellWidth: root.cellWidth + root.cellGap
        cellHeight: root.cellHeight + root.cellGap
        model: root.files
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool applied: cell.modelData.filePath === root.appliedPath
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                id: tile
                width: root.cellWidth
                height: root.cellHeight
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.width: cell.applied ? 2 : 1
                border.color: cell.applied ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                scale: tileMouse.containsPress ? 0.96 : 1
                Behavior on scale {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tile)
                }

                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: tile.border.width
                    radius: tile.radius - tile.border.width
                    color: "transparent"

                    ThumbnailImage {
                        anchors.fill: parent
                        sourcePath: cell.modelData.filePath
                        thumbnailService: Wallpapers
                        generateThumbnail: false
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    visible: cell.applied
                    width: 22
                    height: 22
                    radius: width / 2
                    color: Appearance.colors.colPrimary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!cell.applied)
                            root.apply(cell.modelData.filePath);
                    }
                }

                StyledToolTip {
                    requireOverlay: false
                    text: cell.modelData.fileName
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: grid.count === 0
        text: Wallpapers.directoryLoading ? Translation.tr("Loading…") : Translation.tr("No wallpapers in this folder")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnSurfaceVariant
    }
}
