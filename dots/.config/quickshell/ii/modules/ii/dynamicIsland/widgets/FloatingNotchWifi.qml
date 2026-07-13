import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

RowLayout {
    id: root
    anchors.fill: parent
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    spacing: 8

    // Access local ssid from DynamicIslandPanel
    readonly property string ssid: {
        var p = root.parent;
        while (p && !p.hasOwnProperty("wifiSsid")) {
            p = p.parent;
        }
        return p ? p.wifiSsid : "";
    }

    MaterialSymbol {
        Layout.alignment: Qt.AlignVCenter
        text: "wifi"
        iconSize: 16
        color: Appearance.colors.colPrimary
    }

    StyledText {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.bold: true
        color: Appearance.colors.colOnSurface
        text: Network.networkName !== "" ? Network.networkName : (root.ssid !== "" ? root.ssid : Translation.tr("Wi-Fi Connected"))
        elide: Text.ElideRight
        maximumLineCount: 1
        wrapMode: Text.NoWrap
    }
}
