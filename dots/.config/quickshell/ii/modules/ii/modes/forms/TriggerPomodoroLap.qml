pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `pomodoroLap` event. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
FormChoice {
    required property var row

    current: row.trigger.lap
    onPicked: v => row.set({ lap: v })
    options: [
        { displayName: Translation.tr("Any lap"), value: "any" },
        { displayName: Translation.tr("A focus lap ends"), value: "focusEnd" },
        { displayName: Translation.tr("A break ends"), value: "breakEnd" }
    ]
}
