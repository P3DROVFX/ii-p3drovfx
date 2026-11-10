import QtQuick
import Quickshell.Bluetooth
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Bluetooth")
    statusText: BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Not connected")
    tooltipText: Translation.tr("%1 | Right-click to configure").arg(
        (BluetoothStatus.firstActiveDevice?.name ?? Translation.tr("Bluetooth"))
        + (BluetoothStatus.activeDeviceCount > 1 ? ` +${BluetoothStatus.activeDeviceCount - 1}` : "")
    )
    icon: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"

    available: BluetoothStatus.available
    toggled: BluetoothStatus.enabled
    readonly property bool batteryKnown: BluetoothStatus.firstActiveDevice?.batteryAvailable ?? false
    heroLevel: batteryKnown ? BluetoothStatus.firstActiveDevice.battery : -1
    heroValue: batteryKnown ? String(Math.round(BluetoothStatus.firstActiveDevice.battery * 100)) : ""
    heroUnit: batteryKnown ? "%" : ""
    mainAction: () => {
        BluetoothStatus.toggle()
    }
    hasMenu: true
}
