pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking as QNet
import qs.services
import qs.modules.common

/**
 * Whether this machine can actually run a Wi-Fi hotspot, and the profile it
 * runs from.
 *
 * NetworkManager accepts a shared connection on a machine that cannot serve
 * one: sharing spawns dnsmasq, which is not a dependency of the package, and
 * the radio decides whether an access point may run beside the connection being
 * shared. Both are probed up front so the page can say what will not work
 * before anyone tries it, rather than leaving a hotspot that associates clients
 * and then hands them nothing.
 *
 * Everything the hotspot is lives in NetworkManager rather than in the shell's
 * own config, so the hotspot configured here is the one nmcli sees.
 */
Singleton {
    id: root

    readonly property string profileName: "ii-hotspot"

    property var capabilities: ({})
    property var dependencies: ({})
    property var combinations: ({
        known: false,
        concurrent: false,
        channels: 0
    })
    property bool environmentRead: false
    property bool capabilitiesRead: false
    property var profile: null
    property bool profileRead: false
    property var stations: []
    property bool busy: false
    property string lastError: ""

    readonly property bool probed: root.environmentRead && root.capabilitiesRead
    readonly property string interfaceName: NetworkState.wifiInterface

    readonly property bool apCapable: root.capabilities.ap === true
    readonly property bool band24Capable: root.capabilities["2ghz"] === true
    readonly property bool band5Capable: root.capabilities["5ghz"] === true
    readonly property bool dnsmasqAvailable: root.dependencies.dnsmasq === true
    readonly property bool firewallAvailable: root.dependencies.iptables === true
        || root.dependencies.nft === true
    readonly property bool iwAvailable: root.dependencies.iw === true

    // A radio that can hold one channel at a time has to put the access point
    // on whatever channel the client connection already uses, so the band is
    // not free to choose while that connection is up.
    readonly property bool sharedChannel: root.combinations.known && root.combinations.channels === 1
    // An unknown combination list is not a refusal: iw is missing, and the
    // honest answer is to let the attempt decide.
    readonly property bool concurrentCapable: !root.combinations.known || root.combinations.concurrent

    readonly property bool supported: NetworkState.hasWifiDevice && root.apCapable
    readonly property bool ready: root.supported && root.dnsmasqAvailable && root.firewallAvailable
    readonly property bool active: NetworkState.accessPointMode

    // What the hotspot would actually share. A second adapter is the good case;
    // sharing the one radio that is also serving the client connection is the
    // common one, and the reason the channel constraint above matters.
    readonly property var uplinkDevice: NetworkState.devices.find(device => device.connected
        && device.name !== root.interfaceName
        && (device.type === QNet.DeviceType.Wired || device.type === QNet.DeviceType.Wifi)) ?? null
    readonly property bool sharesOwnRadio: !root.uplinkDevice && NetworkState.wifiConnected
    readonly property string uplinkName: root.uplinkDevice?.name
        ?? (root.sharesOwnRadio ? root.interfaceName : "")

    function bandLabel(band: string): string {
        if (band === "bg")
            return Translation.tr("2.4 GHz");
        if (band === "a")
            return Translation.tr("5 GHz");
        return Translation.tr("Automatic");
    }

    function securityOf(keyMgmt: string): string {
        if (keyMgmt === "sae")
            return "sae";
        if (keyMgmt.length === 0)
            return "open";
        return "wpa-psk";
    }

    // nmcli puts the useful sentence on the first line and the D-Bus path on the
    // rest, and prefixes it with a word the page already says in its own voice.
    function errorText(text: string): string {
        const first = (text ?? "").trim().split("\n")[0] ?? "";
        return first.replace(/^Error:\s*/, "");
    }

    function probeEnvironment(): void {
        NetworkCommands.readHotspotDeps(deps => {
            root.dependencies = deps;
            NetworkCommands.readInterfaceCombinations(combos => {
                root.combinations = combos;
                root.environmentRead = true;
            });
        });
    }

    function probeDevice(): void {
        if (root.interfaceName.length === 0)
            return;
        NetworkCommands.readWifiCapabilities(root.interfaceName, caps => {
            root.capabilities = caps;
            root.capabilitiesRead = true;
        });
    }

    function refreshProfile(): void {
        NetworkCommands.readHotspotProfiles(rows => {
            root.profileRead = true;
            root.profile = rows.find(entry => entry.name === root.profileName) ?? (rows[0] ?? null);
        });
    }

    function refreshStations(): void {
        if (!root.active || !root.iwAvailable) {
            root.stations = [];
            return;
        }
        NetworkCommands.readStations(root.interfaceName, rows => root.stations = rows);
    }

    /**
     * The settings dictionary one hotspot profile is built from. `options` takes
     * ssid, security ("open", "wpa-psk", "sae"), band ("", "bg", "a") and
     * hidden.
     */
    function settingsFor(options: var): var {
        const settings = {
            "802-11-wireless.mode": "ap",
            "802-11-wireless.band": options.band ?? "",
            "802-11-wireless.hidden": options.hidden ? "yes" : "no",
            "ipv4.method": "shared",
            "ipv6.method": "ignore",
            "connection.autoconnect": "no"
        };
        if ((options.security ?? "wpa-psk") === "open")
            return settings;
        settings["802-11-wireless-security.key-mgmt"] = options.security === "sae" ? "sae" : "wpa-psk";
        // Left to itself NetworkManager will offer TKIP to anything that asks
        // for it, which drags the whole access point down to WPA1 rates.
        settings["802-11-wireless-security.proto"] = "rsn";
        settings["802-11-wireless-security.pairwise"] = "ccmp";
        settings["802-11-wireless-security.group"] = "ccmp";
        return settings;
    }

    function save(options: var, secret: string, startAfter: bool, callback = null): void {
        root.busy = true;
        root.lastError = "";
        const settings = root.settingsFor(options);
        const open = (options.security ?? "wpa-psk") === "open";
        if (!root.profile) {
            NetworkCommands.addHotspotProfile(root.profileName, options.ssid, root.interfaceName, settings,
                open ? "" : secret, (code, out, err) => {
                    // The new uuid is only ever reported in the success line.
                    const match = out.match(/\(([0-9a-fA-F-]{36})\)/);
                    root.afterSave(code, err, startAfter && match ? match[1] : "", callback);
                });
            return;
        }
        settings["802-11-wireless.ssid"] = options.ssid;
        // An empty key-mgmt is rejected rather than cleared, so an access point
        // that loses its password has to lose the whole security group.
        if (open)
            NetworkCommands.removeSetting(root.profile.uuid, "802-11-wireless-security");
        const uuid = root.profile.uuid;
        NetworkCommands.modifyProfileWithSecret(uuid, open ? "" : "802-11-wireless-security.psk", secret,
            settings, (code, out, err) => root.afterSave(code, err, startAfter ? uuid : "", callback));
    }

    function afterSave(code: int, err: string, startUuid: string, callback): void {
        root.refreshProfile();
        NetworkProfiles.refresh();
        if (code !== 0) {
            root.busy = false;
            root.lastError = root.errorText(err);
            if (callback)
                callback(false);
            return;
        }
        if (startUuid.length === 0) {
            root.busy = false;
            if (callback)
                callback(true);
            return;
        }
        root.start(startUuid, callback);
    }

    function start(uuid: string, callback = null): void {
        root.busy = true;
        root.lastError = "";
        NetworkCommands.activateProfileUuid(uuid, (code, out, err) => {
            root.busy = false;
            root.lastError = code === 0 ? "" : root.errorText(err);
            root.refreshProfile();
            NetworkProfiles.refresh();
            stationTimer.restart();
            if (callback)
                callback(code === 0);
        });
    }

    function stop(callback = null): void {
        if (!root.profile)
            return;
        root.busy = true;
        root.lastError = "";
        NetworkCommands.deactivateProfileUuid(root.profile.uuid, (code, out, err) => {
            root.busy = false;
            root.lastError = code === 0 ? "" : root.errorText(err);
            root.refreshProfile();
            NetworkProfiles.refresh();
            if (callback)
                callback(code === 0);
        });
    }

    function forget(callback = null): void {
        if (!root.profile)
            return;
        root.busy = true;
        NetworkCommands.deleteProfileUuid(root.profile.uuid, (code, out, err) => {
            root.busy = false;
            root.lastError = code === 0 ? "" : root.errorText(err);
            root.profile = null;
            root.refreshProfile();
            NetworkProfiles.refresh();
            if (callback)
                callback(code === 0);
        });
    }

    onInterfaceNameChanged: root.probeDevice()
    onActiveChanged: {
        root.refreshProfile();
        root.refreshStations();
    }

    // Stations come and go without announcing it, and there is no signal for
    // them; this only runs while the access point is actually up.
    Timer {
        id: stationTimer
        running: root.active && root.iwAvailable
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshStations()
    }

    Component.onCompleted: {
        root.probeEnvironment();
        root.probeDevice();
        root.refreshProfile();
    }
}
