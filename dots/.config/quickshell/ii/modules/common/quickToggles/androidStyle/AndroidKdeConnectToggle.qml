import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets
import QtQuick

AndroidQuickToggleButton {
    id: root

    toggleModel: KdeConnectToggle {}

    readonly property var device: KdeConnectService.activeDevice
    readonly property bool serviceEnabled: KdeConnectService.serviceEnabled
    readonly property bool connected: KdeConnectService.serviceEnabled && KdeConnectService.activeReachable
    readonly property bool hasBattery: root.connected && (root.device?.charge ?? -1) >= 0

    expandedTitle: !root.serviceEnabled ? Translation.tr("KDE Connect off")
        : root.connected ? (KdeConnectService.activeDeviceDisplayName || root.device?.name || Translation.tr("Device"))
        : Translation.tr("No devices")
    expandedStatus: root.hasBattery
        ? Math.round(root.device.charge) + Translation.tr("% battery") + (root.device.charging ? " · " + Translation.tr("Charging") : "")
        : ""
    expandedSurfaceColor: root.connected
        ? (root.toggled ? Appearance.colors.colPrimary : Appearance.colors.colLayer3)
        : (root.serviceEnabled ? Appearance.colors.colLayer3 : Appearance.colors.colSurfaceContainerLow)
    expandedSymbolColor: root.connected
        ? (root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3)
        : (root.serviceEnabled ? Appearance.colors.colOnLayer3 : Appearance.colors.colOnSurfaceVariant)
}
