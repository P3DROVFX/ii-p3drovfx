import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Column {
    property real maxListHeight: 250
    width: parent?.width ?? 0
    spacing: 0
    topPadding: 4

    StyledIndeterminateProgressBar {
        visible: Bluetooth.defaultAdapter?.discovering ?? false
        anchors { left: parent.left; right: parent.right }
    }

    ListView {
        width: parent.width
        height: Math.min(contentHeight, maxListHeight)
        clip: true
        spacing: 0
        model: ScriptModel { values: BluetoothStatus.friendlyDeviceList }
        delegate: BluetoothDeviceItem {
            required property var modelData
            device: modelData
            width: ListView.view?.width ?? 0
            buttonRadius: Appearance.rounding.small
            labelColor: Appearance.colors.colOnLayer3
        }
    }
}
