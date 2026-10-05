import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    // An empty status falls back to "Active"/"Inactive" in the tile, which is
    // what a cable without a named profile used to show. Every state says what
    // the connection is instead.
    readonly property string connectionStatus: {
        if (NetworkState.accessPointMode)
            return Translation.tr("Hotspot");
        if (Network.ethernet)
            return Network.networkName || Translation.tr("Ethernet");
        if (NetworkState.wiredConnecting)
            return Translation.tr("Ethernet · Connecting");
        switch (Network.wifiStatus) {
        case "disabled":
            return Translation.tr("Wi-Fi off");
        case "connecting":
            return Translation.tr("Connecting");
        case "disconnected":
            return Translation.tr("Disconnected");
        case "limited":
            return Translation.tr("Limited");
        default:
            return Network.networkName || Translation.tr("Wi-Fi");
        }
    }

    name: Translation.tr("Internet")
    statusText: connectionStatus
    tooltipText: Translation.tr("%1 | Right-click to configure").arg(connectionStatus)
    icon: Network.materialSymbol

    // A cable or a running hotspot is a live connection even with the Wi-Fi radio off.
    toggled: Network.ethernet || NetworkState.accessPointMode || Network.wifiStatus !== "disabled"
    mainAction: () => Network.toggleWifi()
    hasMenu: true
}
