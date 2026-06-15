pragma ComponentBehavior: Bound
import QtQml
import QtQuick
import Quickshell.Io
import qs.services
import "../"

NestableObject {
    id: root
    property var monitors: []
    property var profiles: []

    Component.onCompleted: {
        Qt.callLater(() => {
            fetchProc.running = true;
            reloadProfiles();
        });
    }

    function reloadProfiles() {
        profilesProc.running = true;
    }

    function updateMonitor(index, changes) {
        let m = root.monitors.slice();
        m[index] = Object.assign({}, m[index], changes);
        root.monitors = m;
    }

    Timer {
        id: debounceSaveTimer
        interval: 150
        repeat: false
        onTriggered: {
            root.doSave();
        }
    }

    function save() {
        debounceSaveTimer.restart();
    }

    function doSave() {
        if (saveProc.running) {
            // If the process is still running, try again shortly
            debounceSaveTimer.start();
            return;
        }

        if (root.monitors.length === 0)
            return;
        if (root.monitors.some(m => !m.name))
            return;

        const profile = {
            name: "__quickshell_live__",
            monitors: root.monitors.map(m => {
                return {
                    name: m.name,
                    make: "",
                    model: m.description,
                    PxW: m.width,
                    PxH: m.height,
                    Hz: m.refreshRate,
                    Scale: m.scale,
                    X: m.x,
                    Y: m.y,
                    Active: !m.disabled,
                    BitDepth: m.bitDepth || 8,
                    ColorMode: m.colorManagementPreset || "srgb",
                    SDRBrightness: m.sdrBrightness || 1.0,
                    SDRSaturation: m.sdrSaturation || 1.0,
                    VRR: m.vrr || 0,
                    Transform: m.transform || 0,
                    IsMirrored: m.mirrorOf && m.mirrorOf !== "none",
                    MirrorSource: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : ""
                };
            }),
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        };
        const jsonStr = JSON.stringify(profile, null, 2);

        saveProc.command = ["bash", "-c", "mkdir -p ~/.config/hyprmon/profiles && cat << 'EOF' > ~/.config/hyprmon/profiles/__quickshell_live__.json\n" + jsonStr + "\nEOF\nhyprmon -profile __quickshell_live__ && mkdir -p ~/.config/hypr/hyprmon_backups && mv ~/.config/hypr/*.bak.* ~/.config/hypr/hyprmon_backups/ 2>/dev/null || true; ls -t ~/.config/hypr/hyprmon_backups/*.bak.* 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null || true"];
        saveProc.running = true;
    }

    function applyMonitor(m) {
        root.save();
    }

    function applyAndSave(index) {
        root.save();
    }

    function logicalWidth(m) {
        return (m.transform === 1 || m.transform === 3) ? m.height : m.width;
    }

    function logicalHeight(m) {
        return (m.transform === 1 || m.transform === 3) ? m.width : m.height;
    }

    function applyProfile(name) {
        applyProfileProc.command = ["bash", "-c", "hyprmon -profile \"$1\" && mkdir -p ~/.config/hypr/hyprmon_backups && mv ~/.config/hypr/*.bak.* ~/.config/hypr/hyprmon_backups/ 2>/dev/null || true; ls -t ~/.config/hypr/hyprmon_backups/*.bak.* 2>/dev/null | tail -n +21 | xargs rm -f 2>/dev/null || true", "--", name];
        applyProfileProc.running = true;
    }

    function deleteProfile(name) {
        deleteProfileProc.command = ["bash", "-c", "rm -f ~/.config/hyprmon/profiles/\"$1\".json", "--", name];
        deleteProfileProc.running = true;
    }

    function saveProfile(name) {
        if (!name)
            return;
        const profile = {
            name: name,
            monitors: root.monitors.map(m => {
                return {
                    name: m.name,
                    make: "",
                    model: m.description,
                    PxW: m.width,
                    PxH: m.height,
                    Hz: m.refreshRate,
                    Scale: m.scale,
                    X: m.x,
                    Y: m.y,
                    Active: !m.disabled,
                    BitDepth: m.bitDepth || 8,
                    ColorMode: m.colorManagementPreset || "srgb",
                    SDRBrightness: m.sdrBrightness || 1.0,
                    SDRSaturation: m.sdrSaturation || 1.0,
                    VRR: m.vrr || 0,
                    Transform: m.transform || 0,
                    IsMirrored: m.mirrorOf && m.mirrorOf !== "none",
                    MirrorSource: m.mirrorOf && m.mirrorOf !== "none" ? m.mirrorOf : ""
                };
            }),
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString()
        };
        const jsonStr = JSON.stringify(profile, null, 2);
        saveProfileProc.command = ["bash", "-c", "mkdir -p ~/.config/hyprmon/profiles && cat << 'EOF' > ~/.config/hyprmon/profiles/\"$1\".json\n$2\nEOF", "--", name, jsonStr];
        saveProfileProc.running = true;
    }

    Process {
        id: fetchProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(text).map(m => ({
                                name: m.name,
                                description: m.description,
                                width: m.width,
                                height: m.height,
                                refreshRate: m.refreshRate,
                                x: m.x,
                                y: m.y,
                                scale: m.scale,
                                transform: (m.transform !== undefined && m.transform !== null) ? m.transform : 0,
                                disabled: m.disabled,
                                availableModes: m.availableModes,
                                currentMode: `${m.width}x${m.height}@${m.refreshRate.toFixed(2)}Hz`,
                                mirrorOf: m.mirrorOf || "none",
                                bitDepth: (m.currentFormat && m.currentFormat.indexOf("2101010") !== -1) ? 10 : 8,
                                colorManagementPreset: m.colorManagementPreset || "srgb",
                                sdrBrightness: m.sdrBrightness !== undefined ? m.sdrBrightness : 1.0,
                                sdrSaturation: m.sdrSaturation !== undefined ? m.sdrSaturation : 1.0,
                                vrr: m.vrr ? 1 : 0
                            }));
                } catch (e) {
                    console.log("[MonitorConfigOption] Error:", e);
                }
            }
        }
    }

    Process {
        id: applyProc
    }
    Process {
        id: saveProc
        onRunningChanged: if (!running) {
            delayFetchTimer.restart();
        }
    }
    Process {
        id: reloadProc
        command: ["hyprctl", "reload"]
    }

    Process {
        id: profilesProc
        command: ["hyprmon", "-list-profiles"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let lines = text.trim().split("\n").filter(l => l.length > 0);
                    let plist = lines.map(line => {
                        let isA = line.endsWith(" *");
                        let name = isA ? line.substring(0, line.length - 2) : line;
                        return {
                            name: name,
                            isActive: isA
                        };
                    }).filter(p => p.name !== "__quickshell_live__");
                    root.profiles = plist;
                } catch (e) {
                    console.log("[MonitorConfigOption] Error profiles:", e);
                }
            }
        }
    }

    Timer {
        id: delayFetchTimer
        interval: 200
        repeat: false
        onTriggered: {
            fetchProc.running = true;
            reloadProfiles();
        }
    }

    Process {
        id: applyProfileProc
        onRunningChanged: if (!running) {
            delayFetchTimer.restart();
        }
    }

    Process {
        id: deleteProfileProc
        onRunningChanged: if (!running) {
            reloadProfiles();
        }
    }

    function reloadFromHyprland() {
        Quickshell.execDetached(["hyprctl", "reload"]);
        // delay fetching so hyprctl reload has time to apply
        delayFetchTimer.restart();
    }

    function saveToHyprland() {
        let content = "# Generated by Quickshell/II MonitorsConfig\n";
        for (let i = 0; i < root.monitors.length; i++) {
            let m = root.monitors[i];
            if (!m) continue;
            if (m.disabled) {
                content += "monitor=" + m.name + ",disable\n";
            } else {
                let res = m.width + "x" + m.height + "@" + parseFloat(m.refreshRate).toFixed(2);
                let pos = Math.round(m.x) + "x" + Math.round(m.y);
                let scale = parseFloat(m.scale).toFixed(2);
                if (scale.endsWith(".00")) scale = parseInt(scale).toString();
                let params = [m.name, res, pos, scale];
                let line = "monitor=" + params.join(",");
                
                if (m.mirrorOf && m.mirrorOf !== "none") {
                    line += ",mirror," + m.mirrorOf;
                }
                if (m.bitDepth === 10) {
                    line += ",bitdepth,10";
                }
                if (m.transform !== undefined && m.transform !== 0) {
                    line += ",transform," + m.transform;
                }
                content += line + "\n";
            }
        }
        
        saveToHyprlandProc.command = ["bash", "-c", "cat << 'EOF' > ~/.config/hypr/monitors.conf\n" + content + "EOF\nnotify-send 'Monitors' 'Saved permanently to Hyprland!' -t 3000"];
        saveToHyprlandProc.running = true;
    }

    Process {
        id: saveToHyprlandProc
    }

    Process {
        id: saveProfileProc
        onRunningChanged: if (!running) {
            reloadProfiles();
        }
    }
}
