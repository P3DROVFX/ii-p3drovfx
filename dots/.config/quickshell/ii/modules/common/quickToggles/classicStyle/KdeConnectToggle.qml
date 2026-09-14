import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs
import QtQuick

QuickToggleButton {
    id: root

    readonly property bool serviceEnabled: KdeConnectService.serviceEnabled
    readonly property var device: KdeConnectService.activeDevice
    readonly property bool connected: KdeConnectService.serviceEnabled && KdeConnectService.activeReachable
    readonly property bool hasBattery: root.connected && (root.device?.charge ?? -1) >= 0
    readonly property string statusText: !root.serviceEnabled ? Translation.tr("Disabled")
        : root.connected ? (KdeConnectService.activeDeviceDisplayName || root.device?.name || Translation.tr("Device"))
        : Translation.tr("No devices")

    interactive: KdeConnectService.available
    toggled: root.serviceEnabled
    buttonIcon: !root.serviceEnabled ? "sync_disabled"
        : root.connected ? "phonelink"
        : "phonelink_off"
    onClicked: {
        Config.options.phone.kdeconnectEnabled = !root.serviceEnabled;
    }
    StyledToolTip {
        text: {
            if (!root.serviceEnabled)
                return Translation.tr("KDE Connect service is disabled | Right-click for options");
            if (root.connected && root.hasBattery)
                return Translation.tr("%1 · %2% battery | Right-click for options")
                    .arg(KdeConnectService.activeDeviceDisplayName).arg(String(Math.round(root.device.charge)));
            return Translation.tr("KDE Connect: %1 | Right-click for options").arg(KdeConnectService.statusText);
        }
    }
}
