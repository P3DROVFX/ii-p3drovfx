pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `bedtime` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.phase
        onPicked: v => row.set({ phase: v })
        options: [
            { displayName: Translation.tr("Wind-down and after"), value: "either" },
            { displayName: Translation.tr("Winding down"), value: "windDown" },
            { displayName: Translation.tr("Past bedtime"), value: "bedtime" }
        ]
    }

    FormHint {
        text: BedtimeService.enabled
            ? Translation.tr("Bedtime is %1, wind-down starts %2 min before.").arg(BedtimeService.targetTime).arg(BedtimeService.windDownMinutes)
            : Translation.tr("Bedtime is off. Turn it on in the Clock app's Bedtime tab.")
    }
}
