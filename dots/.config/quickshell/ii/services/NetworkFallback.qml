pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking as QNet
import "network/NmcliDeviceStatus.js" as Nmcli

/**
 * Wi-Fi and wired device state read from nmcli, for machines where Quickshell's
 * NetworkManager backend enumerates no adapter.
 *
 * The backend is the source of truth everywhere it works, and this stays asleep
 * there. It exists because the backend can come up with an empty device list on
 * a machine whose NetworkManager is perfectly healthy — a NetworkManager older
 * than the backend expects, or a backend that resolved before NetworkManager
 * was on the bus and cannot resolve again, since `Networking.backend` is
 * constant for the life of the process. The shell used to read everything from
 * nmcli and so never noticed; once it stopped, those machines lost Wi-Fi
 * outright — no adapter in the quick toggle, none in the settings page, nothing
 * to connect to — while `nmcli` kept working from a terminal.
 *
 * NetworkState reads this only where the backend has nothing of its own to say,
 * so no surface has to know which of the two answered.
 */
Singleton {
    id: root

    // Read off Networking directly rather than through NetworkState: that
    // singleton reads this one back, and the two would otherwise define each
    // other.
    readonly property var backendDevices: QNet.Networking.devices?.values ?? []
    readonly property bool backendHasWifi: root.backendDevices.some(d => d.type === QNet.DeviceType.Wifi)
    readonly property bool backendHasWired: root.backendDevices.some(d => d.type === QNet.DeviceType.Wired)

    /**
     * Devices arrive a second or two after the shell starts, so engaging on an
     * empty list would run nmcli on every machine at every start. Network's own
     * startup seed covers that window, and this takes over from it.
     */
    property bool graceElapsed: false
    readonly property bool active: root.graceElapsed && !root.backendHasWifi

    /** True once a probe has come back, whether or not it found anything. */
    property bool loaded: false
    /** True while nmcli answers at all, which is what "NetworkManager is up" means here. */
    property bool reachable: false

    property bool hasWifiDevice: false
    property string wifiInterface: ""
    property string wifiMac: ""
    // nmcli's own word: connected, connecting, disconnected, unavailable,
    // unmanaged.
    property string wifiState: ""
    property string wifiConnectionName: ""

    property bool hasWiredDevice: false
    property string wiredInterface: ""
    property string wiredMac: ""
    property string wiredState: ""
    property string wiredConnectionName: ""

    property bool radioEnabled: false
    property bool radioHardwareEnabled: true

    readonly property bool wifiConnected: root.wifiState === "connected"
    readonly property bool wifiConnecting: root.wifiState === "connecting"
    readonly property bool wiredConnected: root.wiredState === "connected"
    // A port with no cable in it reads "unavailable", which is the same thing
    // the backend's `hasLink` says with a boolean.
    readonly property bool wiredHasLink: root.hasWiredDevice && root.wiredState !== "unavailable"

    /** Emitted after every probe, so Network can refresh what it reads itself. */
    signal probed

    readonly property string kProbe: 'nmcli -t -f WIFI,WIFI-HW radio; echo ---; nmcli -t -e yes -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,GENERAL.HWADDR device show'

    function refresh(): void {
        if (!root.active)
            return;
        probeDebounce.restart();
    }

    function probe(): void {
        NetworkCommands.runScript(root.kProbe, [], "fallback", (code, out) => root.apply(code, out));
    }

    function apply(exitCode: int, text: string): void {
        root.loaded = true;
        root.reachable = exitCode === 0;
        if (exitCode !== 0) {
            // nmcli is the only thing left that could have answered, so a
            // failure here is NetworkManager being down rather than a device
            // going away, and clearing the adapter is the honest reading.
            root.hasWifiDevice = false;
            root.hasWiredDevice = false;
            root.probed();
            return;
        }
        const blocks = text.split("---");
        const radio = Nmcli.parseRadio(blocks[0] ?? "");
        root.radioEnabled = radio.enabled;
        root.radioHardwareEnabled = radio.hardwareEnabled;

        const devices = Nmcli.parseDevices(blocks[1] ?? "");
        const wifi = Nmcli.pickDevice(devices, "wifi");
        root.hasWifiDevice = wifi !== null;
        root.wifiInterface = wifi?.device ?? "";
        root.wifiMac = wifi?.mac ?? "";
        root.wifiState = wifi?.state ?? "";
        root.wifiConnectionName = wifi?.connection ?? "";

        const wired = Nmcli.pickDevice(devices, "ethernet");
        root.hasWiredDevice = wired !== null;
        root.wiredInterface = wired?.device ?? "";
        root.wiredMac = wired?.mac ?? "";
        root.wiredState = wired?.state ?? "";
        root.wiredConnectionName = wired?.connection ?? "";

        root.probed();
    }

    Timer {
        interval: 4000
        running: !root.graceElapsed
        onTriggered: root.graceElapsed = true
    }

    Timer {
        id: probeDebounce
        interval: 250
        onTriggered: root.probe()
    }

    /**
     * Polls only while nmcli is covering for a device the backend cannot see.
     * Everywhere else the single probe on start is enough to answer "is there
     * an adapter at all", and `nmcli monitor` — which Network already watches —
     * brings news of one appearing later through refresh().
     */
    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: root.active && (!root.loaded || root.hasWifiDevice || (root.hasWiredDevice && !root.backendHasWired))
        onTriggered: root.probe()
    }
}
