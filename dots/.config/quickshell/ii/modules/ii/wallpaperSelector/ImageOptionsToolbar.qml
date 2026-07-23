import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

Toolbar {
    id: imageToolbar
    z: 20
    visible: modelData !== null
    
    property var modelData: wallpaperSelectorContent.moreOptionsModelData ?? null

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        property string wallhavenId: wallpaperSelectorContent.getWallhavenId(modelData?.fileUrl) ?? ""
        visible: wallhavenId?.length > 0 ?? false
        onClicked: {
            wallpaperSelectorContent.searchForSimilarImages(wallhavenId);
        }
        text: "image_search"
        StyledToolTip {
            text: Translation.tr("Search for similar images")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: !wallpaperSelectorContent.browserMode
        onClicked: {
            wallpaperSelectorContent.toggleFavourite(modelData.filePath);
        }
        text: "favorite"
        iconFill: Persistent.states.wallpaper.favourites.includes(modelData?.filePath) ?? false
        StyledToolTip {
            text: Translation.tr("Favourite this wallpaper")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        onClicked: {
            wallpaperSelectorContent.selectWallpaperPath(wallpaperSelectorContent.browserMode ? modelData.fileUrl : modelData.filePath);
        }
        text: "wallpaper"
        StyledToolTip {
            text: Translation.tr("Set as walpaper")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: wallpaperSelectorContent.browserMode
        onClicked: {
            const targetPath = Config.options.wallpapers.paths.download; 
            Quickshell.execDetached(["bash", "-c",   
                `mkdir -p '${targetPath}' && curl '${modelData.fileUrl}' -o '${targetPath}/${modelData.fileName}.png' && notify-send '${Translation.tr("Download complete")}' '${targetPath}/${modelData.fileName}.png' -a 'Shell'`  
            ])  
        }
        text: "download"
        StyledToolTip {
            text: Translation.tr("Download")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: modelData?.fileUrl.length > 0 ?? false
        onClicked: {
            Qt.openUrlExternally(modelData?.fileUrl)
        }
        text: "link"
        StyledToolTip {
            text: Translation.tr("Open file link")
        }
    }
}