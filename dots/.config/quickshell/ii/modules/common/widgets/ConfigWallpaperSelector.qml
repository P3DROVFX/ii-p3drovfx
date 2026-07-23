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
    property string targetMode: "desktop" // "desktop" or "lockscreen"

    implicitWidth: 360
    implicitHeight: 220

    readonly property string effectivePath: {
        if (targetMode === "lockscreen") {
            const lockPath = Config.options.background.lockscreenWallpaperPath;
            return (lockPath && lockPath !== "") ? lockPath : Config.options.background.wallpaperPath;
        }
        return Config.options.background.wallpaperPath;
    }

    StyledImage {
        id: wallpaperPreview
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: {
            if (targetMode === "desktop" && Config.options.background.useWallpaperEngine) {
                return "file:///tmp/wpe_screenshot.png?t=" + Config.options.background.wallpaperEngineId;
            }
            return wallpaperSelectorRoot.effectivePath !== "" ? wallpaperSelectorRoot.effectivePath : `${Directories.assetsPath}/images/default_wallpaper.png`
        }
        cache: false
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: 360
                height: 200
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
                const action = wallpaperSelectorRoot.targetMode === "lockscreen" ? "toggleLockscreen" : "toggle";
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
                if (path === "")
                    return wallpaperSelectorRoot.targetMode === "lockscreen" ? "Select lockscreen wallpaper" : "Click to select wallpaper";
                const parts = path.split("/");
                const prefix = wallpaperSelectorRoot.targetMode === "lockscreen" ? "Lockscreen: " : "";
                return prefix + parts[parts.length - 1];
            }
            text: fileName.length > 30 ? fileName.slice(0, 27) + "..." : fileName
            color: Appearance.colors.colOnPrimary
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
