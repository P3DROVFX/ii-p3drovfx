pragma Singleton
pragma ComponentBehavior: Bound

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

    property real transitionProgress: 1.0
    property int transitionDuration: 800
    property var _oldColors: ({})
    property var _targetColors: ({})
    property bool _hasOldColors: false

    function reapplyTheme() {
        themeFileView.reload()
    }

    function applyColors(fileContent) {
        try {
            if (!fileContent || fileContent.trim() === "") {
                console.log("[MaterialThemeLoader] applyColors: empty content, skipping")
                return;
            }
            const json = JSON.parse(fileContent)
            const skip = { "darkmode": true, "transparent": true }
            const isFirstLoad = !root._hasOldColors
            if (isFirstLoad) {
                for (const key in json) {
                    if (json.hasOwnProperty(key) && !skip[key]) {
                        Appearance.m3colors[root._toM3Key(key)] = json[key]
                    }
                }
            } else {
                root.startColorTransition(json)
            }
            
            Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
            console.log("[MaterialThemeLoader] applyColors: darkmode=", Appearance.m3colors.darkmode, "bg=", Appearance.m3colors.m3background)
        } catch(e) {
            console.log("[MaterialThemeLoader] Error parsing colors.json:", e)
        }
    }

    function _toM3Key(key) {
        const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
        return `m3${camelCaseKey}`
    }

    function startColorTransition(newJson) {
        const skip = { "m3darkmode": true, "m3transparent": true }
        const oldSnap = {}
        if (root._hasOldColors && root.transitionProgress < 1) {
            const t = root.transitionProgress
            for (const key in root._targetColors) {
                if (skip[key]) continue
                oldSnap[key] = root._interpolateColor(
                    root._oldColors[key] || root._targetColors[key],
                    root._targetColors[key], t
                )
            }
        } else {
            for (const key in newJson) {
                const m3Key = root._toM3Key(key)
                if (skip[m3Key]) continue
                oldSnap[m3Key] = Appearance.m3colors[m3Key]
            }
        }
        const targets = {}
        for (const key in newJson) {
            const m3Key = root._toM3Key(key)
            if (skip[m3Key]) continue
            targets[m3Key] = newJson[key]
        }
        root._oldColors = oldSnap
        root._targetColors = targets
        root._hasOldColors = true
        root.transitionProgress = 0
        colorTransitionAnim.stop()
        colorTransitionAnim.start()
    }

    function _interpolateColor(c1, c2, t) {
        const color1 = Qt.color(c1)
        const color2 = Qt.color(c2)
        const sat1 = color1.hslSaturation
        const sat2 = color2.hslSaturation
        if (sat1 > 0.08 && sat2 > 0.08) {
            let h1 = color1.hslHue * 360
            let h2 = color2.hslHue * 360
            let delta = h2 - h1
            if (delta > 180) delta -= 360
            if (delta < -180) delta += 360
            let h = ((h1 + delta * t) % 360 + 360) % 360 / 360
            let s = color1.hslSaturation + (color2.hslSaturation - color1.hslSaturation) * t
            let l = color1.hslLightness + (color2.hslLightness - color1.hslLightness) * t
            let a = color1.a + (color2.a - color1.a) * t
            return Qt.hsla(h, s, l, a)
        }
        return Qt.rgba(
            color1.r + (color2.r - color1.r) * t,
            color1.g + (color2.g - color1.g) * t,
            color1.b + (color2.b - color1.b) * t,
            color1.a + (color2.a - color1.a) * t
        )
    }

    function _applyInterpolatedColors(t) {
        for (const key in root._targetColors) {
            const start = root._oldColors[key]
            const end = root._targetColors[key]
            if (start !== undefined && end !== undefined) {
                Appearance.m3colors[key] = root._interpolateColor(start, end, t)
            } else if (end !== undefined) {
                Appearance.m3colors[key] = end
            }
        }
    }

    NumberAnimation {
        id: colorTransitionAnim
        target: root
        property: "transitionProgress"
        from: 0
        to: 1
        duration: root.transitionDuration
        easing.type: Easing.OutCubic
    }

    onTransitionProgressChanged: {
        if (root._hasOldColors) {
            root._applyInterpolatedColors(transitionProgress)
        }
    }

    property int retryCount: 0

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
        id: retryTimer
        interval: 150
        repeat: false
        running: false
        onTriggered: {
            if (root.retryCount < 5) {
                root.retryCount++
                console.log("[MaterialThemeLoader] Retrying file reload, attempt:", root.retryCount)
                themeFileView.reload()
            } else {
                console.log("[MaterialThemeLoader] Max retries reached, resetting path to re-establish watch")
                root.filePath = ""
                root.filePath = Directories.generatedMaterialThemePath
                root.retryCount = 0
            }
        }
    }

    Timer {
        id: delayedFileRead
        interval: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
        repeat: false
        running: false
        onTriggered: {
            root.applyColors(themeFileView.text())
        }
    }

	FileView { 
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onFileChanged: {
            console.log("[MaterialThemeLoader] onFileChanged triggered, reloading...")
            this.reload()
            delayedFileRead.start()
        }
        onLoadedChanged: {
            console.log("[MaterialThemeLoader] onLoadedChanged, loaded=", themeFileView.loaded)
            if (themeFileView.loaded) {
                root.retryCount = 0
                retryTimer.stop()
                const fileContent = themeFileView.text()
                root.applyColors(fileContent)
            }
        }
        onLoadFailed: {
            console.log("[MaterialThemeLoader] onLoadFailed, starting retry timer")
            retryTimer.start()
        }
    }

    function toggleLightDark() {
        const currentlyDark = Appearance.m3colors.darkmode;
        Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", currentlyDark ? "light" : "dark", "--noswitch"]);
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
