pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `pomodoro` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
FormChoice {
    required property var row

    current: row.trigger.phase
    onPicked: v => row.set({ phase: v })
    options: [
        { displayName: Translation.tr("Running"), value: "any" },
        { displayName: Translation.tr("In a focus lap"), value: "focus" },
        { displayName: Translation.tr("On a break"), value: "break" }
    ]
}
