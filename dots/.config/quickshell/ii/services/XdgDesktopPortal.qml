pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The user's XDG Desktop Portal backend preference for the current Hyprland session.
 *
 * xdg-desktop-portal chooses a backend from `hyprland-portals.conf`. Hyprland stays first in
 * the default chain for screen sharing and global shortcuts; the selected desktop backend then
 * supplies file chooser and other desktop-facing requests. This service edits only the two
 * relevant [preferred] entries and leaves any other per-interface choices untouched.
 */
Singleton {
    id: root

    readonly property string configPath: `${Directories.config}/xdg-desktop-portal/hyprland-portals.conf`
    readonly property string configDirectory: FileUtils.parentDirectory(root.configPath)
    readonly property string fileChooserKey: "org.freedesktop.impl.portal.FileChooser"

    property bool configReady: false
    property bool probeReady: false
    property bool writing: false
    property bool restarting: false
    property string selectedBackend: ""
    property string configText: ""
    property string statusMessage: ""
    property string errorMessage: ""
    /// [{ id, fileChooser }] read from the installed .portal declarations.
    property var backends: []
    property string _pendingText: ""
    property real _startedAt: Date.now()

    readonly property bool ready: root.configReady && root.probeReady
    readonly property var portalOptions: {
        const options = [{
            "displayName": Translation.tr("System default"), "value": "", "icon": "auto_awesome"
        }];
        for (const backend of root.backends) {
            if (!backend.fileChooser)
                continue;
            options.push({
                "displayName": root.backendLabel(backend.id), "value": backend.id,
                "icon": root.backendIcon(backend.id)
            });
        }
        if (root.selectedBackend !== ""
                && !options.some(option => option.value === root.selectedBackend)) {
            options.push({
                "displayName": Translation.tr("%1 — unavailable").arg(root.backendLabel(root.selectedBackend)),
                "value": root.selectedBackend, "icon": "warning"
            });
        }
        return options;
    }

    function backendLabel(id: string): string {
        const names = {
            "gtk": Translation.tr("GTK"),
            "kde": Translation.tr("KDE"),
            "gnome": Translation.tr("GNOME")
        };
        return names[id] ?? id;
    }

    function backendIcon(id: string): string {
        const icons = {
            "gtk": "folder_open",
            "kde": "desktop_windows",
            "gnome": "apps"
        };
        return icons[id] ?? "extension";
    }

    function backendExists(id: string): bool {
        return root.backends.some(backend => backend.id === id && backend.fileChooser);
    }

    function hasHyprland(): bool {
        return root.backends.some(backend => backend.id === "hyprland");
    }

    function readPreferred(text: string): var {
        const values = {};
        let inPreferred = false;
        for (const rawLine of String(text ?? "").split("\n")) {
            const line = rawLine.replace(/\r$/, "");
            const header = line.match(/^\s*\[([^\]]+)\]\s*$/);
            if (header) {
                inPreferred = header[1].toLowerCase() === "preferred";
                continue;
            }
            if (!inPreferred || /^\s*[#;]/.test(line))
                continue;
            const divider = line.indexOf("=");
            if (divider < 0)
                continue;
            const key = line.slice(0, divider).trim();
            if (key !== "")
                values[key] = line.slice(divider + 1).trim();
        }
        return values;
    }

    function selectionFrom(preferred: var): string {
        const forced = String(preferred[root.fileChooserKey] ?? "").trim();
        if (forced !== "")
            return forced;
        const chain = String(preferred.default ?? "").split(";").map(value => value.trim())
            .filter(value => value !== "");
        for (let index = chain.length - 1; index >= 0; index--) {
            if (chain[index] !== "hyprland")
                return chain[index];
        }
        return "";
    }

    function applyRead(text: string) {
        root.configText = String(text ?? "");
        root.selectedBackend = root.selectionFrom(root.readPreferred(root.configText));
        root.configReady = true;
        if (!root.writing)
            root.errorMessage = "";
    }

    function appendMissing(out: var, values: var, written: var) {
        for (const key of Object.keys(values)) {
            if (written[key] || values[key] === null)
                continue;
            out.push(`${key} = ${values[key]}`);
            written[key] = true;
        }
    }

    function writePreferred(values: var): string {
        const out = [];
        const written = {};
        let inPreferred = false;
        let sawPreferred = false;
        for (const rawLine of root.configText.split("\n")) {
            const line = rawLine.replace(/\r$/, "");
            const header = line.match(/^\s*\[([^\]]+)\]\s*$/);
            if (header) {
                if (inPreferred)
                    root.appendMissing(out, values, written);
                inPreferred = header[1].toLowerCase() === "preferred";
                sawPreferred = sawPreferred || inPreferred;
                out.push(line);
                continue;
            }
            if (inPreferred && !/^\s*[#;]/.test(line)) {
                const divider = line.indexOf("=");
                const key = divider < 0 ? "" : line.slice(0, divider).trim();
                if (key !== "" && values[key] !== undefined) {
                    if (!written[key] && values[key] !== null) {
                        out.push(`${key} = ${values[key]}`);
                        written[key] = true;
                    }
                    continue;
                }
            }
            out.push(line);
        }
        if (inPreferred)
            root.appendMissing(out, values, written);

        const hasNewPreference = Object.keys(values).some(key => values[key] !== null);
        if (!sawPreferred && hasNewPreference) {
            if (out.length > 0 && out[out.length - 1] !== "")
                out.push("");
            out.push("[preferred]");
            root.appendMissing(out, values, written);
        }
        return out.join("\n").replace(/\n+$/, "") + "\n";
    }

    function defaultChain(backend: string): string {
        return root.hasHyprland() && backend !== "hyprland" ? `hyprland;${backend}` : backend;
    }

    function setBackend(id: string): bool {
        const backend = String(id ?? "").trim();
        if ((backend !== "" && !root.backendExists(backend)) || root.writing || root.restarting)
            return false;
        const values = {
            "default": backend === "" ? null : root.defaultChain(backend),
            "org.freedesktop.impl.portal.FileChooser": backend === "" ? null : backend
        };
        const nextText = root.writePreferred(values);
        if (nextText === root.configText)
            return false;
        root.errorMessage = "";
        root.statusMessage = "";
        root.writing = true;
        root._pendingText = nextText;
        makeDirectory.command = ["mkdir", "-p", root.configDirectory];
        makeDirectory.running = true;
        return true;
    }

    function refresh() {
        portalFile.reload();
        if (!portalProbe.running) {
            root.probeReady = false;
            portalProbe.running = true;
        }
    }

    Component.onCompleted: root.refresh()

    Timer {
        id: loadRetry
        interval: 750
        repeat: false
        onTriggered: portalFile.reload()
    }

    FileView {
        id: portalFile
        path: root.configPath
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onLoaded: root.applyRead(portalFile.text())
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                root.errorMessage = Translation.tr("Could not read the desktop portal configuration.");
                root.configReady = true;
                return;
            }
            if (Date.now() - root._startedAt < 2000 || root.writing) {
                loadRetry.restart();
                return;
            }
            // Missing is a valid system-default state. Never create a config until the user picks one.
            root.applyRead("");
        }
        onSaved: {
            root.configText = root._pendingText;
            root.selectedBackend = root.selectionFrom(root.readPreferred(root.configText));
            root.writing = false;
            root.restarting = true;
            restartPortal.running = true;
        }
        onSaveFailed: error => {
            root.writing = false;
            root.errorMessage = Translation.tr("Could not save the desktop portal configuration.");
        }
    }

    Process {
        id: makeDirectory

        onExited: exitCode => {
            if (exitCode !== 0) {
                root.writing = false;
                root.errorMessage = Translation.tr("Could not create the desktop portal configuration directory.");
                return;
            }
            portalFile.setText(root._pendingText);
        }
    }

    Process {
        id: restartPortal
        command: ["systemctl", "--user", "restart", "xdg-desktop-portal.service"]

        onExited: exitCode => {
            root.restarting = false;
            if (exitCode !== 0) {
                root.errorMessage = Translation.tr("The portal preference was saved, but the portal could not be restarted.");
                return;
            }
            root.statusMessage = Translation.tr("Desktop portal updated. New dialogs use it now.");
        }
    }

    Process {
        id: portalProbe
        command: ["bash", "-c",
            "for portal in /usr/share/xdg-desktop-portal/portals/*.portal; do "
            + "[ -f \"$portal\" ] || continue; id=${portal##*/}; id=${id%.portal}; "
            + "grep -q '^Interfaces=.*org\\.freedesktop\\.impl\\.portal\\.FileChooser' \"$portal\" "
            + "&& chooser=1 || chooser=0; printf '%s\\t%s\\n' \"$id\" \"$chooser\"; done"]

        stdout: StdioCollector {
            id: portalProbeOutput
        }

        onExited: exitCode => {
            const found = [];
            if (exitCode === 0) {
                const seen = {};
                for (const line of String(portalProbeOutput.text ?? "").split("\n")) {
                    const parts = line.split("\t");
                    const id = String(parts[0] ?? "").trim();
                    if (!/^[A-Za-z0-9_-]+$/.test(id) || seen[id])
                        continue;
                    seen[id] = true;
                    found.push({ "id": id, "fileChooser": parts[1] === "1" });
                }
            }
            root.backends = found;
            root.probeReady = true;
            if (exitCode !== 0)
                root.errorMessage = Translation.tr("Could not find installed desktop portal backends.");
        }
    }
}
