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
    readonly property bool usesVideo: !root.usesWallpaperEngine && Wallpapers.isVideoFile(root.effectivePath.toLowerCase())
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

    StyledImage {
        id: still
        anchors.fill: parent
        visible: !root.usesVideo && status !== Image.Error
        fillMode: Image.PreserveAspectCrop
        cache: !root.usesWallpaperEngine
        source: root.usesVideo ? ""
            : root.usesWallpaperEngine ? "file:///tmp/wpe_screenshot.png?t=" + root.background.wallpaperEngineId
            : root.effectivePath !== "" ? root.effectivePath : root.defaultPath
    }

    ThumbnailImage {
        id: video
        anchors.fill: parent
        visible: root.usesVideo
        sourcePath: root.usesVideo ? root.effectivePath : ""
        thumbnailService: Wallpapers
        generateThumbnail: root.usesVideo
        cache: false
        fillMode: Image.PreserveAspectCrop
    }

    StyledImage {
        anchors.fill: parent
        visible: (!root.usesVideo && still.status === Image.Error) || (root.usesVideo && video.status !== Image.Ready)
        fillMode: Image.PreserveAspectCrop
        source: visible ? root.defaultPath : ""
    }
}
