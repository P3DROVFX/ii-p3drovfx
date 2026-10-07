import QtQuick
import qs
import qs.services
import qs.modules.common

/*
 * The Phone widgets' view of the active KDE Connect phone and of its scrcpy
 * mirror, with the same actions as the dock's phone button: mirror (or focus
 * the running one), stop, send files, send the clipboard. A send answers with
 * a short "sent" beat the widgets show on the key.
 */
QtObject {
    id: root

    property bool enabled: true

    readonly property string deviceId: KdeConnectService.activeDeviceId
    readonly property var device: KdeConnectService.activeDevice
    readonly property bool hasDevice: root.deviceId !== "" && KdeConnectService.activeReachable
    readonly property string name: KdeConnectService.activeDeviceDisplayName || Translation.tr("No phone")
    readonly property int charge: root.device?.charge ?? -1
    readonly property bool charging: root.device?.charging === true
    readonly property string imageSource: BluetoothDeviceImages.phoneImageFor(KdeConnectService.activeDeviceDisplayName, root.device?.name ?? "")

    readonly property bool mirrorAvailable: PhoneScrcpyService.available || KdeConnectService.scrcpyAvailable
    readonly property bool mirrorRunning: PhoneScrcpyService.mirrorRunning || KdeConnectService.scrcpyRunning
    readonly property bool mirrorLaunching: PhoneScrcpyService.mirrorLaunching || KdeConnectService.scrcpyLaunching
    readonly property bool canMirror: root.enabled && root.hasDevice && root.mirrorAvailable

    readonly property string status: {
        if (!KdeConnectService.available)
            return Translation.tr("KDE Connect is off");
        if (!root.hasDevice)
            return Translation.tr("Not connected");
        if (!root.mirrorAvailable)
            return Translation.tr("scrcpy unavailable");
        if (root.mirrorRunning)
            return Translation.tr("Mirroring");
        if (root.mirrorLaunching)
            return Translation.tr("Starting mirror…");
        if (!KdeConnectService.adbReachable)
            return Translation.tr("Connected · no ADB");
        return Translation.tr("Connected");
    }

    // The last send, for a beat ("clipboard").
    property string sent: ""
    property Timer sentTimer: Timer {
        interval: 1800
        onTriggered: root.sent = ""
    }

    function mirror() {
        if (!root.canMirror)
            return;
        if (root.mirrorRunning) {
            PhoneScrcpyService.focusMirror();
            KdeConnectService.focusScrcpyWindow();
            return;
        }
        if (!root.mirrorLaunching)
            PhoneScrcpyService.openMirrorWindow();
    }

    function stopMirror() {
        if (root.enabled)
            PhoneScrcpyService.stopMirroring();
    }

    function sendFile() {
        if (!root.enabled || !root.hasDevice)
            return;
        // The file picker that opens is its own feedback.
        KdeConnectService.sendFile(root.deviceId);
    }

    function sendClipboard() {
        if (!root.enabled || !root.hasDevice)
            return;
        KdeConnectService.sendClipboard(root.deviceId);
        root.sent = "clipboard";
        root.sentTimer.restart();
    }

    function ring() {
        if (root.enabled && root.hasDevice)
            KdeConnectService.findMyPhone(root.deviceId);
    }
}
