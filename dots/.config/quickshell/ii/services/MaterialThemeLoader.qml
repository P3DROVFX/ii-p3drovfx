pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Automatically reloads generated material colors.
 * It is necessary to run reapplyTheme() on startup because Singletons are lazily loaded.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath

    // While the lock's look is on screen (session lock or Edit Mode's Lockscreen
    // preview) and a separate lock wallpaper is configured, the palette generated
    // for that wallpaper is applied in memory instead of rewriting colors.json.
    readonly property bool lockThemeActive: GlobalStates.lockLookActive
        && (Config.options?.background?.useSeparateLockscreenWallpaper ?? false)
        && (Config.options?.background?.lockscreenWallpaperPath ?? "") !== ""
    property var activeColorAnimations: []
    // Animating every role invalidates dozens of global bindings per frame while
    // the lock blur is moving; keep the structural/accent roles fluid and set
    // the rest atomically.
    readonly property var animatedColorRoles: ({
        m3background: true, m3onBackground: true, m3surface: true,
        m3surfaceContainerLow: true, m3surfaceContainer: true,
        m3surfaceContainerHigh: true, m3onSurface: true,
        m3onSurfaceVariant: true, m3outline: true, m3outlineVariant: true,
        m3primary: true, m3onPrimary: true, m3primaryContainer: true,
        m3onPrimaryContainer: true, m3secondary: true, m3onSecondary: true,
        m3secondaryContainer: true, m3onSecondaryContainer: true,
        m3tertiary: true, m3onTertiary: true, m3tertiaryContainer: true,
        m3onTertiaryContainer: true
    })

    // FileView.reload() only emits loadedChanged on the initial load, so a
    // reapply has to read the file itself instead of waiting for a signal that
    // never arrives once the view is loaded.
    function reapplyTheme() {
        themeFileView.reload();
        delayedFileRead.restart();
    }

    function stopColorAnimations() {
        for (const animation of activeColorAnimations) {
            animation.stop();
            animation.destroy();
        }
        activeColorAnimations = [];
    }

    // Which palette should be on screen right now.
    function applyCurrentPalette(animated) {
        const lockContent = lockFileView.text();
        if (root.lockThemeActive && lockContent && lockContent.trim() !== "") {
            root.applyColors(lockContent, animated);
            return;
        }
        root.applyColors(themeFileView.text(), animated);
    }

    function applyColors(fileContent, animated = false) {
        try {
            if (!fileContent || fileContent.trim() === "") {
                console.warn("[MaterialThemeLoader] colors.json is empty, keeping current palette")
                return;
            }

            const json = JSON.parse(fileContent)
            const skip = { "darkmode": true, "transparent": true }
            root.stopColorAnimations();
            const animate = animated && !Appearance.reducedMotion;
            const animations = [];
            for (const key in json) {
                if (!json.hasOwnProperty(key) || skip[key]) continue;
                const m3Key = root._toM3Key(key);
                if (Appearance.m3colors[m3Key] === undefined) continue;
                if (animate && root.animatedColorRoles[m3Key] === true
                        && Appearance.m3colors[m3Key] != json[key]) {
                    animations.push(Appearance.animation.elementMoveFast.colorAnimation.createObject(root, {
                        target: Appearance.m3colors,
                        property: m3Key,
                        from: Appearance.m3colors[m3Key],
                        to: json[key]
                    }));
                } else {
                    Appearance.m3colors[m3Key] = json[key]
                }
            }
            activeColorAnimations = animations;
            for (const animation of animations) animation.start();

            root.updateDarkMode(json)
        } catch (e) {
            console.warn("[MaterialThemeLoader] Error parsing colors.json:", e)
        }
    }

    function updateDarkMode(json) {
        if (typeof json.darkmode === "boolean") {
            Appearance.m3colors.darkmode = json.darkmode;
            return;
        }

        const background = json.background ?? json.surface;
        if (background !== undefined && background !== null && background !== "") {
            Appearance.m3colors.darkmode = Qt.color(background).hslLightness < 0.5;
        }
    }

    function _toM3Key(key) {
        const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
        return `m3${camelCaseKey}`
    }

    function resetFilePathNextTime() {
        resetFilePathNextWallpaperChange.enabled = true
    }

    Connections {
        id: resetFilePathNextWallpaperChange
        enabled: false
        target: Config.options.background
        function onWallpaperPathChanged() {
            root.filePath = ""
            root.filePath = Directories.generatedMaterialThemePath
            resetFilePathNextWallpaperChange.enabled = false
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyCurrentPalette(false)
        }
    }

    Connections {
        target: root
        function onLockThemeActiveChanged() {
            root.applyCurrentPalette(true);
        }
    }

    FileView {
        id: lockFileView
        path: Qt.resolvedUrl(Directories.lockscreenColorsPath)
        watchChanges: true
        onFileChanged: {
            this.reload();
            if (root.lockThemeActive) delayedFileRead.restart();
        }
        onLoadedChanged: {
            if (lockFileView.loaded && root.lockThemeActive)
                root.applyCurrentPalette(false)
        }
    }

    FileView {
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            this.reload();
            delayedFileRead.restart();
        }
        onLoadedChanged: {
            if (themeFileView.loaded)
                root.applyCurrentPalette(false)
        }
        onLoadFailed: root.resetFilePathNextTime()
    }

    function toggleLightDark() {
        const currentlyDark = Appearance.m3colors.darkmode;
        if (Config.options?.background?.useSeparateLightModeWallpaper) {
            if (currentlyDark) {
                const lightPath = Config.options.background.lightModeWallpaperPath;
                if (lightPath && lightPath !== "") {
                    Wallpapers.applyLightModeWallpaper(lightPath);
                    return;
                }
            } else {
                const darkPath = Config.options.background.wallpaperPath;
                if (darkPath && darkPath !== "") {
                    Wallpapers.apply(darkPath, true);
                    return;
                }
            }
        }
        Quickshell.execDetached(["bash", "-c", `env -u LD_LIBRARY_PATH -u PYTHONHOME -u PYTHONPATH PATH=$HOME/.local/bin:$HOME/.cargo/bin:$PATH "${Directories.wallpaperSwitchScriptPath}" --mode ${currentlyDark ? "light" : "dark"} --noswitch`]);
    }

    GlobalShortcut {
        name: "toggleLightDark"
        description: "Toggles between dark theme and light theme"

        onPressed: {
            root.toggleLightDark();
        }
    }

    IpcHandler {
        target: "theme"

        function toggleLightDark(): void {
            root.toggleLightDark();
        }

        function reapplyTheme(): void {
            root.reapplyTheme();
        }
    }
}
