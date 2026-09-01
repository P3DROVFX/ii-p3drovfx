pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
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

            delegate: RippleButton {
                id: chip
                required property var modelData
                readonly property bool on: chip.modelData.name === deviceCol.pickedName

                implicitHeight: 32
                implicitWidth: chipRow.implicitWidth + 22
                buttonRadius: Appearance.rounding.full
                colBackground: on ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                colBackgroundHover: on ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover
                colRipple: on ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active
                onClicked: row.setValue({ name: chip.modelData.name, label: deviceCol.labelOf(chip.modelData) })

                StyledToolTip {
                    text: chip.modelData.name
                }

                contentItem: RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        visible: chip.on || chip.modelData === deviceCol.defaultNode
                        text: chip.on ? "check" : "radio_button_checked"
                        iconSize: 16
                        color: chip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                    }

                    StyledText {
                        text: deviceCol.labelOf(chip.modelData)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: chip.on ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
                    }
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
