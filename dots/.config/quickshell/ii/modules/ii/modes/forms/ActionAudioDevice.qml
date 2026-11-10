pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

/**
 * Parameters of the `audioOutput` / `audioInput` actions: one of the
 * devices PipeWire knows right now. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    id: deviceCol
    required property var row

    spacing: 10

    readonly property bool input: row.type === "audioInput"
    readonly property var devices: Array.from(deviceCol.input ? Audio.inputDevices : Audio.outputDevices)
    readonly property string pickedName: String(row.obj.name ?? "")
    readonly property var defaultNode: deviceCol.input ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink

    function labelOf(node) {
        return node.description ?? node.nickname ?? node.name ?? "";
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: deviceCol.devices

            // The picked device fills and carries a check; the current default is
            // marked with a dot.
            delegate: ClockChip {
                id: chip
                required property var modelData
                readonly property bool on: chip.modelData.name === deviceCol.pickedName

                height_: 32
                selected: chip.on
                symbol: chip.on ? "check" : (chip.modelData === deviceCol.defaultNode ? "radio_button_checked" : "")
                label: deviceCol.labelOf(chip.modelData)
                onClicked: row.setValue({ name: chip.modelData.name, label: deviceCol.labelOf(chip.modelData) })

                StyledToolTip {
                    text: chip.modelData.name
                }
            }
        }
    }

    FormHint {
        visible: deviceCol.pickedName.length > 0 && !deviceCol.devices.some(d => d.name === deviceCol.pickedName)
        text: Translation.tr("\"%1\" is not connected right now; it is matched again when the action runs")
            .arg(String(row.obj.label ?? deviceCol.pickedName))
    }

    FormHint {
        text: deviceCol.input
            ? Translation.tr("Becomes the default microphone; the previous one comes back at the end")
            : Translation.tr("Becomes the default output; the previous one comes back at the end")
    }
}
