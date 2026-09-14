import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions

QuickToggleModel {
    id: root

    readonly property bool serviceEnabled: KdeConnectService.serviceEnabled
    readonly property var device: KdeConnectService.activeDevice
    readonly property bool deviceConnected: KdeConnectService.serviceEnabled && KdeConnectService.activeReachable
    readonly property bool hasBattery: root.deviceConnected && (root.device?.charge ?? -1) >= 0
    readonly property string deviceLabel: KdeConnectService.activeDeviceDisplayName || root.device?.name || ""

    name: Translation.tr("KDE Connect")
    available: KdeConnectService.available
    toggled: root.serviceEnabled
    statusText: {
        if (!root.serviceEnabled)
            return Translation.tr("Disabled");
        if (root.deviceConnected) {
            const label = root.deviceLabel || Translation.tr("Device");
            return root.hasBattery ? label + " · " + Math.round(root.device.charge) + "%" : label;
        }
        return Translation.tr("No devices");
    }
    tooltipText: {
        if (!root.serviceEnabled)
            return Translation.tr("KDE Connect service is disabled | Right-click for options");
        if (root.deviceConnected && root.hasBattery)
            return Translation.tr("%1 · %2% battery | Right-click for options")
                .arg(root.deviceLabel).arg(String(Math.round(root.device.charge)));
        return Translation.tr("KDE Connect: %1 | Right-click for options").arg(root.statusText);
    }
    icon: !root.serviceEnabled ? "sync_disabled"
        : root.deviceConnected ? "phonelink"
        : "phonelink_off"
    hasMenu: true

    mainAction: () => {
        Config.options.phone.kdeconnectEnabled = !root.serviceEnabled;
    }
}
