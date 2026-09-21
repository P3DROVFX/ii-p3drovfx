pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common.functions
import qs.modules.ii.dynamicIsland.core

/**
 * A VPN or Tailscale connected or dropped.
 *
 * VpnService and TailscaleService only poll while the dashboard or settings are open, so
 * on their own they would never notice a tunnel brought up from a terminal or dropped by
 * the network. The kernel does notice: a tunnel is an interface, and `ip monitor link`
 * reports interfaces appearing, disappearing and changing state as it happens. One such
 * report asks both services for a single refresh; their answer is the edge announced.
 *
 * What the services report first is a baseline, not news: they start out "disconnected"
 * whatever the truth, so the first answer after start would otherwise announce every
 * tunnel that was already up.
 */
TransientSource {
    id: source

    activityId: "vpn"
    ttlMs: 3500
    cooldownMs: 1500

    // The tunnels the kernel names: WireGuard, OpenVPN/tun, Tailscale, the Nord and
    // Proton clients' own, and PPP-based ones.
    readonly property var tunnelPattern: /^(wg|tun|tap|tailscale|nordlynx|nordtun|proton|pvpn|ppp|ipsec)/

    property bool _baselined: false
    property bool _vpnWas: false
    property bool _tailscaleWas: false

    function _announce(connected, provider, detail) {
        if (!source._baselined)
            return;
        source.trigger({ connected: connected, provider: provider, detail: detail });
    }

    property Connections _vpn: Connections {
        target: VpnService
        function onActiveChanged() {
            const now = VpnService.active;
            if (now === source._vpnWas)
                return;
            source._vpnWas = now;
            const provider = VpnService.activeProvider === "nordvpn" ? "NordVPN"
                : (VpnService.activeProvider === "protonvpn" ? "Proton VPN" : "VPN");
            const detail = VpnService.activeProvider === "nordvpn" ? VpnService.nordvpnLocation
                : (VpnService.activeProvider === "protonvpn" ? VpnService.protonvpnLocation : VpnService.activeProfile);
            source._announce(now, provider, detail);
        }
    }

    property Connections _tailscale: Connections {
        target: TailscaleService
        function onActiveChanged() {
            const now = TailscaleService.active;
            if (now === source._tailscaleWas)
                return;
            source._tailscaleWas = now;
            const exitNode = TailscaleService.currentExitNode;
            source._announce(now, "Tailscale", exitNode !== ""
                ? exitNode : TailscaleService.tailnetName);
        }
    }

    function _refreshServices() {
        if (VpnService.enabled)
            VpnService.refresh();
        if (TailscaleService.enabled)
            TailscaleService.refresh();
    }

    // ── The kernel's view: interfaces coming and going ──────────────────────
    onAllowedChanged: source._syncWatch()
    Component.onCompleted: {
        source._syncWatch();
        // Learn what is already up, quietly.
        source._refreshServices();
        source._baselineTimer.start();
    }

    function _syncWatch() {
        source._linkWatch.running = source.allowed;
    }

    property Timer _baselineTimer: Timer {
        interval: 8000
        onTriggered: {
            source._vpnWas = VpnService.active;
            source._tailscaleWas = TailscaleService.active;
            source._baselined = true;
        }
    }

    property Process _linkWatch: Process {
        command: ProcUtils.pdeath(["ip", "-o", "monitor", "link"])
        stdout: SplitParser {
            onRead: data => {
                for (const line of String(data).split("\n")) {
                    // "4: wg0: <POINTOPOINT,UP> ..." or "Deleted 4: wg0: ..."
                    const match = /^(?:Deleted\s+)?\d+:\s+([^:@\s]+)/.exec(line.trim());
                    if (match && source.tunnelPattern.test(match[1]))
                        source._settle.restart();
                }
            }
        }
    }

    // A tunnel coming up is a burst of link events; ask once it has settled.
    property Timer _settle: Timer {
        interval: 1500
        onTriggered: source._refreshServices()
    }
}
