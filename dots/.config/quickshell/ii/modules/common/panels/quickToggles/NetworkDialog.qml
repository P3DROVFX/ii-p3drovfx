import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Column {
    property real maxListHeight: 250
    width: parent?.width ?? 0
    spacing: 0
    topPadding: 4

    StyledIndeterminateProgressBar {
        visible: Network.wifiScanning
        anchors { left: parent.left; right: parent.right }
    }

    ListView {
        width: parent.width
        height: Math.min(contentHeight, maxListHeight)
        clip: true
        spacing: 0
        model: ScriptModel { values: Network.friendlyWifiNetworks }
        delegate: WifiNetworkItem {
            required property var modelData
            wifiNetwork: modelData
            width: ListView.view?.width ?? 0
            buttonRadius: Appearance.rounding.small
            labelColor: Appearance.colors.colOnLayer3
        }
    }
}
