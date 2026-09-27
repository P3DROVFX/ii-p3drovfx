pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `alarm` event. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
FormChoice {
    required property var row

    current: row.trigger.event
    onPicked: v => row.set({ event: v })
    options: [
        { displayName: Translation.tr("Starts ringing"), value: "ringing" },
        { displayName: Translation.tr("Is dismissed"), value: "dismissed" },
        { displayName: Translation.tr("Is snoozed"), value: "snoozed" },
        { displayName: Translation.tr("Was missed"), value: "missed" }
    ]
}
