import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs
import QtQuick

QuickToggleButton {
    interactive: (Config.options?.vpn?.enabled ?? true) && VpnService.available
    toggled: (Config.options?.vpn?.enabled ?? true) && VpnService.displayActive
    buttonIcon: VpnService.displayActive ? "key" : (VpnService.errorMessage ? "error" : "vpn_key")
    onClicked: {
        if (Config.options?.vpn?.enabled ?? true)
            VpnService.toggleVpn()
    }
    StyledToolTip {
        text: (Config.options?.vpn?.enabled ?? true)
            ? Translation.tr("VPN: %1 | Right-click for options").arg(VpnService.statusText)
            : Translation.tr("VPN is disabled in Privacy settings")
    }
}
