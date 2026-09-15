pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Per-link DNS-over-TLS control on top of systemd-resolved.
 *
 * Enabling points the default-route link at the configured resolver
 * (`resolvectl dns <link> <ip>#<name>`) and turns on DoT for that link.
 * Disabling runs `resolvectl revert <link>`, which restores whatever
 * NetworkManager/DHCP handed out — saved connection profiles are never touched.
 *
 * Because per-link settings are runtime-only, they are re-applied whenever the
 * default route changes or the link is reconfigured.
 *
 * The `resolvectl` calls need polkit authorisation; see
 * `scripts/polkit/49-resolve1-wheel.rules` for the passwordless rule.
 */
Singleton {
    id: root

    readonly property string ruleFileName: "49-resolve1-wheel.rules"
    readonly property string ruleTargetPath: `/etc/polkit-1/rules.d/${root.ruleFileName}`
    readonly property string ruleSourcePath: FileUtils.trimFileProtocol(Quickshell.shellPath(`scripts/polkit/${root.ruleFileName}`))
    readonly property string installCommand: `sudo install -Dm644 '${root.ruleSourcePath}' '${root.ruleTargetPath}'`
    readonly property string uninstallCommand: `sudo rm -f '${root.ruleTargetPath}'`

    // Probed state
    property bool resolvedAvailable: false
    property bool polkitRuleInstalled: false
    property string link: ""
    property string mode: "no" // no | opportunistic | yes
    property string activeServers: ""
    property bool busy: false
    property string errorMessage: ""

    readonly property bool active: root.mode === "yes" || root.mode === "opportunistic"
    readonly property bool available: root.resolvedAvailable && root.link.length > 0

    // Desired configuration
    readonly property var options: Config.options?.dnsOverTls ?? null
    readonly property bool wanted: root.options?.enabled ?? false
    readonly property string serverName: root.options?.serverName ?? ""
    readonly property string serverAddress: root.options?.serverAddress ?? ""
    readonly property string fallbackAddress: root.options?.fallbackAddress ?? ""
    readonly property bool strict: root.options?.strict ?? true
    readonly property bool routeAllQueries: root.options?.routeAllQueries ?? true
    readonly property bool reapplyOnNetworkChange: root.options?.reapplyOnNetworkChange ?? true

    readonly property string statusText: !root.resolvedAvailable ? Translation.tr("systemd-resolved not running") : !root.available ? Translation.tr("No network") : root.mode === "yes" ? Translation.tr("Strict") : root.mode === "opportunistic" ? Translation.tr("Opportunistic") : Translation.tr("Off")

    // Well-known public resolvers that support DNS-over-TLS
    readonly property var presets: [
        {
            key: "adguard",
            label: "AdGuard",
            serverName: "dns.adguard-dns.com",
            serverAddress: "94.140.14.14",
            fallbackAddress: "94.140.15.15"
        },
        {
            key: "adguardFamily",
            label: "AdGuard Family",
            serverName: "family.adguard-dns.com",
            serverAddress: "94.140.14.15",
            fallbackAddress: "94.140.15.16"
        },
        {
            key: "cloudflare",
            label: "Cloudflare",
            serverName: "cloudflare-dns.com",
            serverAddress: "1.1.1.1",
            fallbackAddress: "1.0.0.1"
        },
        {
            key: "cloudflareSecurity",
            label: "Cloudflare Security",
            serverName: "security.cloudflare-dns.com",
            serverAddress: "1.1.1.2",
            fallbackAddress: "1.0.0.2"
        },
        {
            key: "quad9",
            label: "Quad9",
            serverName: "dns.quad9.net",
            serverAddress: "9.9.9.9",
            fallbackAddress: "149.112.112.112"
        },
        {
            key: "mullvad",
            label: "Mullvad",
            serverName: "dns.mullvad.net",
            serverAddress: "194.242.2.2",
            fallbackAddress: "193.19.108.2"
        }
    ]

    readonly property string preset: root.options?.preset ?? "custom"
    readonly property string presetLabel: root.presets.find(entry => entry.key === root.preset)?.label ?? (root.serverName.length > 0 ? root.serverName : Translation.tr("Custom"))

    function applyPreset(key: string): void {
        const entry = root.presets.find(candidate => candidate.key === key);
        if (!entry || !root.options)
            return;
        root.options.preset = entry.key;
        root.options.serverName = entry.serverName;
        root.options.serverAddress = entry.serverAddress;
        root.options.fallbackAddress = entry.fallbackAddress;
    }

    signal applyFinished(bool success, string message)

    function refresh(): void {
        if (probeProc.running)
            return;
        probeProc.running = true;
    }

    function serverArguments(): string {
        const name = root.serverName.trim();
        const suffix = name.length > 0 ? `#${name}` : "";
        const addresses = [root.serverAddress, root.fallbackAddress].map(address => address.trim()).filter(address => address.length > 0);
        return addresses.map(address => `${address}${suffix}`).join(" ");
    }

    function configurationValid(): bool {
        return root.serverAddress.trim().length > 0;
    }

    function enable(): void {
        if (root.busy)
            return;
        if (!root.available) {
            root.fail(Translation.tr("No default network link to configure."));
            return;
        }
        if (!root.configurationValid()) {
            root.fail(Translation.tr("No DNS server address configured."));
            return;
        }
        if (root.options)
            root.options.enabled = true;
        root.applyNow();
    }

    function disable(): void {
        if (root.busy)
            return;
        if (root.options)
            root.options.enabled = false;
        if (!root.available) {
            root.refresh();
            return;
        }
        root.busy = true;
        root.errorMessage = "";
        revertProc.linkToRevert = root.link;
        revertProc.running = true;
    }

    function toggle(): void {
        if (root.active || root.wanted)
            root.disable();
        else
            root.enable();
    }

    // Pushes the current configuration to the link without changing the desired state.
    // Used by enable() and by the re-apply watcher after a network change.
    function applyNow(): void {
        if (root.busy || !root.available || !root.configurationValid())
            return;
        root.busy = true;
        root.errorMessage = "";
        const dotMode = root.strict ? "yes" : "opportunistic";
        const domainStep = root.routeAllQueries ? `resolvectl domain '${root.link}' '~.'\n` : "";
        applyProc.command = ["bash", "-c", `set -e
resolvectl dns '${root.link}' ${root.serverArguments()}
resolvectl dnsovertls '${root.link}' ${dotMode}
${domainStep}resolvectl flush-caches || true`];
        applyProc.running = true;
    }

    function fail(message: string): void {
        root.busy = false;
        root.errorMessage = message;
        Quickshell.execDetached(["notify-send", "-a", "Shell", "-u", "critical", Translation.tr("DNS over TLS"), message, "-i", "vpn_lock"]);
        root.applyFinished(false, message);
    }

    // Reverts the link and stops wanting DoT, used when a fresh config breaks name resolution
    function revertAfterFailure(message: string): void {
        if (root.options)
            root.options.enabled = false;
        revertProc.linkToRevert = root.link;
        revertProc.running = true;
        root.fail(message);
    }

    Component.onCompleted: root.refresh()

    Process {
        id: probeProc
        command: ["bash", "-c", `link=$(ip -o route show default 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit }}')
echo "LINK=$link"
systemctl is-active --quiet systemd-resolved && echo "RESOLVED=1" || echo "RESOLVED=0"
pkcheck --action-id org.freedesktop.resolve1.set-dns-over-tls --process $$ >/dev/null 2>&1 && echo "POLKIT=1" || echo "POLKIT=0"
if [ -n "$link" ]; then
    echo "MODE=$(resolvectl dnsovertls "$link" 2>/dev/null | sed 's/.*: //')"
    echo "SERVERS=$(resolvectl dns "$link" 2>/dev/null | sed 's/.*: //')"
fi`]
        stdout: StdioCollector {
            onStreamFinished: {
                const values = {};
                text.trim().split("\n").forEach(line => {
                    const separator = line.indexOf("=");
                    if (separator > 0)
                        values[line.slice(0, separator)] = line.slice(separator + 1).trim();
                });
                root.link = values["LINK"] ?? "";
                root.resolvedAvailable = values["RESOLVED"] === "1";
                root.polkitRuleInstalled = values["POLKIT"] === "1";
                root.mode = values["MODE"] ?? "no";
                root.activeServers = values["SERVERS"] ?? "";
                root.maybeReapply();
            }
        }
    }

    Process {
        id: applyProc
        stderr: StdioCollector {
            id: applyErrorCollector
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.busy = false;
                const details = applyErrorCollector.text.trim();
                root.revertAfterFailure(details.length > 0 ? details : Translation.tr("Failed to apply DNS settings."));
                return;
            }
            verifyProc.running = true;
        }
    }

    // A wrong address or certificate name silently kills name resolution, so
    // confirm a real lookup still works before leaving the new settings in place.
    Process {
        id: verifyProc
        command: ["bash", "-c", "timeout 8 resolvectl query --cache=no example.com >/dev/null 2>&1"]
        onExited: exitCode => {
            root.busy = false;
            if (exitCode !== 0) {
                root.revertAfterFailure(Translation.tr("%1 did not answer, reverting to the network's DNS.").arg(root.serverName.length > 0 ? root.serverName : root.serverAddress));
                return;
            }
            root.applyFinished(true, "");
            root.refresh();
        }
    }

    Process {
        id: revertProc
        property string linkToRevert: ""
        command: ["resolvectl", "revert", revertProc.linkToRevert]
        onExited: {
            root.busy = false;
            root.refresh();
        }
    }

    // Per-link settings are runtime-only: NetworkManager wipes them whenever it
    // reconfigures the link, so put them back if they are still wanted.
    function maybeReapply(): void {
        if (!root.reapplyOnNetworkChange || !root.wanted || root.busy)
            return;
        if (!root.available || root.active || !root.configurationValid())
            return;
        root.applyNow();
    }

    Connections {
        target: Config
        function onReadyChanged(): void {
            if (Config.ready)
                root.refresh();
        }
    }

    Connections {
        target: Network
        function onWifiStatusChanged(): void {
            reapplyDebounce.restart();
        }
        function onActiveConnectionNameChanged(): void {
            reapplyDebounce.restart();
        }
        function onEthernetChanged(): void {
            reapplyDebounce.restart();
        }
    }

    Timer {
        id: reapplyDebounce
        interval: 2500
        onTriggered: root.refresh()
    }

    Timer {
        running: true
        repeat: true
        interval: root.wanted ? 30000 : 300000
        onTriggered: root.refresh()
    }
}
