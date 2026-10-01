pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `resource` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    readonly property bool isTemp: String(row.trigger.metric).endsWith("Temp")

    StyledComboBox {
        Layout.preferredWidth: 240
        model: [
            Translation.tr("CPU load"), Translation.tr("CPU temperature"),
            Translation.tr("GPU load"), Translation.tr("GPU temperature"),
            Translation.tr("Memory used"), Translation.tr("Swap used"), Translation.tr("Disk used")
        ]
        currentIndex: Math.max(0, ["cpuUsage", "cpuTemp", "gpuUsage", "gpuTemp", "memory", "swap", "disk"]
            .indexOf(row.trigger.metric))
        onActivated: index => row.set({
            metric: ["cpuUsage", "cpuTemp", "gpuUsage", "gpuTemp", "memory", "swap", "disk"][index]
        })
    }

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("Above")
        }

        NumberField {
            value: row.trigger.above
            onCommitted: v => row.set({ above: v })
        }

        FormLabel {
            text: Translation.tr("Below")
        }

        NumberField {
            value: row.trigger.below
            onCommitted: v => row.set({ below: v })
        }

        FormHint {
            text: isTemp ? Translation.tr("°C · leave one empty") : Translation.tr("% · leave one empty")
        }
    }

    FormHint {
        text: Translation.tr("Read every few seconds with 5 units of slack, so a value on the line does not flap.")
    }

    // A number on the clock's filled field surface; empty means "not set".
    component NumberField: Rectangle {
        id: field
        property var value: null
        signal committed(var value)

        implicitWidth: 80
        implicitHeight: 40
        radius: ClockStyle.radiusSmall
        color: input.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

        StyledTextInput {
            id: input
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            text: field.value === null || field.value === undefined ? "" : String(field.value)
            color: ClockStyle.colOnSurface
            font.family: ClockStyle.fontMain
            font.variableAxes: ClockStyle.axesDigitsBold
            font.pixelSize: ClockStyle.textLarge + 1
            validator: IntValidator {
                bottom: 0
                top: 1000
            }
            onEditingFinished: {
                const next = input.text.trim().length ? Number(input.text) : null;
                if (next !== field.value)
                    field.committed(next);
            }
        }
    }
}
