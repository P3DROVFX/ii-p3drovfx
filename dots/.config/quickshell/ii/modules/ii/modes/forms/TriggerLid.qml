pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `lid` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.closed === false ? "open" : "closed"
        onPicked: v => row.set({ closed: v === "closed" })
        options: [
            { displayName: Translation.tr("Closed"), value: "closed" },
            { displayName: Translation.tr("Open"), value: "open" }
        ]
    }

    FormHint {
        text: Translation.tr("Checked every few seconds. Pairs with Monitors for \"closed on a dock\".")
    }
}
