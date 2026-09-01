pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `weather` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    StyledComboBox {
        Layout.preferredWidth: 200
        model: [
            Translation.tr("Any weather"), Translation.tr("Clear"), Translation.tr("Cloudy"), Translation.tr("Fog"),
            Translation.tr("Rain"), Translation.tr("Snow"), Translation.tr("Storm")
        ]
        currentIndex: Math.max(0, ["any", "clear", "cloudy", "fog", "rain", "snow", "storm"].indexOf(row.trigger.kind))
        onActivated: index => row.set({ kind: ["any", "clear", "cloudy", "fog", "rain", "snow", "storm"][index] })
    }

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("Colder than")
        }

        TempField {
            value: row.trigger.tempBelow
            onCommitted: v => row.set({ tempBelow: v })
        }

        FormLabel {
            text: Translation.tr("Warmer than")
        }

        TempField {
            value: row.trigger.tempAbove
            onCommitted: v => row.set({ tempAbove: v })
        }

        FormHint {
            text: Translation.tr("In the weather widget's unit · leave empty to ignore")
        }
    }

    FormHint {
        text: (Weather.data?.wDesc ?? "").length
            ? Translation.tr("Now in %1: %2, %3").arg(Weather.data.city).arg(Weather.data.wDesc).arg(Weather.data.temp)
            : Translation.tr("Needs the weather widget's location; nothing has loaded yet.")
    }

    component TempField: Rectangle {
        id: field
        property var value: null
        signal committed(var value)

        implicitWidth: 72
        implicitHeight: 36
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer3
        border.width: input.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary

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
            color: Appearance.colors.colOnLayer3
            font.family: Appearance.font.family.numbers
            validator: IntValidator {
                bottom: -100
                top: 150
            }
            onEditingFinished: {
                const next = input.text.trim().length ? Number(input.text) : null;
                if (next !== field.value)
                    field.committed(next);
            }
        }
    }
}
