import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarDashboard.quickToggles
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

QuickToggleButton {
    toggled: Network.wifiStatus !== "disabled"
    buttonIcon: Network.materialSymbol
    onClicked: Network.toggleWifi()
    altAction: () => {
        GlobalStates.openSettingsPage("network", "", Network.ethernet ? "Ethernet ports" : "Wi-Fi")
        GlobalStates.sidebarRightOpen = false
    }
    StyledToolTip {
        text: Translation.tr("%1 | Right-click to configure").arg(Network.networkName)
    }
}
