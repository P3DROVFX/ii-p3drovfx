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
 * Parameters of the ii Vitals conditions (`vitalsSleep`, `vitalsEnergy`,
 * `vitalsStepGoal`). `row` is the TriggerRow this form unfolds from; every change
 * goes back through it.
 */
ColumnLayout {
    id: form
    required property var row

    spacing: 10

    readonly property string type: String(row.trigger.type ?? "")
    // Sleep durations are kept in minutes and typed in hours.
    readonly property bool hours: form.type === "vitalsSleep" && row.trigger.metric !== "score"

    FormChoice {
        visible: form.type === "vitalsSleep"
        current: row.trigger.metric === "score" ? "score" : "duration"
        // The two scales differ, so a switch starts from the new metric's default.
        onPicked: v => form.row.set({ metric: v, below: null, above: null })
        options: [
            { displayName: Translation.tr("Duration"), value: "duration" },
            { displayName: Translation.tr("Sleep score"), value: "score" }
        ]
    }

    RowLayout {
        visible: form.type !== "vitalsStepGoal"
        spacing: 10

        FormLabel {
            text: Translation.tr("Below")
        }

        NumberField {
            value: row.trigger.below
            onCommitted: v => row.set({ below: v })
        }

        FormLabel {
            text: Translation.tr("Above")
        }

        NumberField {
            value: row.trigger.above
            onCommitted: v => row.set({ above: v })
        }

        FormHint {
            text: form.hours ? Translation.tr("Hours · leave one empty") : Translation.tr("0–100 · leave one empty")
        }
    }

    FormHint {
        text: !VitalsService.enabled ? Translation.tr("Needs ii Vitals, which is off.")
            : form.type === "vitalsSleep" ? Translation.tr("The main night that ended today, once the phone has synced it.")
            : form.type === "vitalsEnergy" ? Translation.tr("Today's score, once the phone has worked it out in the morning.")
            : (VitalsService.meta?.goals?.steps ?? 0) > 0
                ? Translation.tr("The phone's goal is %1 steps. Steps sync every 10 minutes, so this turns on within about that.")
                    .arg(VitalsTypes.format("steps", VitalsService.meta.goals.steps))
                : Translation.tr("The phone has not sent a step goal yet.")
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
            text: field.value === null || field.value === undefined ? ""
                : form.hours ? String(Math.round(field.value / 6) / 10) : String(field.value)
            color: ClockStyle.colOnSurface
            font.family: ClockStyle.fontMain
            font.variableAxes: ClockStyle.axesDigitsBold
            font.pixelSize: ClockStyle.textLarge + 1
            validator: form.hours ? hoursValidator : scoreValidator
            onEditingFinished: {
                const typed = input.text.trim().replace(",", ".");
                const next = typed.length ? (form.hours ? Math.round(Number(typed) * 60) : Number(typed)) : null;
                if (next !== field.value)
                    field.committed(next);
            }
        }
    }

    // Not a DoubleValidator: that follows the locale, and "6.5" fails where the
    // decimal sign is a comma.
    RegularExpressionValidator {
        id: hoursValidator
        regularExpression: /^(1?\d|2[0-4])([.,]\d)?$/
    }

    IntValidator {
        id: scoreValidator
        bottom: 0
        top: 100
    }
}
