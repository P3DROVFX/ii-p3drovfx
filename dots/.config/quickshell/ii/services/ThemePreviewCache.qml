pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Serves every colour swatch shown in Settings from shared file reads.
 *
 * Built-in and custom theme swatches share one queued FileView instead of a
 * FileView per delegate, and the wallpaper-derived schemes come from the
 * all-schemes cache that switchwall already writes on every wallpaper change.
 * Both paths replace one subprocess per swatch, which is what made the
 * Colors & Themes page stall on open.
 */
Singleton {
    id: root

    property var values: ({})

    // Written by generate_colors_material.py --all-previews, keyed by scheme
    // name ("scheme-tonal-spot", ...) with primary/primary_container/secondary.
    property var wallpaperPreviews: ({})
    readonly property bool wallpaperPreviewsReady: Object.keys(root.wallpaperPreviews).length > 0

    function wallpaperPreview(scheme) {
        const entry = root.wallpaperPreviews[scheme];
        if (!entry)
            return null;
        return {
            primary: entry.primary || "transparent",
            secondary: entry.primary_container || "transparent",
            tertiary: entry.secondary || "transparent"
        };
    }

    function _parseWallpaperPreviews() {
        try {
            const raw = wallpaperPreviewFile.text().trim();
            root.wallpaperPreviews = raw ? (JSON.parse(raw) ?? ({})) : ({});
        } catch (e) {
            root.wallpaperPreviews = ({});
        }
    }

    Timer {
        id: wallpaperPreviewReadTimer
        interval: 50
        repeat: false
        onTriggered: root._parseWallpaperPreviews()
    }

    FileView {
        id: wallpaperPreviewFile
        path: Qt.resolvedUrl(Directories.wallpaperPreviewColorsPath)
        watchChanges: true
        printErrors: false

        // reload() does not re-emit loadedChanged once loaded, so the refresh
        // has to read the file itself after the reload settles.
        onFileChanged: {
            this.reload();
            wallpaperPreviewReadTimer.restart();
        }
        onLoadedChanged: {
            if (wallpaperPreviewFile.loaded)
                root._parseWallpaperPreviews();
        }
        onLoadFailed: root.wallpaperPreviews = ({})
    }

    property var pendingPaths: []
    property string currentPath: ""

    signal cacheChanged(string path)

    function get(path) {
        return path && root.values[path] ? root.values[path] : null;
    }

    function request(path) {
        if (!path || root.values[path])
            return;

        if (root.pendingPaths.indexOf(path) === -1)
            root.pendingPaths.push(path);

        if (root.currentPath === "")
            root.loadNext();
    }

    function loadNext() {
        if (root.currentPath !== "" || root.pendingPaths.length === 0)
            return;

        root.currentPath = root.pendingPaths.shift();
    }

    function finishCurrent() {
        root.currentPath = "";
        Qt.callLater(root.loadNext);
    }

    function release() {
        root.pendingPaths = [];
        root.currentPath = "";
        root.values = ({});
    }

    FileView {
        id: themeFile
        path: root.currentPath
        watchChanges: false
        printErrors: false

        onLoaded: {
            if (root.currentPath === "")
                return;

            const pathLoaded = root.currentPath;
            try {
                const raw = themeFile.text().trim();
                const data = raw ? JSON.parse(raw) : null;
                if (data) {
                    root.values[pathLoaded] = {
                        primary: data.primary || "transparent",
                        secondary: data.primary_container || "transparent",
                        tertiary: data.secondary || "transparent"
                    };
                    root.cacheChanged(pathLoaded);
                }
            } catch (e) {
                // A malformed optional theme must not stop the remaining queue.
            }
            root.finishCurrent();
        }

        onLoadFailed: root.finishCurrent()
    }
}
