pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `bluetooth` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.connected === false ? "off" : "on"
        onPicked: v => row.set({ connected: v === "on" })
        options: [
            { displayName: Translation.tr("Connected"), value: "on" },
            { displayName: Translation.tr("Disconnected"), value: "off" }
        ]
    }

    ChipInput {
        Layout.fillWidth: true
        values: row.trigger.devices
        placeholder: Translation.tr("Device address — empty means any device")
        display: v => ModeUi.bluetoothName(v)
        suggestions: Array.from(BluetoothStatus.connectedDevices ?? [])
            .concat(Array.from(BluetoothStatus.pairedButNotConnectedDevices ?? []))
            .map(d => ({ label: d.name, value: String(d.address).toUpperCase() }))
        onChanged: list => row.set({ devices: list })
    }
}
