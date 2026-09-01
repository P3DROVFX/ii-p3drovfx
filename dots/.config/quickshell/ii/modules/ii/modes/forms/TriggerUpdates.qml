pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `updates` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("At least")
        }

        StyledSpinBox {
            implicitHeight: baseHeight
            from: 1
            to: 1000
            value: row.trigger.atLeast
            onValueModified: row.set({ atLeast: value })
        }

        FormLabel {
            text: Translation.tr("updates pending")
        }
    }

    FormHint {
        text: Updates.available
            ? Translation.tr("%1 pending now.").arg(Updates.count)
            : Translation.tr("The bar's update checker is off or has not run yet.")
    }
}
