pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

Singleton {
    id: root

    readonly property string helperScript: Quickshell.shellPath("scripts/smartDevices/smart_devices.py")

    property var devices: []
    readonly property int deviceCount: devices.length
    readonly property bool hasDevices: deviceCount > 0

    readonly property int onCount: {
        let count = 0;
        for (let i = 0; i < devices.length; i++) {
            if (devices[i]?.is_on) count++;
        }
        return count;
    }

    readonly property bool anyDeviceOn: onCount > 0

    readonly property var primaryDevice: {
        for (let i = 0; i < devices.length; i++) {
            if (devices[i]?.is_on) return devices[i];
        }
        return devices.length > 0 ? devices[0] : null;
    }

    readonly property string statusText: {
        if (!hasDevices) {
            return Translation.tr("No devices connected");
        }
        if (!anyDeviceOn) {
            if (deviceCount === 1) {
                return Translation.tr("Off • 1 device");
            }
            return Translation.tr("Off • %1 devices").arg(deviceCount);
        }

        const dev = primaryDevice;
        if (!dev) {
            return Translation.tr("Active");
        }

        let info = "";
        if (dev.mode === "white") {
            info = `${dev.name} • ${dev.brightness}% • ${dev.temperature ?? 4000}K`;
        } else {
            info = `${dev.name} • ${dev.brightness}% • ${dev.hue ?? 275}°`;
        }

        if (onCount > 1) {
            info += ` (+${onCount - 1})`;
        }
        return info;
    }

    readonly property string heroValue: primaryDevice && anyDeviceOn ? String(primaryDevice.brightness) : ""
    readonly property string heroUnit: primaryDevice && anyDeviceOn ? "%" : ""
    readonly property real heroLevel: primaryDevice && anyDeviceOn ? Math.max(0, Math.min(1, primaryDevice.brightness / 100)) : -1

    property bool isRefreshing: false

    function refresh(): void {
        if (isRefreshing) return;
        isRefreshing = true;
        refreshProc.running = false;
        refreshProc.running = true;
    }

    Process {
        id: refreshProc
        command: ["python3", root.helperScript, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim());
                    if (Array.isArray(data)) {
                        root.devices = data;
                    }
                } catch (e) {
                    console.warn("[SmartDevicesService] Error parsing list output:", e);
                }
            }
        }
        onExited: {
            root.isRefreshing = false;
        }
    }

    // Fast status check (reads cache file)
    function readCache(): void {
        statusProc.running = false;
        statusProc.running = true;
    }

    Process {
        id: statusProc
        command: ["python3", root.helperScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim());
                    if (Array.isArray(data) && data.length > 0) {
                        root.devices = data;
                    }
                } catch (e) {
                    // Ignore empty cache
                }
            }
        }
    }

    function updateDeviceLocal(id: string, patch: var): void {
        const next = [];
        for (let i = 0; i < root.devices.length; i++) {
            const dev = Object.assign({}, root.devices[i]);
            if (dev.id === id) {
                Object.assign(dev, patch);
            }
            next.push(dev);
        }
        root.devices = next;
    }

    function setDevicePower(id: string, onState: bool): void {
        updateDeviceLocal(id, { "is_on": onState });
        Quickshell.execDetached(["python3", root.helperScript, "set-power", id, onState ? "on" : "off"]);
    }

    function toggleDevice(id: string): void {
        const dev = root.devices.find(d => d.id === id);
        const nextState = !(dev?.is_on ?? false);
        setDevicePower(id, nextState);
    }

    function toggleAll(): void {
        const nextState = !root.anyDeviceOn;
        const next = [];
        for (let i = 0; i < root.devices.length; i++) {
            const dev = Object.assign({}, root.devices[i], { "is_on": nextState });
            next.push(dev);
        }
        root.devices = next;
        Quickshell.execDetached(["python3", root.helperScript, "set-all-power", nextState ? "on" : "off"]);
    }

    // Debounced slider controllers
    property var _pendingWhite: ({})
    property var _pendingColour: ({})

    Timer {
        id: whiteDebounceTimer
        interval: 90
        repeat: false
        onTriggered: {
            for (const id in root._pendingWhite) {
                const req = root._pendingWhite[id];
                if (req) {
                    Quickshell.execDetached([
                        "python3", root.helperScript, "set-white",
                        id, String(req.brightness), String(req.temperature)
                    ]);
                }
            }
            root._pendingWhite = ({});
        }
    }

    Timer {
        id: colourDebounceTimer
        interval: 90
        repeat: false
        onTriggered: {
            for (const id in root._pendingColour) {
                const req = root._pendingColour[id];
                if (req) {
                    Quickshell.execDetached([
                        "python3", root.helperScript, "set-colour-hsv",
                        id, String(req.hue), String(req.saturation), String(req.value)
                    ]);
                }
            }
            root._pendingColour = ({});
        }
    }

    function setDeviceWhite(id: string, brightness: int, temperature: int): void {
        updateDeviceLocal(id, {
            "is_on": true,
            "mode": "white",
            "brightness": brightness,
            "temperature": temperature
        });
        root._pendingWhite[id] = { "brightness": brightness, "temperature": temperature };
        whiteDebounceTimer.restart();
    }

    function setDeviceColourHsv(id: string, hue: int, saturation: int, value: int, hexColor: string): void {
        updateDeviceLocal(id, {
            "is_on": true,
            "mode": "colour",
            "brightness": value,
            "hue": hue,
            "saturation": saturation,
            "value": value,
            "hex_color": hexColor || root.hsvToHex(hue, saturation, value)
        });
        root._pendingColour[id] = { "hue": hue, "saturation": saturation, "value": value };
        colourDebounceTimer.restart();
    }

    function hsvToHex(h: real, s: real, v: real): string {
        const c = (v / 100) * (s / 100);
        const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
        const m = (v / 100) - c;
        let r = 0, g = 0, b = 0;
        if (h >= 0 && h < 60) { r = c; g = x; b = 0; }
        else if (h >= 60 && h < 120) { r = x; g = c; b = 0; }
        else if (h >= 120 && h < 180) { r = 0; g = c; b = x; }
        else if (h >= 180 && h < 240) { r = 0; g = x; b = c; }
        else if (h >= 240 && h < 300) { r = x; g = 0; b = c; }
        else { r = c; g = 0; b = x; }

        const rHex = Math.round((r + m) * 255).toString(16).padStart(2, '0');
        const gHex = Math.round((g + m) * 255).toString(16).padStart(2, '0');
        const bHex = Math.round((b + m) * 255).toString(16).padStart(2, '0');
        return `#${rHex}${gHex}${bHex}`;
    }

    // Periodic slow poll (every 45s) to stay in sync with external changes
    Timer {
        id: periodicPoll
        interval: 45000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        root.readCache();
        root.refresh();
    }
}
