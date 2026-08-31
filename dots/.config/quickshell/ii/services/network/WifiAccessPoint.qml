import QtQuick
import Quickshell.Networking as QNet
import qs.services

/**
 * One Wi-Fi network, as the rest of the shell sees it.
 *
 * `backend` is the live network object from Quickshell's NetworkManager
 * backend and drives everything that changes on its own. `details` carries the
 * few extras that backend doesn't expose — BSSID, frequency, NetworkManager's
 * own security string — refreshed from nmcli alongside it.
 */
QtObject {
    id: root

    property var backend: null
    property var details: null

    // Still accepted so anything building an access point straight from nmcli
    // output keeps working.
    property var lastIpcObject: null

    readonly property string ssid: root.backend?.name ?? root.lastIpcObject?.ssid ?? ""
    readonly property string bssid: root.details?.bssid ?? root.lastIpcObject?.bssid ?? ""
    readonly property int strength: root.backend ? Math.round(root.backend.signalStrength * 100) : (root.lastIpcObject?.strength ?? 0)
    readonly property int frequency: root.details?.frequency ?? root.lastIpcObject?.frequency ?? 0
    readonly property bool active: root.backend?.connected ?? root.lastIpcObject?.active ?? false
    readonly property bool known: root.backend?.known ?? false

    readonly property int securityType: root.backend?.security ?? QNet.WifiSecurityType.Unknown
    // NetworkManager's string is the friendlier of the two and covers mixed
    // modes the enum flattens, but it only arrives with the nmcli pass.
    readonly property string security: (root.details?.security ?? "").length > 0 ? root.details.security : (root.backend ? NetworkState.securityLabel(root.securityType) : (root.lastIpcObject?.security ?? ""))
    readonly property bool isSecure: root.security.length > 0
    readonly property bool enterprise: root.backend ? NetworkState.isEnterprise(root.securityType) : root.security.includes("802.1X")

    readonly property int band: root.frequency >= 5925 ? 6 : (root.frequency >= 4900 ? 5 : (root.frequency > 0 ? 2 : 0))
    readonly property string bandLabel: root.band === 0 ? "" : (root.band === 2 ? "2.4 GHz" : `${root.band} GHz`)

    readonly property int connectionState: root.backend?.state ?? QNet.ConnectionState.Unknown
    readonly property bool stateChanging: root.backend?.stateChanging ?? false

    property bool askingPassword: false
}
