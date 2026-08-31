pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking as QNet
import qs.modules.common

/**
 * Live NetworkManager state, straight from Quickshell's native D-Bus backend.
 *
 * Read only on purpose: nothing here polls and nothing here parses text, so
 * signal strength, connectivity and per-network state stay correct without a
 * timer. Writes that a settings dictionary is needed for go through
 * NetworkCommands, and Network is the facade the rest of the shell binds to.
 */
Singleton {
    id: root

    readonly property bool backendAvailable: QNet.Networking.backend === QNet.NetworkBackendType.NetworkManager

    // Devices show up a second or two after the shell starts. Latch readiness so
    // consumers can hold onto their startup values instead of flashing "no
    // adapter", and so a device disappearing later never sends them back there.
    property bool ready: false

    readonly property var devices: QNet.Networking.devices?.values ?? []
    onDevicesChanged: if (root.devices.length > 0) root.ready = true

    readonly property var wifiDevices: root.devices.filter(d => d.type === QNet.DeviceType.Wifi)
    readonly property var wiredDevices: root.devices.filter(d => d.type === QNet.DeviceType.Wired)
    readonly property bool hasWifiDevice: root.wifiDevices.length > 0
    readonly property bool hasWiredDevice: root.wiredDevices.length > 0

    readonly property var wifiDevice: root.wifiDevices.find(d => d.connected) ?? (root.wifiDevices[0] ?? null)
    readonly property var wiredDevice: root.wiredDevices.find(d => d.connected) ?? (root.wiredDevices[0] ?? null)
    readonly property string wifiInterface: root.wifiDevice?.name ?? ""
    readonly property string wiredInterface: root.wiredDevice?.name ?? ""

    // NetworkDevice.address is the hardware address, not an IP. Addressing comes
    // from NetworkCommands, which has to ask nmcli for it.
    readonly property string wifiMac: root.wifiDevice?.address ?? ""
    readonly property string wiredMac: root.wiredDevice?.address ?? ""

    readonly property bool wifiEnabled: QNet.Networking.wifiEnabled
    readonly property bool wifiHardwareEnabled: QNet.Networking.wifiHardwareEnabled
    readonly property bool scannerEnabled: root.wifiDevice?.scannerEnabled ?? false
    readonly property int wifiMode: root.wifiDevice?.mode ?? QNet.WifiDeviceMode.Unknown
    readonly property bool accessPointMode: root.wifiMode === QNet.WifiDeviceMode.AccessPoint

    readonly property int connectivity: QNet.Networking.connectivity
    readonly property bool canCheckConnectivity: QNet.Networking.canCheckConnectivity
    readonly property bool captivePortal: root.canCheckConnectivity && root.connectivity === QNet.NetworkConnectivity.Portal
    // Connectivity reads Unknown until the first check lands, and calling that
    // limited would report every cold start as a broken connection.
    readonly property bool limited: root.canCheckConnectivity && (root.connectivity === QNet.NetworkConnectivity.Portal || root.connectivity === QNet.NetworkConnectivity.Limited)

    readonly property var wifiNetworks: root.wifiDevice?.networks?.values ?? []
    readonly property var activeWifiNetwork: root.wifiNetworks.find(n => n.connected) ?? null
    readonly property var wiredNetwork: root.wiredDevice?.network ?? null

    readonly property bool wifiConnected: root.wifiDevice?.connected ?? false
    readonly property bool wifiConnecting: (root.wifiDevice?.state ?? QNet.ConnectionState.Unknown) === QNet.ConnectionState.Connecting
    readonly property bool wiredConnected: root.wiredDevices.some(d => d.connected)
    readonly property bool wiredHasLink: root.wiredDevices.some(d => d.hasLink === true)
    readonly property int wiredLinkSpeed: root.wiredDevice?.linkSpeed ?? 0

    function setWifiEnabled(enabled: bool): void {
        QNet.Networking.wifiEnabled = enabled;
    }

    function setScannerEnabled(enabled: bool): void {
        if (root.wifiDevice)
            root.wifiDevice.scannerEnabled = enabled;
    }

    function checkConnectivity(): void {
        QNet.Networking.checkConnectivity();
    }

    function findNetwork(ssid: string): var {
        return root.wifiNetworks.find(n => n.name === ssid) ?? null;
    }

    function isEnterprise(security: int): bool {
        return security === QNet.WifiSecurityType.Wpa2Eap || security === QNet.WifiSecurityType.WpaEap || security === QNet.WifiSecurityType.Wpa3SuiteB192 || security === QNet.WifiSecurityType.DynamicWep || security === QNet.WifiSecurityType.Leap;
    }

    // NetworkManager reports an open access point with no security flags at all,
    // which the backend maps to Unknown rather than Open.
    function isSecure(security: int): bool {
        return security !== QNet.WifiSecurityType.Open && security !== QNet.WifiSecurityType.Owe && security !== QNet.WifiSecurityType.Unknown;
    }

    function securityLabel(security: int): string {
        switch (security) {
        case QNet.WifiSecurityType.Wpa3SuiteB192:
            return "WPA3 Suite-B 192";
        case QNet.WifiSecurityType.Sae:
            return "WPA3";
        case QNet.WifiSecurityType.Wpa2Eap:
            return "WPA2 802.1X";
        case QNet.WifiSecurityType.Wpa2Psk:
            return "WPA2";
        case QNet.WifiSecurityType.WpaEap:
            return "WPA 802.1X";
        case QNet.WifiSecurityType.WpaPsk:
            return "WPA";
        case QNet.WifiSecurityType.StaticWep:
            return "WEP";
        case QNet.WifiSecurityType.DynamicWep:
            return "Dynamic WEP";
        case QNet.WifiSecurityType.Leap:
            return "LEAP";
        case QNet.WifiSecurityType.Owe:
            return "OWE";
        default:
            return "";
        }
    }

    function connectivityLabel(value: int): string {
        switch (value) {
        case QNet.NetworkConnectivity.None:
            return Translation.tr("No internet access");
        case QNet.NetworkConnectivity.Portal:
            return Translation.tr("Sign-in required");
        case QNet.NetworkConnectivity.Limited:
            return Translation.tr("Limited connectivity");
        case QNet.NetworkConnectivity.Full:
            return Translation.tr("Connected");
        default:
            return Translation.tr("Checking connection");
        }
    }

    function failReasonLabel(reason: int): string {
        switch (reason) {
        case QNet.ConnectionFailReason.NoSecrets:
            return Translation.tr("Wrong password");
        case QNet.ConnectionFailReason.WifiClientDisconnected:
            return Translation.tr("The network dropped the connection");
        case QNet.ConnectionFailReason.WifiClientFailed:
            return Translation.tr("The network refused the connection");
        case QNet.ConnectionFailReason.WifiAuthTimeout:
            return Translation.tr("Authentication timed out");
        case QNet.ConnectionFailReason.WifiNetworkLost:
            return Translation.tr("The network went out of range");
        default:
            return Translation.tr("Could not connect");
        }
    }
}
