pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import qs.modules.ii.clock.components
import QtQuick
import QtQuick.Layouts
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `schedule` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    readonly property var sun: ({ sunrise: Weather.data?.sunrise ?? "", sunset: Weather.data?.sunset ?? "" })
    readonly property int fromMin: ModeSchema.timeToMinutes(row.trigger.from, sun)
    readonly property int toMin: ModeSchema.timeToMinutes(row.trigger.to, sun)
    readonly property bool usesSun: ModeSchema.SUN_TOKENS.indexOf(row.trigger.from) !== -1
        || ModeSchema.SUN_TOKENS.indexOf(row.trigger.to) !== -1

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("From")
        }

        SunTimeField {
            value: row.trigger.from
            title: Translation.tr("Starts at")
            onCommitted: v => row.set({ from: v })
        }

        FormLabel {
            text: Translation.tr("to")
        }

        SunTimeField {
            value: row.trigger.to
            title: Translation.tr("Ends at")
            onCommitted: v => row.set({ to: v })
        }

        StyledText {
            visible: fromMin >= 0 && toMin >= 0 && fromMin >= toMin
            text: Translation.tr("overnight")
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }
    }

    FormHint {
        visible: usesSun
        text: fromMin >= 0 && toMin >= 0
            ? Translation.tr("Today: sunrise %1, sunset %2 — from the weather widget's location.")
                .arg(Weather.data.sunrise).arg(Weather.data.sunset)
            : Translation.tr("Sunrise and sunset come from the weather widget; nothing has loaded yet, "
                + "so the window stays closed.")
    }

    // The clock's repeat-day chips. The trigger stores ISO days (1 Monday … 7 Sunday);
    // the chips index days like Date.getDay() (0 Sunday), so 7 maps to 0 and back. The
    // last day left cannot be switched off.
    ClockDayChips {
        Layout.fillWidth: true
        Layout.maximumWidth: 380
        chipSize: 36
        days: {
            const on = [false, false, false, false, false, false, false];
            for (const d of ModeSchema.toArray(row.trigger.days))
                on[Number(d) % 7] = true;
            return on;
        }
        onToggled: day => {
            const iso = day === 0 ? 7 : day;
            const days = ModeSchema.toArray(row.trigger.days).map(Number);
            const idx = days.indexOf(iso);
            if (idx === -1)
                days.push(iso);
            else if (days.length > 1)
                days.splice(idx, 1);
            row.set({ days: days.sort((a, b) => a - b) });
        }
    }

    // A clock time, or one of the two sun tokens.
    component SunTimeField: RowLayout {
        id: sunField
        property string value: "00:00"
        property string title: ""
        signal committed(string value)
        readonly property bool isSun: ModeSchema.SUN_TOKENS.indexOf(sunField.value) !== -1
        spacing: 6

        TimeField {
            visible: !sunField.isSun
            pickTitle: sunField.title
            value: sunField.isSun ? "00:00" : sunField.value
            onCommitted: v => sunField.committed(v)
        }

        FormChoice {
            Layout.fillWidth: false
            current: sunField.isSun ? sunField.value : "clock"
            onPicked: v => {
                if (v === "clock")
                    sunField.committed(sunField.isSun ? "08:00" : sunField.value);
                else
                    sunField.committed(v);
            }
            options: [
                { displayName: Translation.tr("Time"), value: "clock" },
                { displayName: Translation.tr("Sunrise"), value: "sunrise" },
                { displayName: Translation.tr("Sunset"), value: "sunset" }
            ]
        }
    }
}
