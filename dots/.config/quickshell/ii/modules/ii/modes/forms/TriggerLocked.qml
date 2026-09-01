pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `locked` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
FormChoice {
    required property var row

    current: row.trigger.is === false ? "no" : "yes"
    onPicked: v => row.set({ is: v === "yes" })
    options: [
        { displayName: Translation.tr("Locked"), value: "yes" },
        { displayName: Translation.tr("Unlocked"), value: "no" }
    ]
}
