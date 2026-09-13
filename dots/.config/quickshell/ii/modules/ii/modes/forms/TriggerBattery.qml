pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `battery` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("Below")
        }

        PercentField {
            value: row.trigger.below
            onCommitted: v => row.set({ below: v })
        }

        FormLabel {
            text: Translation.tr("Above")
        }

        PercentField {
            value: row.trigger.above
            onCommitted: v => row.set({ above: v })
        }

        FormHint {
            text: Translation.tr("Leave empty to ignore")
        }
    }

    FormChoice {
        current: row.trigger.pluggedIn === true ? "yes" : (row.trigger.pluggedIn === false ? "no" : "any")
        onPicked: v => row.set({ pluggedIn: v === "any" ? null : v === "yes" })
        options: [
            { displayName: Translation.tr("Any power"), value: "any" },
            { displayName: Translation.tr("Plugged in"), value: "yes" },
            { displayName: Translation.tr("On battery"), value: "no" }
        ]
    }
}
