pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Keeps the optional ii-p3drovfx SDDM theme looking like the lock screen.
 *
 * Whenever something the login screen mirrors changes (config.json, the colour
 * files, the applied cursor, a monitor's scale, the widget colour scheme), this
 * re-runs scripts/sddm/stage_sddm.py, which writes a state.json only when it
 * differs. A root path unit installed with the theme (ii-sddm-sync@<user>.path)
 * notices it and copies everything to where the greeter can read it. Nothing
 * here needs root, and nothing runs unless the theme is installed.
 */
Singleton {
    id: root

    readonly property string themeMetadata: "/usr/share/sddm/themes/ii-p3drovfx/metadata.desktop"
    readonly property string stageScript: `${Directories.scriptPath}/sddm/stage_sddm.py`
    property bool installed: false
    readonly property bool enabled: Config.ready && root.installed && (Config.options.lock.sddmSync ?? true)

    onEnabledChanged: if (enabled) debounce.restart()

    Process {
        running: Config.ready
        command: ["test", "-f", root.themeMetadata]
        onExited: code => root.installed = code === 0
    }

    // What the stage script cannot read from a file: the cursor HyprlandEnv
    // applied, each monitor's scale, and the widget colours as the shell resolved them.
    readonly property string cursorTheme: HyprlandEnv.cursorTheme ?? ""
    readonly property int cursorSize: HyprlandEnv.cursorSize ?? 24
    readonly property string scalesJson: {
        const scales = {};
        for (const monitor of HyprlandData.monitors ?? []) {
            if (monitor?.name && monitor.scale)
                scales[monitor.name] = monitor.scale;
        }
        return JSON.stringify(scales);
    }
    readonly property string widgetColorsJson: {
        const scheme = WidgetColorScheme.schemes[WidgetColorScheme.currentScheme] ?? WidgetColorScheme.schemes["default"];
        const out = {};
        for (const field in scheme) {
            if (field === "name")
                continue;
            const c = scheme[field];
            if (c === undefined || c === null)
                continue;
            // "#rrggbb", or "#aarrggbb" for the translucent subtext colours.
            out[field] = Qt.color(c).toString();
        }
        return JSON.stringify(out);
    }
    onCursorThemeChanged: debounce.restart()
    onCursorSizeChanged: debounce.restart()
    onScalesJsonChanged: debounce.restart()
    onWidgetColorsJsonChanged: debounce.restart()

    FileView {
        path: root.enabled ? Directories.shellConfigPath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: debounce.restart()
    }
    FileView {
        path: root.enabled ? Directories.generatedMaterialThemePath : ""
        watchChanges: true
        printErrors: false
        onFileChanged: debounce.restart()
    }

    // Wallpaper switches touch config.json and colors.json in quick succession.
    Timer {
        id: debounce
        interval: 2500
        onTriggered: {
            if (!root.enabled)
                return;
            if (stage.running) {
                debounce.restart();
                return;
            }
            stage.running = true;
        }
    }

    Process {
        id: stage
        command: ["python3", "-I", root.stageScript,
            "--cursor-theme", root.cursorTheme,
            "--cursor-size", String(root.cursorSize),
            "--scales", root.scalesJson,
            "--widget-colors", root.widgetColorsJson]
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("[SddmSync]", text.trim())
        }
    }

    /// Restage now, e.g. from a settings button.
    function syncNow() {
        if (root.installed)
            stage.running = true;
    }
}
