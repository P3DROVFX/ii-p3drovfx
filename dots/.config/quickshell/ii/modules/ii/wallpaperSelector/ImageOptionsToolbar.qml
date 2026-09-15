import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io

Toolbar {
    id: imageToolbar
    z: 20
    visible: modelData !== null
    
    property var modelData: wallpaperSelectorContent.moreOptionsModelData ?? null
    property string downloadStatus: "idle"
    property string downloadUrl: ""
    property string downloadTargetPath: ""
    property string downloadTempPath: ""
    property string downloadError: ""
    property bool applyAfterDownload: false

    readonly property bool isRemoteWallpaper: wallpaperSelectorContent.browserMode && Boolean(modelData?.fileUrl)
    readonly property bool downloadBusy: prepareDownloadDirectoryProc.running || downloadProc.running || finalizeDownloadProc.running

    onModelDataChanged: {
        if (downloadBusy) return;
        downloadStatus = "idle";
        downloadUrl = "";
        downloadTargetPath = "";
        downloadTempPath = "";
        downloadError = "";
        applyAfterDownload = false;
    }

    function sanitizeFileName(value) {
        const sanitized = String(value || "wallpaper")
            .replace(/[\u0000-\u001f\u007f]/g, "")
            .replace(/[\\/]+/g, "_")
            .replace(/[^a-zA-Z0-9._ -]/g, "_")
            .replace(/\s+/g, "_")
            .replace(/^\.+/, "")
            .replace(/_+/g, "_")
            .replace(/^[-_. ]+|[-_. ]+$/g, "")
            .slice(0, 100);
        return sanitized || "wallpaper";
    }

    function remoteFileExtension() {
        const allowed = ["jpg", "jpeg", "png", "webp", "avif", "bmp"];
        let extension = String(modelData?.file_ext || modelData?.imageData?.file_ext || "").toLowerCase().replace(/[^a-z0-9]/g, "");
        if (!allowed.includes(extension)) {
            const cleanUrl = String(modelData?.fileUrl || "").split(/[?#]/)[0];
            const match = cleanUrl.match(/\.([a-z0-9]{2,5})$/i);
            extension = match ? match[1].toLowerCase() : "jpg";
        }
        return allowed.includes(extension) ? extension : "jpg";
    }

    function localModelPath() {
        if (!modelData) return "";
        return FileUtils.trimFileProtocol(String(modelData.actualPath || modelData.filePath || ""));
    }

    function startRemoteDownload(applyAfter) {
        if (!isRemoteWallpaper || downloadBusy) return;

        const configuredDirectory = String(Config.options?.wallpapers?.paths?.download || `${Directories.pictures}/Wallpapers`);
        const targetDirectory = FileUtils.trimFileProtocol(configuredDirectory).replace(/\/+$/, "") || "/";
        const baseName = sanitizeFileName(modelData.fileName || modelData.imageData?.id || "wallpaper");
        const extension = remoteFileExtension();

        imageToolbar.downloadUrl = String(modelData.fileUrl || "");
        imageToolbar.downloadTargetPath = `${targetDirectory}/${baseName}.${extension}`;
        imageToolbar.downloadTempPath = `${imageToolbar.downloadTargetPath}.part`;
        imageToolbar.applyAfterDownload = applyAfter;
        imageToolbar.downloadError = "";
        imageToolbar.downloadStatus = "preparing";

        prepareDownloadDirectoryProc.command = ["mkdir", "-p", "--", targetDirectory];
        prepareDownloadDirectoryProc.running = true;
    }

    function finishDownload(success) {
        if (!success) {
            imageToolbar.downloadStatus = "error";
            imageToolbar.downloadError = Translation.tr("Download failed. Check the network or download folder.");
            return;
        }

        imageToolbar.downloadStatus = "done";
        Quickshell.execDetached(["notify-send", "-a", "Shell", Translation.tr("Download complete"), imageToolbar.downloadTargetPath]);
        if (imageToolbar.applyAfterDownload) {
            wallpaperSelectorContent.selectWallpaperPath(imageToolbar.downloadTargetPath);
        }
    }

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
        visible: !wallpaperSelectorContent.browserMode && !modelData?.fileIsDir
        onClicked: {
            wallpaperSelectorContent.toggleFavourite(imageToolbar.localModelPath());
        }
        text: "favorite"
        iconFill: Persistent.states.wallpaper.favourites.includes(imageToolbar.localModelPath()) ?? false
        StyledToolTip {
            text: Translation.tr("Favourite this wallpaper")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: !modelData?.fileIsDir
        onClicked: {
            if (imageToolbar.isRemoteWallpaper) {
                imageToolbar.startRemoteDownload(true);
            } else {
                wallpaperSelectorContent.selectWallpaperPath(imageToolbar.localModelPath());
            }
        }
        text: "wallpaper"
        StyledToolTip {
            text: Translation.tr("Set as wallpaper")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: !wallpaperSelectorContent.browserMode && !modelData?.fileIsDir
        onClicked: {
            wallpaperSelectorContent.moveToTrashFile(modelData);
        }
        text: "delete"
        StyledToolTip {
            text: Translation.tr("Move to trash")
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: imageToolbar.isRemoteWallpaper
        enabled: !imageToolbar.downloadBusy
        onClicked: imageToolbar.startRemoteDownload(false)
        text: imageToolbar.downloadStatus === "downloading" || imageToolbar.downloadStatus === "preparing" || imageToolbar.downloadStatus === "finalizing" ? "sync" : imageToolbar.downloadStatus === "done" ? "check" : "download"
        StyledToolTip {
            text: imageToolbar.downloadError || (imageToolbar.downloadStatus === "done" ? Translation.tr("Downloaded") : Translation.tr("Download"))
        }
    }
    IconToolbarButton {
        implicitWidth: height
        colText: Appearance.colors.colOnPrimary
        visible: Boolean(modelData?.fileUrl)
        onClicked: {
            Qt.openUrlExternally(modelData?.fileUrl)
        }
        text: "link"
        StyledToolTip {
            text: Translation.tr("Open file link")
        }
    }

    Process {
        id: prepareDownloadDirectoryProc
        command: []
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                imageToolbar.finishDownload(false);
                return;
            }

            imageToolbar.downloadStatus = "downloading";
            downloadProc.command = [
                "curl", "-fL", "--retry", "2", "--connect-timeout", "10",
                "--remove-on-error", "--output", imageToolbar.downloadTempPath,
                imageToolbar.downloadUrl
            ];
            downloadProc.running = true;
        }
    }

    Process {
        id: downloadProc
        command: []
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                imageToolbar.finishDownload(false);
                return;
            }

            imageToolbar.downloadStatus = "finalizing";
            finalizeDownloadProc.command = ["mv", "-f", "--", imageToolbar.downloadTempPath, imageToolbar.downloadTargetPath];
            finalizeDownloadProc.running = true;
        }
    }

    Process {
        id: finalizeDownloadProc
        command: []
        onExited: (exitCode, exitStatus) => imageToolbar.finishDownload(exitCode === 0)
    }
}
