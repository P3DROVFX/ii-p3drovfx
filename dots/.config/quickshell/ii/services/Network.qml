pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking as QNet
import qs.modules.common.functions
import qs.services.network

/**
 * Wi-Fi and wired status.
 *
 * State is read from NetworkState, which sits on Quickshell's native
 * NetworkManager backend, and writes go out through NetworkCommands. The shape
 * below is what the bar, the sidebars and the mode conditions already bind to,
 * and is kept stable on purpose.
 */
Singleton {
    id: root

    // The backend needs a second or two to enumerate devices on a cold shell.
    // Until it has, status comes from a one-shot nmcli seed so the bar doesn't
    // spend that time claiming there is no adapter.
    property string seedStatus: "disconnected"
    property bool seedWifiEnabled: false
    property bool seedEthernet: false
    property string seedNetworkName: ""

    readonly property bool ready: NetworkState.ready
    readonly property bool wifi: root.wifiStatus === "connected"
    readonly property bool ethernet: root.ready ? NetworkState.wiredConnected : root.seedEthernet
    readonly property bool wifiEnabled: root.ready ? NetworkState.wifiEnabled : root.seedWifiEnabled
    readonly property bool wifiHardwareEnabled: root.ready ? NetworkState.wifiHardwareEnabled : true
    readonly property bool captivePortal: NetworkState.captivePortal

    property bool wifiScanning: false
    readonly property bool wifiConnecting: root.wifiConnectTarget !== null || NetworkState.wifiConnecting

    property string lastWifiError: ""
    property int lastWifiExitCode: 0
    property WifiAccessPoint wifiConnectTarget
    property WifiAccessPoint wifiErrorTarget

    property var savedConnections: []
    property list<string> savedSsids: []
    property var wifiDetails: ({})

    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n && n.active) ?? null

    // Sorted by connection state then signal strength. Recomputed explicitly
    // rather than as a live binding: reading `.active`/`.strength` off every
    // access point inside a binding subscribes it to every AP's RSSI, so this
    // used to re-sort — and hand every listener a brand-new array — on every
    // signal fluctuation from any network in range, freezing the Wi-Fi tab and
    // the sidebar/quick-toggle Wi-Fi lists whenever several APs were visible.
    property list<var> friendlyWifiNetworks: []

    function resortFriendlyNetworks(): void {
        root.friendlyWifiNetworks = [...root.wifiNetworks].sort((a, b) => {
            if (a.active && !b.active)
                return -1;
            if (!a.active && b.active)
                return 1;
            return b.strength - a.strength;
        });
    }

    readonly property string wifiStatus: {
        if (!root.ready)
            return root.seedStatus;
        if (!NetworkState.hasWifiDevice || !NetworkState.wifiEnabled || !NetworkState.wifiHardwareEnabled)
            return "disabled";
        if (NetworkState.wifiConnecting)
            return "connecting";
        if (!NetworkState.wifiConnected)
            return "disconnected";
        return NetworkState.limited ? "limited" : "connected";
    }

    readonly property string networkName: {
        if (!root.ready)
            return root.seedNetworkName;
        if (NetworkState.wifiConnected)
            return NetworkState.activeWifiNetwork?.name ?? "";
        if (NetworkState.wiredConnected)
            return NetworkState.wiredNetwork?.name ?? "";
        return "";
    }
    readonly property string activeConnectionName: root.networkName
    readonly property int networkStrength: root.active?.strength ?? 0
    readonly property string materialSymbol: root.ethernet ? "lan" : (root.wifiEnabled && root.wifiStatus === "connected") ? ((root.active?.strength ?? 0) > 83 ? "android_wifi_4_bar" : (root.active?.strength ?? 0) > 67 ? "android_wifi_3_bar" : (root.active?.strength ?? 0) > 50 ? "wifi_2_bar" : (root.active?.strength ?? 0) > 33 ? "wifi_2_bar" : (root.active?.strength ?? 0) > 17 ? "wifi_1_bar" : "signal_wifi_0_bar") : (root.wifiStatus === "connecting") ? "signal_wifi_statusbar_not_connected" : (root.wifiStatus === "disconnected") ? "wifi_find" : (root.wifiStatus === "disabled") ? "signal_wifi_off" : "signal_wifi_bad"

    // Connection Details
    property string ipAddress: ""
    property string ipAddress6: ""
    property string gateway: ""
    property string dns: ""
    property string subnetMask: ""
    readonly property string macAddress: NetworkState.wifiMac

    // Control
    function enableWifi(enabled = true): void {
        NetworkCommands.setWifiRadio(enabled);
    }

    function toggleWifi(): void {
        root.enableWifi(!root.wifiEnabled);
    }

    function rescanWifi(): void {
        if (root.wifiScanning)
            return;
        root.wifiScanning = true;
        NetworkCommands.rescanWifi(() => {
            root.wifiScanning = false;
            root.refreshDetails();
        });
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        if (!accessPoint)
            return;
        root.beginConnect(accessPoint);
        NetworkCommands.connectToSsid(accessPoint.ssid, NetworkState.wifiInterface, (code, out, err) => root.finishConnect(code, err));
    }

    function connectWithPassword(ssid: string, password: string, username = "", hidden = false): void {
        root.beginConnect(root.wifiNetworks.find(n => n && n.ssid === ssid) ?? null);
        const done = (code, out, err) => root.finishConnect(code, err);
        if (username.length > 0) {
            NetworkCommands.connectWithEnterprise(ssid, password, {
                identity: username,
                ifname: NetworkState.wifiInterface,
                hidden: hidden
            }, done);
            return;
        }
        // A stored profile still holding the old password would just fail the
        // same way again, so it goes before the retry rather than after it.
        const stale = root.savedProfileFor(ssid);
        if (stale.length > 0)
            NetworkCommands.forgetProfile(stale);
        NetworkCommands.connectWithPsk(ssid, password, {
            ifname: NetworkState.wifiInterface,
            hidden: hidden
        }, done);
    }

    function connectToHiddenNetwork(ssid: string, password: string, username = ""): void {
        root.connectWithPassword(ssid, password, username, true);
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        if (!network)
            return;
        root.connectWithPassword(network.ssid, password, username, false);
    }

    function disconnectWifiNetwork(): void {
        const network = NetworkState.activeWifiNetwork;
        if (network) {
            network.disconnect();
            return;
        }
        if (NetworkState.wifiInterface.length > 0)
            NetworkCommands.disconnectDevice(NetworkState.wifiInterface);
    }

    // Goes through the backend so the right profile is removed even when it was
    // saved under a name that isn't the SSID.
    function forgetWifiNetwork(ssid: string): void {
        const network = NetworkState.findNetwork(ssid);
        if (network) {
            network.forget();
            Qt.callLater(root.refreshSaved);
            return;
        }
        const profile = root.savedProfileFor(ssid);
        if (profile.length === 0)
            return;
        NetworkCommands.forgetProfile(profile, () => root.refreshSaved());
    }

    function openPublicWifiPortal(): void {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]); // From some StackExchange thread, seems to work
    }

    function update(): void {
        root.refreshDetails();
        root.refreshSaved();
        root.refreshAddresses();
    }

    // ---- Connection bookkeeping -------------------------------------------
    function beginConnect(accessPoint): void {
        root.lastWifiError = "";
        root.lastWifiExitCode = 0;
        root.wifiErrorTarget = null;
        root.wifiConnectTarget = accessPoint;
        if (accessPoint)
            accessPoint.askingPassword = false;
    }

    function finishConnect(exitCode: int, stderr: string): void {
        const target = root.wifiConnectTarget;
        root.wifiConnectTarget = null;
        root.lastWifiError = (stderr ?? "").trim();
        root.refreshDetails();
        root.refreshSaved();
        if (!target)
            return;
        target.askingPassword = exitCode !== 0;
        if (exitCode === 0 || root.lastWifiError.includes("Secrets were required")) {
            root.lastWifiExitCode = 0;
            root.wifiErrorTarget = null;
            return;
        }
        root.lastWifiExitCode = exitCode;
        root.wifiErrorTarget = target;
    }

    function savedProfileFor(ssid: string): string {
        const match = root.savedConnections.find(c => c.type === "802-11-wireless" && c.name === ssid);
        return match?.name ?? "";
    }

    // ---- Backend to WifiAccessPoint bridge --------------------------------
    function syncNetworks(): void {
        const live = Array.from(NetworkState.wifiNetworks ?? []);
        const wrappers = root.wifiNetworks;
        for (let i = wrappers.length - 1; i >= 0; i--) {
            const wrapper = wrappers[i];
            if (live.some(n => n === wrapper.backend))
                continue;
            wrappers.splice(i, 1);
            if (root.wifiConnectTarget === wrapper)
                root.wifiConnectTarget = null;
            if (root.wifiErrorTarget === wrapper)
                root.wifiErrorTarget = null;
            wrapper.destroy();
        }
        for (const network of live) {
            if (wrappers.some(w => w.backend === network))
                continue;
            wrappers.push(apComponent.createObject(root, {
                backend: network,
                details: root.wifiDetails[network.name] ?? null
            }));
        }
        root.applyDetails();
        root.resortFriendlyNetworks();
    }

    function applyDetails(): void {
        for (const accessPoint of root.wifiNetworks)
            accessPoint.details = root.wifiDetails[accessPoint.ssid] ?? null;
    }

    function refreshDetails(): void {
        detailsDebounce.restart();
    }

    function refreshSaved(): void {
        savedDebounce.restart();
    }

    function refreshAddresses(): void {
        addressDebounce.restart();
    }

    // Mirrored locally rather than watched through Connections: the backend can
    // be up before this singleton exists, and then its first change signal has
    // already been and gone.
    readonly property var liveNetworks: NetworkState.wifiNetworks
    readonly property bool wifiConnected: NetworkState.wifiConnected
    readonly property var activeBackendNetwork: NetworkState.activeWifiNetwork

    onWifiNetworksChanged: root.applyDetails()
    onLiveNetworksChanged: {
        root.syncNetworks();
        root.refreshDetails();
    }
    onWifiConnectedChanged: {
        root.refreshAddresses();
        root.refreshSaved();
    }
    onActiveBackendNetworkChanged: root.refreshAddresses()
    onReadyChanged: {
        root.syncNetworks();
        root.update();
    }

    // The only failure the backend reports that the UI acts on: a network that
    // wants a password it doesn't have yet.
    Connections {
        target: root.wifiConnectTarget?.backend ?? null
        function onConnectionFailed(reason): void {
            const target = root.wifiConnectTarget;
            if (!target)
                return;
            if (reason === QNet.ConnectionFailReason.NoSecrets) {
                target.askingPassword = true;
                return;
            }
            root.lastWifiError = NetworkState.failReasonLabel(reason);
        }
    }

    Timer {
        id: detailsDebounce
        interval: 250
        onTriggered: NetworkCommands.readWifiDetails(details => {
            root.wifiDetails = details;
            root.syncNetworks();
        })
    }

    Timer {
        id: savedDebounce
        interval: 400
        onTriggered: NetworkCommands.readSavedConnections(rows => {
            root.savedConnections = rows;
            const wireless = rows.filter(r => r.type === "802-11-wireless").map(r => r.name);
            const known = Array.from(NetworkState.wifiNetworks ?? []).filter(n => n.known).map(n => n.name);
            root.savedSsids = [...new Set([...wireless, ...known])];
        })
    }

    Timer {
        id: addressDebounce
        interval: 250
        onTriggered: {
            if (!NetworkState.wifiConnected) {
                root.ipAddress = "";
                root.ipAddress6 = "";
                root.gateway = "";
                root.dns = "";
                root.subnetMask = "";
                return;
            }
            NetworkCommands.readIpConfig(NetworkState.wifiInterface, config => {
                root.ipAddress = config.address ?? "";
                root.ipAddress6 = config.address6 ?? "";
                root.gateway = config.gateway ?? "";
                root.dns = (config.dns ?? []).join(" / ");
                root.subnetMask = NetworkCommands.prefixToMask(config.prefix ?? 0);
            });
        }
    }

    // NetworkManager profiles can also be added, edited or removed from outside
    // the shell, and the D-Bus backend only tracks the networks in range.
    Process {
        id: subscriber
        running: true
        // Runs for as long as the shell does, and reports nothing between network
        // events, so an orphaned one never notices its output is gone.
        command: ProcUtils.pdeath(["nmcli", "monitor"])
        stdout: SplitParser {
            onRead: {
                root.refreshSaved();
                root.refreshDetails();
            }
        }
    }

    Process {
        id: seedProc
        running: true
        command: ["bash", "-c", 'nmcli -t -f TYPE,STATE device status; echo ---; nmcli radio wifi; echo ---; nmcli -t -g NAME,TYPE connection show --active']
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                if (NetworkState.ready)
                    return;
                const blocks = text.split("---");
                let status = "disconnected";
                let wired = false;
                (blocks[0] ?? "").trim().split("\n").forEach(line => {
                    if (line.startsWith("ethernet:") && line.includes("connected") && !line.includes("disconnected"))
                        wired = true;
                    if (!line.startsWith("wifi:"))
                        return;
                    if (line.includes("unavailable"))
                        status = "disabled";
                    else if (line.includes("connecting"))
                        status = "connecting";
                    else if (line.includes("disconnected"))
                        status = "disconnected";
                    else if (line.includes("connected"))
                        status = "connected";
                });
                root.seedWifiEnabled = (blocks[1] ?? "").trim() === "enabled";
                root.seedEthernet = wired;
                root.seedStatus = root.seedWifiEnabled ? status : "disabled";
                const active = (blocks[2] ?? "").trim().split("\n").find(l => l.includes(":802-11-wireless"));
                root.seedNetworkName = active ? active.split(":")[0] : "";
            }
        }
    }

    Component {
        id: apComponent

        WifiAccessPoint {}
    }

    // Catches RSSI drift between network add/remove events. Explicit and
    // throttled on purpose — see the note on friendlyWifiNetworks above.
    Timer {
        interval: 4000
        repeat: true
        running: root.wifiNetworks.length > 0
        onTriggered: root.resortFriendlyNetworks()
    }

    Component.onCompleted: {
        root.syncNetworks();
        root.update();
    }
}
