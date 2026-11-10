import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: wallpaperSelectorRoot
    property string text: ""
    property string targetMode: "desktop" // "desktop", "lockscreen", or "lightmode"

    implicitWidth: 360
    implicitHeight: 220

    readonly property string effectivePath: {
        if (targetMode === "lockscreen") {
            const lockPath = Config.options.background.lockscreenWallpaperPath;
            return (lockPath && lockPath !== "") ? lockPath : Config.options.background.wallpaperPath;
        }
        if (targetMode === "lightmode") {
            const lightPath = Config.options.background.lightModeWallpaperPath;
            return (lightPath && lightPath !== "") ? lightPath : Config.options.background.wallpaperPath;
        }
        return Config.options.background.wallpaperPath;
    }

    readonly property bool usesWallpaperEnginePreview: targetMode === "desktop" && Config.options.background.useWallpaperEngine
    readonly property bool usesVideoPreview: !usesWallpaperEnginePreview && Wallpapers.isVideoFile(effectivePath.toLowerCase())
    readonly property string defaultPreviewPath: `${Directories.assetsPath}/images/default_wallpaper.png`

    StyledImage {
        id: wallpaperPreview
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        visible: !wallpaperSelectorRoot.usesVideoPreview
        source: {
            if (wallpaperSelectorRoot.usesVideoPreview) {
                return "";
            }
            if (wallpaperSelectorRoot.usesWallpaperEnginePreview) {
                return "file:///tmp/wpe_screenshot.png?t=" + Config.options.background.wallpaperEngineId;
            }
            return wallpaperSelectorRoot.effectivePath !== "" ? wallpaperSelectorRoot.effectivePath : wallpaperSelectorRoot.defaultPreviewPath
        }
        cache: !wallpaperSelectorRoot.usesWallpaperEnginePreview
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: wallpaperPreview.width
                height: wallpaperPreview.height
                radius: Appearance.rounding.normal
            }
        }
    }

    StyledImage {
        id: wallpaperPreviewFallback
        anchors.fill: parent
        visible: !wallpaperSelectorRoot.usesVideoPreview && wallpaperPreview.status === Image.Error
        source: wallpaperSelectorRoot.defaultPreviewPath
        fillMode: Image.PreserveAspectCrop
        cache: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: wallpaperPreviewFallback.width
                height: wallpaperPreviewFallback.height
                radius: Appearance.rounding.normal
            }
        }
    }

    ThumbnailImage {
        id: videoPreview
        anchors.fill: parent
        visible: wallpaperSelectorRoot.usesVideoPreview
        sourcePath: wallpaperSelectorRoot.effectivePath
        thumbnailService: Wallpapers
        generateThumbnail: wallpaperSelectorRoot.usesVideoPreview
        cache: false
        fillMode: Image.PreserveAspectCrop
        clip: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: videoPreview.width
                height: videoPreview.height
                radius: Appearance.rounding.normal
            }
        }
    }

    StyledImage {
        id: videoPreviewFallback
        anchors.fill: parent
        visible: wallpaperSelectorRoot.usesVideoPreview && videoPreview.status !== Image.Ready
        source: wallpaperSelectorRoot.defaultPreviewPath
        fillMode: Image.PreserveAspectCrop
        cache: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: videoPreviewFallback.width
                height: videoPreviewFallback.height
                radius: Appearance.rounding.normal
            }
        }
    }

    RippleButton {
        anchors.fill: parent
        colBackground: "transparent"
        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.85)
        colRipple: ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.5)
        onClicked: {
            if (Config.options.wallpaperSelector.useSystemFileDialog) {
                Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode, wallpaperSelectorRoot.targetMode === "lockscreen");
            } else {
                let action = "toggle";
                if (wallpaperSelectorRoot.targetMode === "lockscreen") action = "toggleLockscreen";
                else if (wallpaperSelectorRoot.targetMode === "lightmode") action = "toggleLightmode";
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", action]);
            }
        }
    }

    MaterialSymbol {
        anchors.centerIn: parent
        text: "hourglass_top"
        color: Appearance.colors.colPrimary
        iconSize: 40
        z: -1
        visible: false
    }

    Rectangle {
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: 10
        }

        implicitWidth: Math.min(fileNameLabel.implicitWidth + 20, parent.width - 20)
        implicitHeight: fileNameLabel.implicitHeight + 5
        color: Appearance.colors.colPrimary
        radius: Appearance.rounding.full

        StyledText {
            id: fileNameLabel
            anchors.centerIn: parent
            property string fileName: {
                if (wallpaperSelectorRoot.targetMode === "desktop" && Config.options.background.useWallpaperEngine) {
                    const id = Config.options.background.wallpaperEngineId;
                    const parts = id.split("/");
                    return "Wallpaper Engine: " + parts[parts.length - 1];
                }
                const path = wallpaperSelectorRoot.effectivePath;
                if (path === "") {
                    if (wallpaperSelectorRoot.targetMode === "lockscreen") return "Select lockscreen wallpaper";
                    if (wallpaperSelectorRoot.targetMode === "lightmode") return "Select light mode wallpaper";
                    return "Click to select wallpaper";
                }
                const parts = path.split("/");
                let prefix = "";
                if (wallpaperSelectorRoot.targetMode === "lockscreen") prefix = "Lockscreen: ";
                else if (wallpaperSelectorRoot.targetMode === "lightmode") prefix = "Light mode: ";
                return prefix + parts[parts.length - 1];
            }
            text: fileName.length > 30 ? fileName.slice(0, 27) + "..." : fileName
            color: Appearance.colors.colOnPrimary
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
