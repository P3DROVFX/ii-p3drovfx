pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: Bluetooth.defaultAdapter?.devices.values.find(device => device.connected) ?? null
    readonly property int activeDeviceCount: Bluetooth.defaultAdapter?.devices.values.filter(device => device.connected).length ?? 0
    readonly property bool connected: Bluetooth.devices.values.some(d => d.connected)

    // === Connection tracking ===
    signal deviceConnected(BluetoothDevice device)
    signal deviceDisconnected(BluetoothDevice device)

    onDeviceConnected: device => SoundService.playEvent("devices", "device-added")
    onDeviceDisconnected: device => SoundService.playEvent("devices", "device-removed")

    property var _previousConnectedAddresses: []
    property bool _initialized: false

    Timer {
        interval: 500
        running: root.enabled
        repeat: true
        onTriggered: root._checkConnectionChanges()
    }

    function _checkConnectionChanges() {
        const currentConnected = Bluetooth.devices.values.filter(d => d.connected);
        const currentAddresses = currentConnected.map(d => d.address);

        // Skip initial snapshot to avoid false positives on startup
        if (!_initialized) {
            _previousConnectedAddresses = currentAddresses;
            _initialized = true;
            return;
        }

        // Find newly connected devices
        for (const device of currentConnected) {
            if (!_previousConnectedAddresses.includes(device.address)) {
                root.deviceConnected(device);
            }
        }

        // Find disconnected devices
        for (const addr of _previousConnectedAddresses) {
            if (!currentAddresses.includes(addr)) {
                const device = Bluetooth.devices.values.find(d => d.address === addr);
                if (device) root.deviceDisconnected(device);
            }
        }

        _previousConnectedAddresses = currentAddresses;
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const macRegex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
        const aIsMac = macRegex.test(a.name);
        const bIsMac = macRegex.test(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }
    property list<var> connectedDevices: Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction)
    property list<var> pairedButNotConnectedDevices: Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction)
    property list<var> unpairedDevices: Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction)
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]
}
