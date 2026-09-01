pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.modules.common
import qs.services

Singleton {
    id: root

    // Dictionary to store active modes by device MAC address
    property var deviceModes: ({})
    // Supported noise-control mode keys by MAC (reported by core.js "get"); default is the classic trio
    property var deviceSupportedModes: ({})
    readonly property list<string> defaultSupportedModes: ["off", "transparency", "anc"]

    function isSuppressed(deviceOrMac) {
        // BudsLink and core.js compete for the same BlueZ RFCOMM profile: stay out of the way while
        // BudsLink is still being probed or is known to be usable, or its registration loses the race.
        if (BudsLinkService.legacyDeferred)
            return true;
        return BudsLinkService.hasDevice(deviceOrMac) || BudsLinkService.hasMac(deviceOrMac);
    }

    readonly property var activeDevice: {
        for (let d of BluetoothStatus.connectedDevices) {
            if (isHeadsetSupported(d) && !isSuppressed(d)) {
                return d;
            }
        }
        return null;
    }

    property bool isConnected: activeDevice !== null
    property string targetDeviceName: activeDevice ? activeDevice.name : "None"
    property string macAddress: activeDevice ? activeDevice.address : ""

    // Backward compatibility property for unified Quick Toggle bindings
    readonly property string currentMode: {
        let dummy = deviceModes; // Force dependency tracking on the deviceModes object
        return activeDevice ? getModeForMac(activeDevice.address) : "Normal";
    }

    readonly property string budsScriptPath: Quickshell.shellPath("scripts/buds/core.js")

    function isHeadsetSupported(device) {
        if (!device) return false;
        let name = (device.name || "").toLowerCase();
        
        // Exclude Soundcore Life Q30/Anker since it is handled by SoundcoreService
        if (name.includes("q30") || name.includes("soundcore")) return false;

        return name.includes("buds") ||
               name.includes("ear") ||
               name.includes("airpods") ||
               name.includes("beats") ||
               name.includes("linkbuds") ||
               name.includes("wf-") ||
               name.includes("wh-") ||
               name.includes("wi-");
    }

    function getModeForMac(mac) {
        return deviceModes[mac] || "Normal";
    }

    function getSupportedModesForMac(mac) {
        return deviceSupportedModes[mac] || defaultSupportedModes;
    }

    function updateSupportedModes(mac, modes) {
        let copy = Object.assign({}, deviceSupportedModes);
        copy[mac] = modes;
        deviceSupportedModes = copy;
    }

    function updateDeviceMode(mac, mode) {
        let copy = Object.assign({}, deviceModes);
        copy[mac] = mode;
        deviceModes = copy; // Trigger QML property updates
    }

    function setMode(mac, mode) {
        // Support single argument calls like setMode(mode) by defaulting to activeDevice.address
        if (arguments.length === 1 || mode === undefined) {
            mode = mac;
            mac = activeDevice ? activeDevice.address : "";
        }

        if (!mac || isSuppressed(mac))
            return;

        Quickshell.execDetached(["gjs", "-m", budsScriptPath, "set", mac, mode.toLowerCase()]);

        // Optimistic update for immediate visual feedback
        updateDeviceMode(mac, mode);
    }

    function refreshMode(mac) {
        if (mac === undefined) {
            refreshAllConnected();
            return;
        }

        if (isSuppressed(mac))
            return;

        // Spawn a lightweight, isolated process to poll the specific headset
        processComponent.createObject(root, {
            "mac": mac
        });
    }

    function refreshAllConnected() {
        for (let d of BluetoothStatus.connectedDevices) {
            if (isHeadsetSupported(d) && !isSuppressed(d)) {
                refreshMode(d.address);
            }
        }
    }

    // Isolated dynamic process component to handle concurrent polling without race conditions
    Component {
        id: processComponent
        Process {
            id: proc
            property string mac: ""

            command: ["gjs", "-m", budsScriptPath, "get", mac]
            running: true

            stdout: StdioCollector {
                onStreamFinished: {
                    const lines = text.split("\n").map(l => l.trim()).filter(l => l.length > 0);
                    const modesLine = lines.find(l => l.startsWith("MODES:"));
                    const modeLine = lines.find(l => !l.startsWith("MODES:"));
                    if (modesLine) {
                        const modes = modesLine.slice(6).split(",").map(m => m.trim()).filter(m => m.length > 0);
                        if (modes.length > 0)
                            root.updateSupportedModes(proc.mac, modes);
                    }
                    if (modeLine) {
                        root.updateDeviceMode(proc.mac, modeLine);
                    }
                    proc.destroy(); // Auto-free memory upon completion
                }
            }
        }
    }

    onIsConnectedChanged: {
        if (isConnected) {
            refreshAllConnected();
        }
    }

    // BudsLink turned out to be unavailable (or was disabled): take over the connected earbuds now
    readonly property bool legacyDeferred: BudsLinkService.legacyDeferred
    onLegacyDeferredChanged: {
        if (!legacyDeferred)
            refreshAllConnected();
    }
}
