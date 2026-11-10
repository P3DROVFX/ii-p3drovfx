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
 * Parameters of the `alarmSoon` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.source
        onPicked: v => row.set({ source: v })
        options: [
            { displayName: Translation.tr("Any alarm"), value: "any" },
            { displayName: Translation.tr("This PC"), value: "pc" },
            { displayName: Translation.tr("The phone"), value: "phone" }
        ]
    }

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("Within")
        }

        ClockStepper {
            from: 1
            to: 1440
            stepSize: 5
            value: row.trigger.minutes
            onMoved: v => row.set({ minutes: v })
        }

        FormLabel {
            text: Translation.tr("minutes")
        }
    }

    FormHint {
        text: PhoneAlarmService.nextAt
            ? Translation.tr("Phone's next alarm: %1").arg(Qt.formatDateTime(PhoneAlarmService.nextAt, "ddd HH:mm"))
            : Translation.tr("The phone's alarm is read over ADB while the phone is connected.")
    }
}
