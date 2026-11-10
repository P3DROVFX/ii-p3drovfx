pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services

/**
 * A bluetooth device connected or disconnected.
 *
 * Devices that reconnect on their own - headphones coming out of a case, a mouse waking
 * up - drop and return within seconds, and announcing each bounce is noise rather than
 * information. So a disconnect waits `flapWindowMs` before it is announced, and a device
 * back inside that wait is a flap: neither edge is said. The reconnect used to be the edge
 * dropped instead, for 10 s after the disconnect had already been announced - turning a
 * headset off and on showed "disconnected" and then nothing while it was connected again.
 */
TransientSource {
    id: source

    activityId: "bluetooth"
    ttlMs: 3000

    readonly property int flapWindowMs: 2000
    /** Disconnects still inside the flap window: { device, name, at }. */
    property var pendingDisconnects: []

    function nameOf(device) {
        return device ? (device.name || device.alias || "") : "";
    }

    /**
     * Transitional bridge to GlobalStates.
     *
     * `FloatingNotchBluetooth.qml` reads the device and the action from
     * `GlobalStates.floatingNotchBt*`, which the panel used to write. Feeding them from
     * here keeps that widget working while it is still the thing being drawn; the
     * properties go when the activity gets its own presentation and the widget is
     * deleted with the rest of them.
     */
    function publish(device, action, active) {
        GlobalStates.floatingNotchBtDevice = active ? device : null;
        GlobalStates.floatingNotchBtAction = action;
        GlobalStates.floatingNotchBtNotifActive = active;
    }

    onTriggered: payload => {
        if (payload)
            source.publish(payload.device, payload.action ?? "connected", true);
    }

    onDismissed: source.publish(null, "connected", false)

    property Connections _bluetooth: Connections {
        target: BluetoothStatus
        function onDeviceConnected(device) {
            const name = source.nameOf(device);
            const pending = source.pendingDisconnects;
            const flapped = name !== "" && pending.some(entry => entry.name === name);
            if (flapped) {
                source.pendingDisconnects = pending.filter(entry => entry.name !== name);
                return;
            }
            source.trigger({ device: device, name: name, action: "connected" });
        }
        function onDeviceDisconnected(device) {
            const name = source.nameOf(device);
            source.pendingDisconnects = source.pendingDisconnects
                .filter(entry => entry.name !== name)
                .concat([{ device: device, name: name, at: Date.now() }]);
            flapTimer.restart();
        }
    }

    property Timer _flapTimer: Timer {
        id: flapTimer
        interval: 250
        repeat: true
        running: false
        onTriggered: {
            const now = Date.now();
            const due = source.pendingDisconnects.filter(entry => now - entry.at >= source.flapWindowMs);
            source.pendingDisconnects = source.pendingDisconnects.filter(entry => now - entry.at < source.flapWindowMs);
            if (source.pendingDisconnects.length === 0)
                flapTimer.stop();
            // The newest one is the one the strip shows; several at once are one moment.
            if (due.length > 0) {
                const last = due[due.length - 1];
                source.trigger({ device: last.device, name: last.name, action: "disconnected" });
            }
        }
    }
}
