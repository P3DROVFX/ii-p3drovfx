pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services

/**
 * A bluetooth device connected or disconnected.
 *
 * Devices that reconnect on their own - headphones coming out of a case, a mouse waking
 * up - drop and return within seconds, and announcing each bounce is noise rather than
 * information. A device that comes back that quickly is treated as a flap.
 */
TransientSource {
    id: source

    activityId: "bluetooth"
    ttlMs: 3000

    readonly property int flapWindowMs: 10000
    property string lastDisconnected: ""
    property double lastDisconnectedAt: 0

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
            if (name !== "" && name === source.lastDisconnected
                    && (Date.now() - source.lastDisconnectedAt) < source.flapWindowMs)
                return;
            source.trigger({ device: device, name: name, action: "connected" });
        }
        function onDeviceDisconnected(device) {
            source.lastDisconnected = source.nameOf(device);
            source.lastDisconnectedAt = Date.now();
            source.trigger({ device: device, name: source.lastDisconnected, action: "disconnected" });
        }
    }
}
