import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item {
    id: bannerSelectorRoot
    property string text: ""
    property string placeholderText: "Click to select banner image"
    property var nameFilters: ["Image files (*.png *.jpg *.jpeg *.webp *.bmp *.gif)"]

    implicitWidth: 360
    implicitHeight: 220

    readonly property string defaultPreviewPath: `${Directories.assetsPath}/images/default_wallpaper.png`

    readonly property string rawSource: Config.options.sidebar.bannerImage !== "" ? Config.options.sidebar.bannerImage : bannerSelectorRoot.defaultPreviewPath
    readonly property string cleanSource: {
        let p = bannerSelectorRoot.rawSource;
        if (!p) return "";
        const qIdx = p.indexOf("?");
        if (qIdx !== -1) p = p.substring(0, qIdx);
        return p.startsWith("file://") ? p : ("file://" + p);
    }
    readonly property bool isAnimated: {
        const lower = bannerSelectorRoot.cleanSource.toLowerCase();
        return lower.includes(".gif") || lower.includes(".webp");
    }
    readonly property bool shouldPlay: GlobalStates.settingsOpen && isAnimated

    // Open where wallpapers live, honoring the wallpaper selector's custom folder when set.
    readonly property string wallpaperFolder: {
        const selector = Config.options.wallpaperSelector;
        const custom = selector?.customDefaultPath ?? "";
        if (selector?.useCustomDefaultPath && custom !== "")
            return `file://${FileUtils.trimFileProtocol(custom)}`;
        return `${Directories.pictures}/Wallpapers`;
    }

    // Static Image preview
    StyledImage {
        id: bannerPreview
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: !bannerSelectorRoot.isAnimated ? bannerSelectorRoot.cleanSource : ""
        visible: !bannerSelectorRoot.isAnimated && status !== Image.Error
        cache: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bannerPreview.width
                height: bannerPreview.height
                radius: Appearance.rounding.normal
            }
        }
    }

    // Animated GIF preview
    AnimatedImage {
        id: bannerPreviewAnimated
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        source: bannerSelectorRoot.isAnimated ? bannerSelectorRoot.cleanSource : ""
        playing: bannerSelectorRoot.shouldPlay
        paused: !bannerSelectorRoot.shouldPlay
        visible: bannerSelectorRoot.isAnimated && status === Image.Ready
        cache: false
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bannerPreviewAnimated.width
                height: bannerPreviewAnimated.height
                radius: Appearance.rounding.normal
            }
        }
    }

    StyledImage {
        id: bannerPreviewFallback
        anchors.fill: parent
        visible: (!bannerSelectorRoot.isAnimated && bannerPreview.status === Image.Error) || (bannerSelectorRoot.isAnimated && bannerPreviewAnimated.status === Image.Error)
        source: bannerSelectorRoot.defaultPreviewPath
        fillMode: Image.PreserveAspectCrop
        cache: true
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bannerPreviewFallback.width
                height: bannerPreviewFallback.height
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
            fileDialog.currentFolder = bannerSelectorRoot.wallpaperFolder;
            fileDialog.open();
        }
    }

    FileDialog {
        id: fileDialog
        title: bannerSelectorRoot.text !== "" ? bannerSelectorRoot.text : "Select banner image"
        nameFilters: bannerSelectorRoot.nameFilters
        fileMode: FileDialog.OpenFile
        onAccepted: {
            const path = selectedFile.toString().replace(/^file:\/\//, "");
            Config.options.sidebar.bannerImage = path;
        }
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
                const path = Config.options.sidebar.bannerImage;
                if (path === "") return bannerSelectorRoot.placeholderText;
                const parts = path.split("/");
                return parts[parts.length - 1];
            }
            text: fileName.length > 30 ? fileName.slice(0, 27) + "..." : fileName
            color: Appearance.colors.colOnPrimary
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
