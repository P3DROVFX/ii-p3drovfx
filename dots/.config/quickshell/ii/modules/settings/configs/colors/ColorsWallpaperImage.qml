import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The picture a wallpaper target is showing, cropped to fill: the image itself, the
 * Wallpaper Engine screenshot, or a video's thumbnail, falling back to the shipped
 * default when the file cannot be read. Unclipped — the card around it owns the shape.
 */
Item {
    id: root

    /// "desktop", "lockscreen" or "lightmode".
    property string targetMode: "desktop"

    readonly property var background: Config.options.background
    readonly property string effectivePath: {
        if (root.targetMode === "lockscreen" && (root.background.lockscreenWallpaperPath ?? "") !== "")
            return root.background.lockscreenWallpaperPath;
        if (root.targetMode === "lightmode" && (root.background.lightModeWallpaperPath ?? "") !== "")
            return root.background.lightModeWallpaperPath;
        return root.background.wallpaperPath ?? "";
    }
    readonly property bool usesWallpaperEngine: root.targetMode === "desktop" && root.background.useWallpaperEngine
    readonly property string defaultPath: `${Directories.assetsPath}/images/default_wallpaper.png`

    readonly property string fileName: {
        if (root.usesWallpaperEngine) {
            const parts = (root.background.wallpaperEngineId ?? "").split("/");
            return parts[parts.length - 1];
        }
        if (root.effectivePath === "")
            return "";
        const parts = root.effectivePath.split("/");
        return parts[parts.length - 1];
    }

    // Thumbnails, never the file itself: a wallpaper is routinely an 8K PNG, and decoding one
    // per card (three cards, re-decoded whenever the card's size and so its sourceSize moved)
    // took seconds. The selector has usually cached the x-large one already, so it shows at
    // once; the card-sized one replaces it when it is cached too, or once it is generated.
    // Hidden cards (no separate lock/light wallpaper) load nothing.
    readonly property string thumbnailSource: !root.visible || root.usesWallpaperEngine ? ""
        : root.effectivePath !== "" ? root.effectivePath : root.defaultPath

    ThumbnailImage {
        id: preview
        anchors.fill: parent
        sourcePath: root.thumbnailSource
        thumbnailSizeName: "x-large"
        generateThumbnail: false
        fillMode: Image.PreserveAspectCrop
    }

    ThumbnailImage {
        id: sharp
        anchors.fill: parent
        sourcePath: root.thumbnailSource
        thumbnailService: Wallpapers
        fillMode: Image.PreserveAspectCrop
    }

    StyledImage {
        id: engineShot
        anchors.fill: parent
        visible: root.usesWallpaperEngine && status !== Image.Error
        fillMode: Image.PreserveAspectCrop
        cache: false
        source: root.usesWallpaperEngine ? "file:///tmp/wpe_screenshot.png?t=" + root.background.wallpaperEngineId : ""
    }

    // Only once nothing above can show: the file is unreadable and no thumbnail could be made.
    StyledImage {
        anchors.fill: parent
        visible: root.usesWallpaperEngine ? engineShot.status === Image.Error
            : root.thumbnailSource !== "" && sharp.status === Image.Error && !sharp.thumbnailGenerationRunning
                && preview.status !== Image.Ready
        fillMode: Image.PreserveAspectCrop
        source: visible ? root.defaultPath : ""
    }
}
