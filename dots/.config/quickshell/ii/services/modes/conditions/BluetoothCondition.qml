import QtQuick
import qs.services
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * One of `devices` (addresses; empty = any device) is connected, or none is
 * when `connected` is false.
 */
ModeCondition {
    id: root
    readonly property var devices: ModeSchema.stringList(root.params?.devices).map(a => a.toUpperCase())
    readonly property bool wantConnected: root.params?.connected !== false

    readonly property var connected: Array.from(BluetoothStatus.connectedDevices ?? [])
    readonly property var matched: root.devices.length
        ? root.connected.filter(d => root.devices.indexOf(String(d.address ?? "").toUpperCase()) !== -1)
        : root.connected

    satisfied: root.wantConnected ? root.matched.length > 0 : root.matched.length === 0
    reason: root.matched[0]?.name ?? (root.wantConnected ? "" : "no device")
}
