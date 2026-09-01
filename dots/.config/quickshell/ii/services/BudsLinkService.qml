pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    // =========================================================================
    // Internal state
    // =========================================================================
    property bool _serviceAvailable: false
    property string _serviceVersion: ""
    property bool _serviceHeld: false
    property string _lastError: ""
    property string _lastErrorCode: ""
    property var _devicesByMac: ({})
    property bool _manualHoldRequested: false
    property bool _diagnosticsActive: false
    property bool _stopping: false
    // True once the bridge has reported a serviceStatus for the current run (available or not)
    property bool _statusKnown: false
    // One-shot service restart when BudsLink is up but never claimed a connected audio device
    property bool _recovering: false
    property bool _recoveryDone: false

    // Canonical bridge script path
    readonly property string bridgeScriptPath: Quickshell.shellPath("scripts/budslink/bridge.js")

    // =========================================================================
    // Public Properties (Implementation Plan Section 14)
    // =========================================================================
    readonly property list<string> supportedVersions: ["0.0.1"]

    function isVersionSupported(version: string): bool {
        if (!version || typeof version !== "string")
            return false;
        return root.supportedVersions.indexOf(version.trim()) !== -1;
    }

    readonly property bool bridgeRunning: bridgeProc.running
    readonly property bool serviceAvailable: root._serviceAvailable
    readonly property bool serviceCompatible: root._serviceAvailable && root._serviceVersion.length > 0 && root.isVersionSupported(root._serviceVersion)
    readonly property string serviceVersion: root._serviceVersion
    readonly property bool serviceHeld: root._serviceHeld
    readonly property string lastError: root._lastError
    readonly property string lastErrorCode: root._lastErrorCode
    readonly property var devicesByMac: root._devicesByMac
    readonly property list<var> devices: Object.values(root._devicesByMac)
    readonly property int activeDeviceCount: root.devices.length

    // Legacy RFCOMM helpers (scripts/buds/core.js) register the same BlueZ profile as BudsLink; BlueZ only
    // allows one owner, and whichever loses the race silently ends up without the device. Keep the legacy
    // path parked while BudsLink is being probed, usable, or being restarted.
    readonly property bool legacyDeferred: root.shouldBridgeRun && (!root._statusKnown || root.serviceCompatible || root._recovering)

    // =========================================================================
    // Candidate-Aware Activation Heuristics (Plan Sections 32 & 33)
    // =========================================================================
    function isAudioCandidate(device): bool {
        if (!device || !device.connected)
            return false;

        const mac = canonicalizeMac(device.address);
        if (mac.length > 0 && root._devicesByMac[mac])
            return true;

        // Generic BlueZ / Quickshell device icon metadata
        const icon = (device.icon || "").toLowerCase();
        if (icon.length > 0) {
            if (icon.includes("headset") || icon.includes("headphones") || icon.includes("audio"))
                return true;
            if (icon.includes("keyboard") || icon.includes("mouse") || icon.includes("touchpad") ||
                icon.includes("phone") || icon.includes("computer") || icon.includes("gaming") ||
                icon.includes("input") || icon.includes("controller") || icon.includes("gamepad") ||
                icon.includes("dongle"))
                return false;
        }

        // Generic BlueZ profile UUIDs (A2DP, HSP, HFP, AVRCP)
        if (device.uuids && Array.isArray(device.uuids)) {
            for (let i = 0; i < device.uuids.length; i++) {
                const u = String(device.uuids[i]).toLowerCase();
                if (u.includes("0000110a-") || u.includes("0000110b-") || u.includes("0000110d-") ||
                    u.includes("00001108-") || u.includes("00001112-") || u.includes("0000111e-") ||
                    u.includes("0000111f-") || u.includes("0000110e-")) {
                    return true;
                }
            }
        }

        // Safe fallback without name/brand keyword heuristics.
        // BudsLink D-Bus publication remains the only support confirmation.
        return false;
    }

    readonly property bool hasAudioCandidate: {
        if (!BluetoothStatus.available || !BluetoothStatus.enabled)
            return false;

        for (let d of BluetoothStatus.connectedDevices) {
            if (d && d.connected && root.isAudioCandidate(d))
                return true;
        }
        return false;
    }

    readonly property bool hasConnectedClaimedBuds: {
        if (!BluetoothStatus.available || !BluetoothStatus.enabled)
            return false;

        for (let d of BluetoothStatus.connectedDevices) {
            if (d && d.connected) {
                const mac = canonicalizeMac(d.address);
                if (mac.length > 0 && root._devicesByMac[mac])
                    return true;
            }
        }
        return false;
    }

    function pruneDisconnectedDevices(): void {
        const connectedMacs = new Set();
        if (BluetoothStatus.available && BluetoothStatus.enabled && BluetoothStatus.connectedDevices) {
            for (let d of BluetoothStatus.connectedDevices) {
                if (d && d.connected) {
                    const mac = canonicalizeMac(d.address);
                    if (mac.length > 0)
                        connectedMacs.add(mac);
                }
            }
        }

        let changed = false;
        const copy = Object.assign({}, root._devicesByMac);
        for (let mac in copy) {
            if (!connectedMacs.has(mac)) {
                delete copy[mac];
                changed = true;
            }
        }
        if (changed) {
            root._devicesByMac = copy;
        }
    }

    Connections {
        target: BluetoothStatus
        function onConnectedDevicesChanged() {
            root.pruneDisconnectedDevices();
        }
    }

    readonly property bool shouldBridgeRun: {
        if (Config.ready && Config.options && Config.options.bluetooth &&
            Config.options.bluetooth.budsLink && Config.options.bluetooth.budsLink.enabled === false) {
            return false;
        }
        return root._manualHoldRequested || root._diagnosticsActive || root.hasAudioCandidate || root.hasConnectedClaimedBuds;
    }

    onShouldBridgeRunChanged: {
        if (shouldBridgeRun) {
            idleGraceTimer.stop();
            root.ensureBridgeRunning();
        } else {
            // Start grace period before stopping bridge to avoid reconnect churn (Plan Section 32)
            idleGraceTimer.restart();
        }
    }

    // BudsLink is up and held, an audio device is connected, but BudsLink never published it: most likely its
    // profile registration lost the race at startup. Restart it once per connection so it re-registers.
    readonly property bool unclaimedCandidate: root.serviceCompatible && root.serviceHeld && root.hasAudioCandidate && !root.hasConnectedClaimedBuds

    onHasAudioCandidateChanged: {
        if (!hasAudioCandidate)
            root._recoveryDone = false;
    }

    Timer {
        id: unclaimedRecoveryTimer
        interval: 15000
        running: root.unclaimedCandidate && !root._recoveryDone && !root._recovering
        onTriggered: {
            root._recoveryDone = true;
            root._recovering = true;
            recoveryTimeoutTimer.restart();
            console.log("[BudsLinkService] BudsLink has not claimed a connected audio device; restarting the service");
            root.sendCommand({ command: "restartService" });
        }
    }

    Timer {
        id: recoveryTimeoutTimer
        interval: 20000
        onTriggered: root._recovering = false
    }

    Timer {
        id: idleGraceTimer
        interval: 8000 // 8-second grace period (5-10s range)
        onTriggered: {
            if (!root.shouldBridgeRun && root.bridgeRunning) {
                root.stopBridge();
            }
        }
    }

    Timer {
        id: diagnosticsTimeoutTimer
        interval: 6000 // 6-second bounded diagnostics probe window (Plan Section 32)
        repeat: false
        onTriggered: {
            root._diagnosticsActive = false;
        }
    }

    // =========================================================================
    // Single Persistent Bridge Process (Plan Sections 8, 9, 10, 83)
    // =========================================================================
    Timer {
        id: stopFallbackTimer
        interval: 2000 // 2-second bounded fallback for clean process shutdown
        onTriggered: {
            if (bridgeProc.running) {
                console.warn("[BudsLinkService] Bridge process did not exit within timeout, forcing termination");
                bridgeProc.running = false;
            }
            root._stopping = false;
            if (root.shouldBridgeRun) {
                bridgeRestartTimer.restart();
            }
        }
    }

    Process {
        id: bridgeProc
        command: ProcUtils.pdeath(["gjs", "-m", root.bridgeScriptPath])
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => root.handleBridgeLine(data)
        }

        stderr: SplitParser {
            onRead: data => console.warn("[BudsLinkBridge]", data)
        }

        onExited: (exitCode, exitStatus) => {
            stopFallbackTimer.stop();
            root._stopping = false;
            root._serviceAvailable = false;
            root._serviceHeld = false;
            root._serviceVersion = "";
            root._devicesByMac = ({});

            recoveryTimeoutTimer.stop();
            root._recovering = false;

            if (root.shouldBridgeRun) {
                if (exitCode !== 0) {
                    root._lastErrorCode = "bridgeFailed";
                    root._lastError = `BudsLink bridge exited with code ${exitCode}`;
                    root._statusKnown = true;
                }
                bridgeRestartTimer.restart();
            }
        }
    }

    Timer {
        id: bridgeRestartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.shouldBridgeRun && !bridgeProc.running && !root._stopping) {
                root.ensureBridgeRunning();
            }
        }
    }

    function ensureBridgeRunning(): void {
        if (!bridgeProc.running && !root._stopping) {
            bridgeRestartTimer.stop();
            // A bridge that keeps crashing must not park the legacy path forever
            root._statusKnown = root._lastErrorCode === "bridgeFailed";
            bridgeProc.running = true;
        }
    }

    function stopBridge(): void {
        root._diagnosticsActive = false;
        diagnosticsTimeoutTimer.stop();
        if (bridgeProc.running && !root._stopping) {
            root._stopping = true;
            stopFallbackTimer.restart();
            sendCommand({ command: "shutdown" });
        }
    }

    function sendCommand(obj): void {
        // Never write when bridge process is not running
        if (!bridgeProc.running) {
            return;
        }

        try {
            const line = JSON.stringify(obj) + "\n";
            bridgeProc.write(line);
        } catch (e) {
            console.warn("[BudsLinkService] Write error:", e.message);
        }
    }

    // =========================================================================
    // Bridge Protocol JSONL Parser (Plan Section 9)
    // =========================================================================
    function handleBridgeLine(rawLine: string): void {
        const trimmed = rawLine.trim();
        if (trimmed.length === 0)
            return;

        let event;
        try {
            event = JSON.parse(trimmed);
        } catch (e) {
            root._lastErrorCode = "invalidJson";
            root._lastError = `Failed to parse bridge JSON: ${e.message}`;
            return;
        }

        if (!event || typeof event !== "object")
            return;

        switch (event.type) {
            case "bridgeReady":
                if (root.shouldBridgeRun) {
                    root.sendCommand({ command: "hold" });
                    root.sendCommand({ command: "enumerate" });
                }
                break;

            case "serviceStatus":
                root._serviceAvailable = Boolean(event.available);
                root._serviceVersion = event.version || "";
                root._serviceHeld = Boolean(event.held);
                root._statusKnown = true;
                if (root._recovering && root._serviceAvailable && root._serviceHeld) {
                    recoveryTimeoutTimer.stop();
                    root._recovering = false;
                }

                if (!root._serviceAvailable) {
                    root._devicesByMac = ({});
                } else if (root._serviceVersion.length > 0 && !root.serviceCompatible) {
                    root._lastErrorCode = "serviceVersionUnsupported";
                    root._lastError = `Unsupported BudsLink version: ${root._serviceVersion}`;
                }
                break;

            case "deviceAdded":
                break;

            case "deviceSnapshot":
                if (event.path) {
                    const mac = event.mac || extractMacFromPath(event.path);
                    if (mac.length > 0) {
                        const copy = Object.assign({}, root._devicesByMac);
                        copy[mac] = {
                            path: event.path,
                            mac: mac,
                            alias: event.alias || "",
                            config: (event.config && typeof event.config === "object") ? event.config : ({}),
                            state: (event.state && typeof event.state === "object") ? event.state : ({}),
                            lastUpdated: Date.now()
                        };
                        root._devicesByMac = copy;
                    }
                }
                break;

            case "deviceAlias":
                if (event.path) {
                    const mac = extractMacFromPath(event.path);
                    if (mac.length > 0 && root._devicesByMac[mac]) {
                        const copy = Object.assign({}, root._devicesByMac);
                        const prev = copy[mac];
                        copy[mac] = {
                            path: prev.path,
                            mac: prev.mac,
                            alias: event.alias || "",
                            config: prev.config,
                            state: prev.state,
                            lastUpdated: Date.now()
                        };
                        root._devicesByMac = copy;
                    }
                }
                break;

            case "deviceState":
                if (event.path) {
                    const mac = extractMacFromPath(event.path);
                    if (mac.length > 0 && root._devicesByMac[mac]) {
                        const copy = Object.assign({}, root._devicesByMac);
                        const prev = copy[mac];
                        copy[mac] = {
                            path: prev.path,
                            mac: prev.mac,
                            alias: prev.alias,
                            config: prev.config,
                            // Replace state atomically without merging removed keys
                            state: (event.state && typeof event.state === "object") ? event.state : prev.state,
                            lastUpdated: Date.now()
                        };
                        root._devicesByMac = copy;
                    }
                }
                break;

            case "deviceConfig":
                if (event.path) {
                    const mac = extractMacFromPath(event.path);
                    if (mac.length > 0 && root._devicesByMac[mac]) {
                        const copy = Object.assign({}, root._devicesByMac);
                        const prev = copy[mac];
                        copy[mac] = {
                            path: prev.path,
                            mac: prev.mac,
                            alias: prev.alias,
                            // Replace config atomically without merging removed keys
                            config: (event.config && typeof event.config === "object") ? event.config : prev.config,
                            state: prev.state,
                            lastUpdated: Date.now()
                        };
                        root._devicesByMac = copy;
                    }
                }
                break;

            case "deviceRemoved":
                if (event.path) {
                    const mac = extractMacFromPath(event.path);
                    if (mac.length > 0 && root._devicesByMac[mac]) {
                        const copy = Object.assign({}, root._devicesByMac);
                        delete copy[mac];
                        root._devicesByMac = copy;
                    }
                }
                break;

            case "error":
                root._lastErrorCode = event.code || "unknown";
                root._lastError = event.message || "An error occurred in BudsLink bridge";
                if (event.code === "restartSkipped" || event.code === "restartFailed") {
                    recoveryTimeoutTimer.stop();
                    root._recovering = false;
                }
                break;

            default:
                break;
        }
    }

    // =========================================================================
    // Public API Helpers (Plan Sections 14, 15, 16)
    // =========================================================================
    function canonicalizeMac(mac): string {
        if (!mac || typeof mac !== "string")
            return "";
        const trimmed = mac.trim().replace(/[-_]/g, ":").toUpperCase();
        const match = /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(trimmed);
        return match ? trimmed : "";
    }

    function extractMacFromPath(path: string): string {
        if (!path || typeof path !== "string")
            return "";
        const match = path.match(/dev_([0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2}_[0-9A-Fa-f]{2})/);
        if (match) {
            return match[1].replace(/_/g, ":").toUpperCase();
        }
        return "";
    }

    function resolveMac(deviceOrMac): string {
        if (!deviceOrMac)
            return "";
        if (typeof deviceOrMac === "string")
            return canonicalizeMac(deviceOrMac);
        if (typeof deviceOrMac === "object") {
            if (deviceOrMac.address)
                return canonicalizeMac(deviceOrMac.address);
            if (deviceOrMac.mac)
                return canonicalizeMac(deviceOrMac.mac);
        }
        return "";
    }

    function hasDevice(device): bool {
        const mac = resolveMac(device);
        return mac.length > 0 && Boolean(root._devicesByMac[mac]);
    }

    function hasMac(mac): bool {
        const canonical = canonicalizeMac(mac);
        return canonical.length > 0 && Boolean(root._devicesByMac[canonical]);
    }

    function infoForDevice(device): var {
        const mac = resolveMac(device);
        return (mac.length > 0 && root._devicesByMac[mac]) ? root._devicesByMac[mac] : null;
    }

    function infoForMac(mac): var {
        const canonical = canonicalizeMac(mac);
        return (canonical.length > 0 && root._devicesByMac[canonical]) ? root._devicesByMac[canonical] : null;
    }

    function batteryInfo(device): var {
        const info = infoForDevice(device);
        if (!info || !info.state)
            return null;
        const state = info.state;
        const config = info.config || ({});
        return {
            available: true,
            computedBatteryLevel: state.computedBatteryLevel !== undefined ? state.computedBatteryLevel : null,
            battery1Level: state.battery1Level !== undefined ? state.battery1Level : null,
            battery1Status: state.battery1Status || null,
            battery1Icon: config.battery1Icon || null,
            battery2Level: state.battery2Level !== undefined ? state.battery2Level : null,
            battery2Status: state.battery2Status || null,
            battery2Icon: config.battery2Icon || null,
            battery3Level: state.battery3Level !== undefined ? state.battery3Level : null,
            battery3Status: state.battery3Status || null,
            battery3Icon: config.battery3Icon || null,
            rawState: state,
            rawConfig: config
        };
    }

    function controlsForDevice(device): var {
        const info = infoForDevice(device);
        if (!info)
            return null;
        return {
            alias: info.alias || "",
            config: info.config || ({}),
            state: info.state || ({})
        };
    }

    function sendAction(deviceOrMac, action: string, value: var): void {
        if (!root.serviceCompatible) {
            console.warn("[BudsLinkService] Cannot send action, service is not compatible or unavailable");
            return;
        }

        const info = infoForDevice(deviceOrMac);
        if (!info || !info.path) {
            console.warn("[BudsLinkService] Cannot send action, unknown device:", deviceOrMac);
            return;
        }

        sendCommand({
            command: "action",
            path: info.path,
            action: action,
            value: (value !== undefined) ? value : 0
        });
    }

    function openDeviceSettings(deviceOrMac): void {
        sendAction(deviceOrMac, "settingsButtonClicked", 0);
    }

    function requestHold(): void {
        root._manualHoldRequested = true;
        ensureBridgeRunning();
        sendCommand({ command: "hold" });
    }

    function release(): void {
        root._manualHoldRequested = false;
        root._diagnosticsActive = false;
        diagnosticsTimeoutTimer.stop();
        sendCommand({ command: "release" });
    }

    function refresh(): void {
        if (bridgeProc.running) {
            sendCommand({ command: "enumerate" });
        } else {
            // Bounded temporary diagnostics activation (Plan Section 32)
            root._diagnosticsActive = true;
            diagnosticsTimeoutTimer.restart();
            ensureBridgeRunning();
        }
    }
}
