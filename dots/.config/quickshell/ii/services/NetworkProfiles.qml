pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * The saved NetworkManager profiles, as a list the settings page can bind to.
 *
 * NetworkManager's settings service is not part of Quickshell's networking
 * backend, so profiles are read through nmcli. The list refreshes after the
 * writes this shell makes rather than on a timer, plus once more a moment
 * later: activating a profile reports the old ACTIVE flag for a second or two.
 */
Singleton {
    id: root

    property var profiles: []
    property bool loading: false
    property bool loadedOnce: false
    // Which profile the editor sub-page opens on. Empty means it is creating a
    // new one, since a sub-page URL cannot carry an argument.
    property string editUuid: ""

    readonly property var wifiProfiles: root.profiles.filter(entry => entry.type === "802-11-wireless")
    readonly property var wiredProfiles: root.profiles.filter(entry => entry.type === "802-3-ethernet")

    function profileByUuid(uuid: string): var {
        return root.profiles.find(entry => entry.uuid === uuid) ?? null;
    }

    function profileForSsid(ssid: string): var {
        return root.wifiProfiles.find(entry => entry.name === ssid) ?? null;
    }

    function typeLabel(type: string): string {
        switch (type) {
        case "802-11-wireless":
            return Translation.tr("Wi-Fi");
        case "802-3-ethernet":
            return Translation.tr("Wired");
        case "bluetooth":
            return Translation.tr("Bluetooth");
        case "vpn":
        case "wireguard":
            return Translation.tr("VPN");
        case "loopback":
            return Translation.tr("Loopback");
        default:
            return type;
        }
    }

    function typeIcon(type: string): string {
        switch (type) {
        case "802-11-wireless":
            return "wifi";
        case "802-3-ethernet":
            return "lan";
        case "bluetooth":
            return "bluetooth";
        case "vpn":
        case "wireguard":
            return "vpn_key";
        default:
            return "settings_ethernet";
        }
    }

    function refresh(): void {
        root.loading = true;
        NetworkCommands.readProfiles(rows => {
            root.loading = false;
            root.loadedOnce = true;
            root.profiles = rows.sort((a, b) => {
                if (a.active !== b.active)
                    return a.active ? -1 : 1;
                return b.timestamp - a.timestamp;
            });
        });
    }

    // Every write refreshes twice: once for the profile list itself, and once
    // after the connection has had time to come up or go down.
    function afterWrite(callback): var {
        return (code, out, err) => {
            root.refresh();
            settleTimer.restart();
            if (callback)
                callback(code, out, err);
        };
    }

    function activate(uuid: string, callback = null): void {
        NetworkCommands.activateProfileUuid(uuid, root.afterWrite(callback));
    }

    function deactivate(uuid: string, callback = null): void {
        NetworkCommands.deactivateProfileUuid(uuid, root.afterWrite(callback));
    }

    function forget(uuid: string, callback = null): void {
        NetworkCommands.deleteProfileUuid(uuid, root.afterWrite(callback));
    }

    function setAutoconnect(uuid: string, enabled: bool, callback = null): void {
        NetworkCommands.setAutoconnectUuid(uuid, enabled, root.afterWrite(callback));
    }

    function readSettings(uuid: string, callback): void {
        NetworkCommands.readProfileSettings(uuid, callback);
    }

    function save(uuid: string, settings: var, secretKey = "", secret = "", callback = null): void {
        NetworkCommands.modifyProfileWithSecret(uuid, secretKey, secret, settings, root.afterWrite(callback));
    }

    function removeSetting(uuid: string, setting: string, callback = null): void {
        NetworkCommands.removeSetting(uuid, setting, callback);
    }

    function create(name: string, ssid: string, settings: var, secretKey = "", secret = "", callback = null): void {
        NetworkCommands.addWifiProfile(name, ssid, settings, secretKey, secret, root.afterWrite(callback));
    }

    function createWired(name: string, ifname: string, settings: var, secretKey = "", secret = "", callback = null): void {
        NetworkCommands.addWiredProfile(name, ifname, settings, secretKey, secret, root.afterWrite(callback));
    }

    Timer {
        id: settleTimer
        interval: 1500
        onTriggered: root.refresh()
    }

    Connections {
        target: NetworkState

        function onActiveWifiNetworkChanged(): void {
            settleTimer.restart();
        }

        // A cable going in or out activates or drops a profile without this
        // shell asking for it, and the list would otherwise stay as it was.
        function onWiredConnectedChanged(): void {
            settleTimer.restart();
        }
    }

    Component.onCompleted: root.refresh()
}
