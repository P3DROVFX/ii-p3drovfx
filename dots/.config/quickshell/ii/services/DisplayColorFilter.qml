pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import "displayColorFilter/DisplayColorFilterUtils.js" as FilterUtils

/**
 * Per-output SDR calibration implemented as Hyprland's final screen shader.
 *
 * DDC/CI remains the preferred hardware path where it works. This service is
 * the GPU fallback for internal panels and monitors whose DDC color controls
 * are absent or ineffective. ScreenShader arbitrates the single compositor
 * shader slot: explicit user filters temporarily take precedence over this
 * generated base shader.
 */
Singleton {
    id: root

    property var profiles: ({})
    property bool restored: false
    property int revision: 0
    property bool regenerateAgain: false
    property string errorMessage: ""

    readonly property list<string> shaderPaths: [
        `${Directories.displayColorFilterGeneratedPath}/display-color-filter-a.glsl`,
        `${Directories.displayColorFilterGeneratedPath}/display-color-filter-b.glsl`
    ]
    readonly property bool active: Object.keys(root.profiles).some(name => !FilterUtils.isIdentity(root.profiles[name]))
    readonly property bool applied: root.active && ScreenShader.baseShaderApplied
    readonly property bool suspended: root.active && ScreenShader.baseShaderSuspended

    function load(): void {
        restoreTimer.restart();
    }

    function profileForMonitor(name: string): var {
        return FilterUtils.normalizeProfile(root.profiles && root.profiles[name] ? root.profiles[name] : null);
    }

    function isMonitorNeutral(name: string): bool {
        return FilterUtils.isIdentity(root.profileForMonitor(name));
    }

    function setMonitorValue(name: string, key: string, value): void {
        if (!name || ["saturation", "contrast", "red", "green", "blue"].indexOf(key) === -1)
            return;

        const nextProfile = root.profileForMonitor(name);
        nextProfile[key] = Number(value);
        const normalized = FilterUtils.normalizeProfile(nextProfile);
        const nextProfiles = Object.assign({}, root.profiles);
        if (FilterUtils.isIdentity(normalized))
            delete nextProfiles[name];
        else
            nextProfiles[name] = normalized;
        root.profiles = nextProfiles;
        root.persist();
        root.requestRegeneration();
    }

    function setSaturation(name: string, value): void {
        root.setMonitorValue(name, "saturation", value);
    }

    function setContrast(name: string, value): void {
        root.setMonitorValue(name, "contrast", value);
    }

    function setRed(name: string, value): void {
        root.setMonitorValue(name, "red", value);
    }

    function setGreen(name: string, value): void {
        root.setMonitorValue(name, "green", value);
    }

    function setBlue(name: string, value): void {
        root.setMonitorValue(name, "blue", value);
    }

    function resetMonitor(name: string): void {
        if (!name || !root.profiles[name])
            return;
        const nextProfiles = Object.assign({}, root.profiles);
        delete nextProfiles[name];
        root.profiles = nextProfiles;
        root.persist();
        root.requestRegeneration();
    }

    function persist(): void {
        if (!root.restored || !Persistent.ready)
            return;
        Persistent.states.displayColorFilter.profilesJson = JSON.stringify(root.profiles);
    }

    function restore(): void {
        if (root.restored || !Persistent.ready)
            return;

        let stored = {};
        try {
            stored = JSON.parse(Persistent.states.displayColorFilter.profilesJson || "{}");
        } catch (error) {
            stored = {};
        }

        const normalized = {};
        for (const name in stored) {
            const profile = FilterUtils.normalizeProfile(stored[name]);
            if (!FilterUtils.isIdentity(profile))
                normalized[name] = profile;
        }
        root.profiles = normalized;
        root.restored = true;
        root.requestRegeneration();
    }

    function shaderEntries(): var {
        const monitors = Array.from(Hyprland.monitors?.values ?? []);
        const entries = [];
        for (let i = 0; i < monitors.length; i++) {
            const monitor = monitors[i];
            const profile = root.profileForMonitor(monitor.name || "");
            if (FilterUtils.isIdentity(profile))
                continue;
            entries.push({
                id: monitor.id,
                name: monitor.name,
                profile
            });
        }
        return entries;
    }

    function requestRegeneration(): void {
        if (!root.restored)
            return;
        root.revision++;
        generationTimer.restart();
    }

    function regenerate(): void {
        const entries = root.shaderEntries();
        if (entries.length === 0) {
            root.errorMessage = "";
            ScreenShader.setBaseShader(root.shaderPaths, false);
            return;
        }
        if (writerProcess.running) {
            root.regenerateAgain = true;
            return;
        }

        writerProcess.requestRevision = root.revision;
        writerProcess.shaderSource = FilterUtils.buildShader(entries);
        writerProcess.command = [
            "python3",
            Directories.displayColorFilterWriterPath,
            "--output", root.shaderPaths[0],
            "--output", root.shaderPaths[1]
        ];
        writerProcess.stdinEnabled = true;
        writerProcess.running = true;
    }

    Timer {
        id: generationTimer
        interval: 90
        repeat: false
        onTriggered: root.regenerate()
    }

    Timer {
        id: restoreTimer
        interval: 0
        repeat: false
        onTriggered: root.restore()
    }

    Process {
        id: writerProcess
        property int requestRevision: -1
        property string shaderSource: ""

        stderr: StdioCollector {
            id: writerErrors
        }

        onRunningChanged: {
            if (!running)
                return;
            write(shaderSource);
            stdinEnabled = false;
        }

        onExited: exitCode => {
            if (writerProcess.requestRevision === root.revision) {
                if (exitCode === 0) {
                    root.errorMessage = "";
                    ScreenShader.setBaseShader(root.shaderPaths, true);
                } else {
                    root.errorMessage = writerErrors.text.trim() || "shaderWriteFailed";
                }
            }
            if (root.regenerateAgain || writerProcess.requestRevision !== root.revision) {
                root.regenerateAgain = false;
                Qt.callLater(root.regenerate);
            }
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged(): void {
            restoreTimer.restart();
        }
    }

    Connections {
        target: Quickshell
        ignoreUnknownSignals: true
        function onScreensChanged(): void {
            root.requestRegeneration();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event): void {
            if (event.name === "monitoradded" || event.name === "monitoraddedv2" || event.name === "monitorremoved")
                root.requestRegeneration();
        }
    }

    Connections {
        target: HyprlandConfig
        function onReloaded(): void {
            root.requestRegeneration();
        }
    }

    Component.onCompleted: restoreTimer.restart()
}
