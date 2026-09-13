pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Listening ports owned by applications the user is running.
 *
 * `scripts/portwatcher.py` already collapses `ss` output into one row per
 * (protocol, port, process). Everything a person can change from the settings
 * page — protocols, port ranges, watch and ignore lists, exposure — is applied
 * here instead, so toggling a filter is instant and never re-runs the scan.
 */
Singleton {
    id: root

    property var ports: []
    property bool available: true
    property bool refreshing: false
    property bool actionBusy: false
    property bool actionSuccess: false
    property bool truncated: false
    property string errorMessage: ""
    property string actionMessage: ""
    property real lastUpdated: 0
    property string busyPortId: ""

    property string _lastSerialized: ""
    property var _knownExposed: ({})
    property bool _hasExposedBaseline: false

    readonly property var _cfg: Config.options?.bar?.portWatcher ?? null

    readonly property bool enabled: root._cfg?.enabled ?? true
    readonly property bool autoRefresh: root._cfg?.autoRefresh ?? true
    readonly property int refreshInterval: Math.max(2000, root._cfg?.refreshInterval ?? 5000)

    // ── Filtering ────────────────────────────────────────────────────────────
    function _parseSpec(text: string): var {
        const ranges = [];
        for (const chunk of String(text ?? "").split(",")) {
            const part = chunk.trim();
            if (part.length === 0)
                continue;
            const dash = part.indexOf("-", 1);
            if (dash > 0) {
                const low = parseInt(part.substring(0, dash), 10);
                const high = parseInt(part.substring(dash + 1), 10);
                if (!isNaN(low) && !isNaN(high))
                    ranges.push([Math.min(low, high), Math.max(low, high)]);
            } else {
                const single = parseInt(part, 10);
                if (!isNaN(single))
                    ranges.push([single, single]);
            }
        }
        return ranges;
    }

    function _inSpec(ranges, port): bool {
        for (const range of ranges) {
            if (port >= range[0] && port <= range[1])
                return true;
        }
        return false;
    }

    function _nameList(text: string): var {
        const names = [];
        for (const chunk of String(text ?? "").split(",")) {
            const part = chunk.trim().toLowerCase();
            if (part.length > 0)
                names.push(part);
        }
        return names;
    }

    readonly property var visiblePorts: {
        const cfg = root._cfg;
        if (!cfg)
            return [];

        const watch = root._parseSpec(cfg.watchPorts);
        const ignore = root._parseSpec(cfg.ignorePorts);
        const ignoredNames = root._nameList(cfg.ignoreProcesses);
        const minPort = Math.max(0, cfg.minPort ?? 0);
        const maxPort = Math.max(minPort, cfg.maxPort ?? 65535);

        const kept = root.ports.filter(entry => {
            if (!entry.owned && !cfg.showSystem)
                return false;
            if (entry.protocol === "tcp" && !cfg.showTcp)
                return false;
            if (entry.protocol === "udp" && !cfg.showUdp)
                return false;
            if (cfg.exposedOnly && !entry.exposed)
                return false;
            if (!cfg.showLoopback && entry.loopback)
                return false;
            if (entry.port < minPort || entry.port > maxPort)
                return false;
            if (watch.length > 0 && !root._inSpec(watch, entry.port))
                return false;
            if (ignore.length > 0 && root._inSpec(ignore, entry.port))
                return false;
            if (ignoredNames.indexOf(String(entry.process).toLowerCase()) >= 0)
                return false;
            return true;
        });

        const mode = cfg.sortMode ?? "port";
        kept.sort((left, right) => {
            switch (mode) {
            case "process":
                return String(left.process).localeCompare(String(right.process))
                    || left.port - right.port;
            case "activity":
                return (right.connections - left.connections)
                    || (Number(right.exposed) - Number(left.exposed))
                    || (left.port - right.port);
            default:
                return (left.port - right.port)
                    || String(left.protocol).localeCompare(String(right.protocol));
            }
        });
        return kept;
    }

    readonly property int count: root.visiblePorts.length
    readonly property int exposedCount: root.visiblePorts.filter(entry => entry.exposed).length
    readonly property int connectionCount: {
        let total = 0;
        for (const entry of root.visiblePorts)
            total += Number(entry.connections ?? 0);
        return total;
    }
    readonly property int processCount: {
        const unique = {};
        for (const entry of root.visiblePorts) {
            if (entry.pid > 0)
                unique[String(entry.pid)] = true;
        }
        return Object.keys(unique).length;
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    function refresh(): void {
        if (!root.enabled || root.refreshing)
            return;
        root.refreshing = true;
        scanProcess.exec(["python3", Directories.scriptPath + "/portwatcher.py", "--scan"]);
    }

    function stopPort(entry, force): void {
        if (!entry || root.actionBusy)
            return;
        if (!(entry.canManage ?? false)
                || Number(entry.pid ?? 0) <= 0
                || String(entry.startTime ?? "").length === 0) {
            root._finishAction(false, Translation.tr("This process cannot be managed from your session."));
            return;
        }
        root.actionBusy = true;
        root.busyPortId = String(entry.id);
        root.actionMessage = "";
        actionProcess.exec([
            "python3",
            Directories.scriptPath + "/portwatcher.py",
            force ? "--force-stop-process" : "--stop-process",
            "--pid",
            String(entry.pid),
            "--start-time",
            String(entry.startTime),
            "--process-name=" + String(entry.process)
        ]);
    }

    function addressFor(entry): string {
        if (!entry)
            return "";
        const host = entry.exposed ? "0.0.0.0" : "localhost";
        return host + ":" + String(entry.port);
    }

    function urlFor(entry): string {
        if (!entry)
            return "";
        const scheme = Number(entry.port) === 443 ? "https" : "http";
        return scheme + "://localhost:" + String(entry.port);
    }

    function openInBrowser(entry): void {
        if (!entry || entry.protocol !== "tcp")
            return;
        Quickshell.execDetached(["xdg-open", root.urlFor(entry)]);
    }

    function copyAddress(entry): void {
        if (!entry)
            return;
        Quickshell.clipboardText = root.addressFor(entry);
        root._finishAction(true, Translation.tr("Copied %1").arg(root.addressFor(entry)));
    }

    function _finishAction(success, message): void {
        root.actionBusy = false;
        root.busyPortId = "";
        root.actionSuccess = success;
        root.actionMessage = String(message ?? "");
        actionMessageTimer.restart();
        if (success)
            refreshAfterAction.restart();
    }

    function _applyPorts(nextPorts): void {
        const serialized = JSON.stringify(nextPorts);
        if (serialized !== root._lastSerialized) {
            root._lastSerialized = serialized;
            root.ports = nextPorts;
        }

        const nextExposed = {};
        const appeared = [];
        for (const entry of nextPorts) {
            if (!entry.exposed || !entry.owned)
                continue;
            nextExposed[entry.id] = true;
            if (root._hasExposedBaseline && !root._knownExposed[entry.id])
                appeared.push(entry);
        }
        root._knownExposed = nextExposed;

        if (root._hasExposedBaseline
                && appeared.length > 0
                && (root._cfg?.notifyNewExposed ?? false)) {
            const first = appeared[0];
            const extra = appeared.length > 1 ? " +" + String(appeared.length - 1) : "";
            Quickshell.execDetached([
                "notify-send",
                "-a",
                "Port Watcher",
                "-i",
                "security",
                Translation.tr("New port open to the network"),
                String(first.process) + " · :" + String(first.port) + extra
            ]);
        }
        root._hasExposedBaseline = true;
    }

    onEnabledChanged: {
        if (root.enabled) {
            root.refresh();
        } else {
            scanProcess.running = false;
            root.refreshing = false;
            root.truncated = false;
            root._knownExposed = ({});
            root._applyPorts([]);
            root._hasExposedBaseline = false;
        }
    }

    Component.onCompleted: {
        if (root.enabled)
            root.refresh();
    }

    Timer {
        id: refreshTimer
        interval: root.refreshInterval
        repeat: true
        running: root.enabled && root.autoRefresh
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshAfterAction
        interval: 450
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: actionMessageTimer
        interval: 4000
        repeat: false
        onTriggered: root.actionMessage = ""
    }

    Process {
        id: scanProcess
        stdout: StdioCollector {
            id: scanOutput
        }
        onExited: exitCode => {
            root.refreshing = false;
            try {
                const payload = JSON.parse(scanOutput.text || "{}");
                root.available = payload.ok ?? false;
                root.errorMessage = String(payload.error ?? "");
                root.truncated = payload.truncated ?? false;
                if (payload.ok) {
                    root.lastUpdated = Date.now();
                    root._applyPorts(payload.ports ?? []);
                }
            } catch (error) {
                root.available = false;
                root.truncated = false;
                root.errorMessage = Translation.tr("Port scan returned invalid data.");
                console.error("[PortWatcher] Invalid scan payload:", error);
            }
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector {
            id: actionOutput
        }
        onExited: exitCode => {
            try {
                const payload = JSON.parse(actionOutput.text || "{}");
                root._finishAction(payload.ok ?? false,
                    payload.message ?? payload.error ?? Translation.tr("The action failed."));
            } catch (error) {
                root._finishAction(false, Translation.tr("The action returned invalid data."));
                console.error("[PortWatcher] Invalid action payload:", error);
            }
        }
    }
}
