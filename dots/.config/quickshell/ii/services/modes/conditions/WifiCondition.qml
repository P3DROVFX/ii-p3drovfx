import QtQuick
import qs.services
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * Wi-Fi connected to one of `ssids` (empty = any network), or not connected
 * when `connected` is false. `ethernet` (null | bool) additionally requires
 * a wired link to be up or down.
 */
ModeCondition {
    id: root
    readonly property var ssids: ModeSchema.stringList(root.params?.ssids)
    readonly property bool wantConnected: root.params?.connected !== false
    readonly property var ethernet: root.params?.ethernet ?? null

    readonly property bool wifiUp: Network.wifiEnabled && Network.wifiStatus === "connected"
    readonly property bool ssidOk: root.ssids.length === 0 || root.ssids.indexOf(Network.networkName) !== -1
    readonly property bool wifiMatch: root.wifiUp && root.ssidOk
    readonly property bool ethernetOk: root.ethernet === null || Network.ethernet === root.ethernet

    satisfied: (root.wantConnected ? root.wifiMatch : !root.wifiMatch) && root.ethernetOk
    reason: root.wifiUp ? Network.networkName : (Network.ethernet ? "ethernet" : "offline")
}
