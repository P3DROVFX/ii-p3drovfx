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

    implicitWidth: 360
    implicitHeight: 220

    StyledImage {
        id: wallpaperPreview
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: Config.options.background.wallpaperPath !== "" ? Config.options.background.wallpaperPath : `${Directories.assetsPath}/images/default_wallpaper.png`
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
                Wallpapers.openFallbackPicker(Appearance.m3colors.darkmode);
            } else {
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "wallpaperSelector", "toggle"]);
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
                const path = Config.options.background.wallpaperPath;
                if (path === "")
                    return "Click to select wallpaper";
                const parts = path.split("/");
                return parts[parts.length - 1];
            }
            text: fileName.length > 30 ? fileName.slice(0, 27) + "..." : fileName
            color: Appearance.colors.colOnPrimary
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
