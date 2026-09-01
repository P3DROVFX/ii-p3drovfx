import QtQuick
import qs.services
import ".."

/**
 * The VPN (`kind: vpn`, NetworkManager profiles) or Tailscale (`tailscale`)
 * is up, or down when `connected` is false.
 */
ModeCondition {
    id: root
    readonly property bool tailscale: root.params?.kind === "tailscale"
    readonly property bool wantConnected: root.params?.connected !== false

    readonly property bool available: root.tailscale ? TailscaleService.available : VpnService.available
    readonly property bool up: root.tailscale ? TailscaleService.active : VpnService.active

    satisfied: root.available && root.up === root.wantConnected
    reason: !root.available ? "not available"
        : (root.tailscale ? (root.up ? (TailscaleService.tailnetName || "tailscale") : "tailscale down")
        : (root.up ? (VpnService.activeProfile || "vpn") : "vpn down"))
}
