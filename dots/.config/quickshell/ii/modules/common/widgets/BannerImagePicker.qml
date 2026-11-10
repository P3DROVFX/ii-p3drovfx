pragma ComponentBehavior: Bound

import Quickshell.Io
import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Uses the user's XDG portal to select a sidebar banner image.
 * The helper exits on selection or cancellation.
 */
Process {
    id: root

    property string title: Translation.tr("Select banner image")
    property var nameFilters: ["Image files (*.png *.jpg *.jpeg *.webp *.bmp *.gif)"]

    readonly property string wallpaperFolder: {
        const selector = Config.options.wallpaperSelector;
        const custom = selector?.customDefaultPath ?? "";
        if (selector?.useCustomDefaultPath && custom !== "")
            return `file://${FileUtils.trimFileProtocol(custom)}`;
        return `${Directories.pictures}/Wallpapers`;
    }

    /** Ignore repeated clicks while a selection is already in progress. */
    function pick(): void {
        if (!root.running)
            root.running = true;
    }

    command: ["python3", Directories.scriptPath + "/image_picker.py",
        "--title", root.title,
        "--folder", root.wallpaperFolder,
        "--filters", JSON.stringify(root.nameFilters)]

    stdout: StdioCollector {
        onStreamFinished: {
            if (!text.trim())
                return;
            const targetPath = JSON.parse(text);
            // Clear first to reload even when the filename has not changed.
            Config.options.sidebar.bannerImage = "";
            Config.options.sidebar.bannerImage = targetPath;
            Config.options.sidebar.useCustomBanner = true;
        }
    }
}
