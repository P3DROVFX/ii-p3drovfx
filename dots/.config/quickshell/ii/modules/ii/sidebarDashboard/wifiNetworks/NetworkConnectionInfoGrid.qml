import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "../../bar/shared/cards"

ColumnLayout {
    id: root

    readonly property bool wired: Network.ethernet
    readonly property bool connected: root.wired || Network.wifiStatus === "connected"
    readonly property string interfaceName: Network.activeInterface

    Layout.fillWidth: true
    Layout.topMargin: 16
    spacing: 6
    visible: root.connected

    function transferRate(megabitsPerSecond: real): string {
        const value = Math.max(0, Number(megabitsPerSecond) || 0);
        if (value >= 10)
            return Math.round(value) + " Mb/s";
        if (value >= 1)
            return value.toFixed(1) + " Mb/s";
        return Math.round(value * 1000) + " Kb/s";
    }

    StyledText {
        Layout.fillWidth: true
        font.pixelSize: Appearance.font.pixelSize.normal
        font.bold: true
        color: Appearance.colors.colSubtext
        text: Translation.tr("Connection details")
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 6
        rowSpacing: 6

        MetricCard {
            elideText: true
            title: Translation.tr("Network")
            symbol: "router"
            value: Network.networkName
            accentColor: Appearance.colors.colPrimaryContainer
            symbolColor: Appearance.colors.colOnPrimaryContainer
        }

        MetricCard {
            elideText: true
            title: Translation.tr("Transport")
            symbol: root.wired ? "lan" : "wifi"
            value: root.wired ? Translation.tr("Ethernet") : Translation.tr("Wi-Fi")
            accentColor: Appearance.colors.colSecondaryContainer
            symbolColor: Appearance.colors.colOnSecondaryContainer
        }

        MetricCard {
            elideText: true
            title: Translation.tr("Download")
            symbol: "download"
            value: root.transferRate(NetworkSpeed.downloadSpeed)
            accentColor: Appearance.colors.colTertiaryContainer
            symbolColor: Appearance.colors.colOnTertiaryContainer
        }

        MetricCard {
            elideText: true
            title: Translation.tr("Upload")
            symbol: "upload"
            value: root.transferRate(NetworkSpeed.uploadSpeed)
            accentColor: Appearance.colors.colPrimaryContainer
            symbolColor: Appearance.colors.colOnPrimaryContainer
        }

        MetricCard {
            elideText: true
            title: root.wired ? Translation.tr("Link") : Translation.tr("Signal")
            symbol: root.wired ? "settings_ethernet" : "network_wifi"
            value: root.wired
                ? (NetworkState.wiredLinkSpeed > 0
                    ? Translation.tr("%1 Mb/s").arg(String(NetworkState.wiredLinkSpeed))
                    : Translation.tr("Connected"))
                : Translation.tr("%1%").arg(String(Network.networkStrength))
            accentColor: Appearance.colors.colSecondaryContainer
            symbolColor: Appearance.colors.colOnSecondaryContainer
        }

        MetricCard {
            elideText: true
            title: Translation.tr("Address")
            symbol: "language"
            value: Network.ipAddress.length > 0 ? Network.ipAddress : "—"
            accentColor: Appearance.colors.colTertiaryContainer
            symbolColor: Appearance.colors.colOnTertiaryContainer
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.interfaceName.length > 0
        elide: Text.ElideRight
        text: Translation.tr("Interface: %1").arg(root.interfaceName)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
