import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs
import QtQuick

QuickToggleButton {
    interactive: (Config.options?.tailscale?.enabled ?? true) && TailscaleService.available
    toggled: (Config.options?.tailscale?.enabled ?? true) && TailscaleService.active
    buttonIcon: TailscaleService.active ? "hub" : (TailscaleService.backendState === "NeedsLogin" ? "key" : "vpn_lock")
    onClicked: {
        if (Config.options?.tailscale?.enabled ?? true)
            TailscaleService.toggleTailscale()
    }
    StyledToolTip {
        text: (Config.options?.tailscale?.enabled ?? true)
            ? Translation.tr("Tailscale: %1 | Right-click for options").arg(TailscaleService.statusText)
            : Translation.tr("Tailscale is disabled in Privacy settings")
    }
}
