import QtQuick
import qs.services
import qs.modules.common

QuickToggleModel {
    id: root
    name: Translation.tr("VPN")

    available: (Config.options?.vpn?.enabled ?? true) && VpnService.available
    toggled: (Config.options?.vpn?.enabled ?? true) && VpnService.displayActive
    // The connected server or profile instead of a bare "Active"; empty falls back to "Inactive".
    statusText: !toggled ? ""
        : VpnService.operationPending ? Translation.tr("Connecting…")
        : (VpnService.activeProfile || Translation.tr("Connected"))
    tooltipText: (Config.options?.vpn?.enabled ?? true)
        ? Translation.tr("VPN Connection: %1 | Right-click to manage profiles").arg(VpnService.statusText)
        : Translation.tr("VPN is disabled in Privacy settings")
    icon: VpnService.displayActive ? "key" : (VpnService.errorMessage ? "error" : "vpn_key")
    hasMenu: true

    mainAction: () => {
        if (Config.options?.vpn?.enabled ?? true)
            VpnService.toggleVpn()
    }
}
