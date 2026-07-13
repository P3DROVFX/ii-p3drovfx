pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import Quickshell.Io
import QtQuick
import qs.services.network

/**
 * Network service with nmcli.
 */
Singleton {
    id: root

    property bool wifi: true
    property bool ethernet: false

    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running || connectWithPasswordProc.running
    property string lastWifiError: ""
    property int lastWifiExitCode: 0
    property string activeConnectionName: ""
    property list<string> savedSsids: []
    property WifiAccessPoint wifiConnectTarget
    property WifiAccessPoint wifiErrorTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        return b.strength - a.strength;
    })
    property string wifiStatus: "disconnected"

    property string networkName: ""
    property int networkStrength
    property string materialSymbol: root.ethernet ? "lan" : (root.wifiEnabled && root.wifiStatus === "connected") ? ((root.active?.strength ?? 0) > 83 ? "android_wifi_4_bar" : (root.active?.strength ?? 0) > 67 ? "android_wifi_3_bar" : (root.active?.strength ?? 0) > 50 ? "wifi_2_bar" : (root.active?.strength ?? 0) > 33 ? "wifi_2_bar" : (root.active?.strength ?? 0) > 17 ? "wifi_1_bar" : "signal_wifi_0_bar") : (root.wifiStatus === "connecting") ? "signal_wifi_statusbar_not_connected" : (root.wifiStatus === "disconnected") ? "wifi_find" : (root.wifiStatus === "disabled") ? "signal_wifi_off" : "signal_wifi_bad"

    // Connection Details
    property string ipAddress: ""
    property string gateway: ""
    property string dns: ""
    property string subnetMask: ""

    // Control
    function enableWifi(enabled = true): void {
        const cmd = enabled ? "on" : "off";
        enableWifiProc.exec(["nmcli", "radio", "wifi", cmd]);
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        wifiScanning = true;
        rescanProcess.running = true;
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        accessPoint.askingPassword = false;
        root.lastWifiExitCode = 0;
        root.wifiErrorTarget = null;
        root.wifiConnectTarget = accessPoint;
        // We use this instead of `nmcli connection up SSID` because this also creates a connection profile
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid]);
    }

    function disconnectWifiNetwork(): void {
        if (active)
            disconnectProc.exec(["nmcli", "connection", "down", active.ssid]);
    }

    function forgetWifiNetwork(ssid: string): void {
        forgetProc.exec(["nmcli", "connection", "delete", ssid]);
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]); // From some StackExchange thread, seems to work
    }

    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        network.askingPassword = false;
        root.lastWifiExitCode = 0;
        root.wifiErrorTarget = null;
        root.wifiConnectTarget = network;
        changePasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": network.ssid
            },
            "command": ["bash", "-c", 'nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"']
        });
    }

    function connectWithPassword(ssid: string, password: string, username = "", hidden = false): void {
        root.lastWifiExitCode = 0;
        root.wifiErrorTarget = null;
        for (let i = 0; i < friendlyWifiNetworks.length; i++) {
            if (friendlyWifiNetworks[i].ssid === ssid) {
                root.wifiConnectTarget = friendlyWifiNetworks[i];
                break;
            }
        }
        connectWithPasswordProc.exec({
            "environment": {
                "PASSWORD": password,
                "SSID": ssid
            },
            "command": ["bash", "-c", 'nmcli connection delete "$SSID" 2>/dev/null; nmcli dev wifi connect "$SSID"; nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"; nmcli connection up "$SSID"']
        });
    }

    Process {
        id: enableWifiProc
    }

    Process {
        id: connectProc
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: SplitParser {
            onRead: line => {
                root.lastWifiError = "";
                root.lastWifiExitCode = 0;
                getNetworks.running = true;
            }
        }
        stderr: SplitParser {
            onRead: line => {
                root.lastWifiError = line;
                if (line.includes("Secrets were required")) {
                    root.wifiConnectTarget.askingPassword = true;
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.lastWifiError.includes("Secrets were required")) {
                root.lastWifiExitCode = exitCode;
                root.wifiErrorTarget = root.wifiConnectTarget;
            } else {
                root.lastWifiExitCode = 0;
                root.wifiErrorTarget = null;
            }
            root.wifiConnectTarget.askingPassword = (exitCode !== 0);
            root.wifiConnectTarget = null;
        }
    }

    Process {
        id: disconnectProc
        stdout: SplitParser {
            onRead: getNetworks.running = true
        }
    }

    Process {
        id: forgetProc
        onExited: {
            getNetworks.running = true;
        }
    }

    Process {
        id: changePasswordProc
        onExited: { // Re-attempt connection after changing password
            connectProc.running = false;
            connectProc.running = true;
        }
    }

    Process {
        id: connectWithPasswordProc
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: SplitParser {
            onRead: line => {
                root.lastWifiError = "";
                root.lastWifiExitCode = 0;
                getNetworks.running = true
            }
        }
        stderr: SplitParser {
            onRead: line => {
                root.lastWifiError = line;
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.lastWifiExitCode = exitCode;
            getNetworks.running = true;
            if (exitCode !== 0) {
                root.wifiErrorTarget = root.wifiConnectTarget;
            } else {
                root.wifiErrorTarget = null;
            }
            root.wifiConnectTarget = null;
        }
    }

    Process {
        id: connectionDetailsProc
        command: ["sh", "-c", "nmcli -t -f IP4.ADDRESS,IP4.GATEWAY,IP4.DNS device show $(nmcli -t -f DEVICE,TYPE d status | grep wifi | head -1 | cut -d: -f1)"]
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                root.dns = ""; // reset antes de acumular
                const lines = text.trim().split('\n');
                for (const line of lines) {
                    const idx = line.indexOf(':');
                    if (idx < 0)
                        continue;
                    const key = line.substring(0, idx);
                    const val = line.substring(idx + 1);
                    if (key.includes("IP4.ADDRESS")) {
                        const parts = val.split('/');
                        root.ipAddress = parts[0] || "";
                        const cidr = parseInt(parts[1] || "24");
                        root.subnetMask = cidr === 32 ? "255.255.255.255" : cidr === 24 ? "255.255.255.0" : cidr === 16 ? "255.255.0.0" : ("/" + cidr);
                    } else if (key.includes("IP4.GATEWAY"))
                        root.gateway = val;
                    else if (key.includes("IP4.DNS")) {
                        root.dns = root.dns ? (root.dns + " / " + val) : val;
                    }
                }
            }
        }
    }

    Process {
        id: rescanProcess
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: SplitParser {
            onRead: {
                wifiScanning = false;
                getNetworks.running = true;
            }
        }
    }

    Process {
        id: getSavedConnections
        command: ["sh", "-c", "nmcli -t -f 802-11-wireless.ssid,NAME connection show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ssids = [];
                text.trim().split("\n").forEach(line => {
                    const parts = line.split(":");
                    if (parts[0]) ssids.push(parts[0]);
                    if (parts[1]) ssids.push(parts[1]); // Also include the profile name
                });
                root.savedSsids = ssids;
            }
        }
    }

    // Status update
    function update() {
        updateConnectionType.startCheck();
        wifiStatusProcess.running = true;
        updateNetworkName.running = true;
        updateNetworkStrength.running = true;

        if (root.wifiStatus === "connected") {
            connectionDetailsProc.running = true;
        }
        getSavedConnections.running = true;
    }

    Process {
        id: subscriber
        running: true
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.update()
        }
    }

    Process {
        id: updateConnectionType
        property string buffer
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        function startCheck() {
            buffer = "";
            updateConnectionType.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                updateConnectionType.buffer += data + "\n";
            }
        }
        onExited: (exitCode, exitStatus) => {
            const lines = updateConnectionType.buffer.trim().split('\n');
            const connectivity = lines.pop(); // none, limited, full
            let hasEthernet = false;
            let hasWifi = false;
            let wifiStatus = "disconnected";
            lines.forEach(line => {
                if (line.includes("ethernet") && line.includes("connected"))
                    hasEthernet = true;
                else if (line.includes("wifi:")) {
                    if (line.includes("disconnected")) {
                        wifiStatus = "disconnected";
                    } else if (line.includes("connected")) {
                        hasWifi = true;
                        wifiStatus = "connected";

                        if (connectivity === "limited") {
                            hasWifi = false;
                            wifiStatus = "limited";
                        }
                    } else if (line.includes("connecting")) {
                        wifiStatus = "connecting";
                    } else if (line.includes("unavailable")) {
                        wifiStatus = "disabled";
                    }
                }
            });
            root.wifiStatus = wifiStatus;
            root.ethernet = hasEthernet;
            root.wifi = hasWifi;

            if (wifiStatus !== "connected") {
                root.ipAddress = "";
                root.gateway = "";
                root.dns = "";
                root.subnetMask = "";
            }
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                root.networkName = data;
            }
        }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi | awk '/^\\*/{if (NR!=1) {print $2}}'"]
        stdout: SplitParser {
            onRead: data => {
                root.networkStrength = parseInt(data);
            }
        }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        Component.onCompleted: running = true
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiEnabled = text.trim() === "enabled";
            }
        }
    }

    Process {
        id: getNetworks
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY,NAME", "d", "w"]
        environment: ({
                LANG: "C",
                LC_ALL: "C"
            })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED";
                const rep = new RegExp("\\\\:", "g");
                const rep2 = new RegExp(PLACEHOLDER, "g");

                const allNetworks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":");
                    const ssid = net[3];
                    const profileName = net[6];
                    if (profileName && profileName !== "--" && !root.savedSsids.includes(ssid)) {
                        // Dynamically add to savedSsids if nmcli says it has a profile
                        const newSaved = [...root.savedSsids];
                        newSaved.push(ssid);
                        root.savedSsids = newSaved;
                    }
                    return {
                        active: net[0] === "yes",
                        strength: parseInt(net[1]),
                        frequency: parseInt(net[2]),
                        ssid: ssid,
                        bssid: net[4]?.replace(rep2, ":") ?? "",
                        security: net[5] || "",
                        isSaved: profileName && profileName !== "--"
                    };
                }).filter(n => n.ssid && n.ssid.length > 0);

                // Group networks by SSID and prioritize connected ones
                const networkMap = new Map();
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid);
                    if (!existing) {
                        networkMap.set(network.ssid, network);
                    } else {
                        // Prioritize active/connected networks
                        if (network.active && !existing.active) {
                            networkMap.set(network.ssid, network);
                        } else if (!network.active && !existing.active) {
                            // If both are inactive, keep the one with better signal
                            if (network.strength > existing.strength) {
                                networkMap.set(network.ssid, network);
                            }
                        }
                        // If existing is active and new is not, keep existing
                    }
                }

                const wifiNetworks = Array.from(networkMap.values());

                const rNetworks = root.wifiNetworks;

                const destroyed = rNetworks.filter(rn => !wifiNetworks.find(n => n.frequency === rn.frequency && n.ssid === rn.ssid && n.bssid === rn.bssid));
                for (const network of destroyed)
                    rNetworks.splice(rNetworks.indexOf(network), 1).forEach(n => n.destroy());

                for (const network of wifiNetworks) {
                    const match = rNetworks.find(n => n.frequency === network.frequency && n.ssid === network.ssid && n.bssid === network.bssid);
                    if (match) {
                        match.lastIpcObject = network;
                    } else {
                        rNetworks.push(apComp.createObject(root, {
                            lastIpcObject: network
                        }));
                    }
                }
            }
        }
    }

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
