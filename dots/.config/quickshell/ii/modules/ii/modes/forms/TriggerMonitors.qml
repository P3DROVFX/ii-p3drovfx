pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

/**
 * Parameters of the `monitors` condition. `row` is the TriggerRow this form
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
            to: 16
            value: row.trigger.count
            onValueModified: row.set({ count: value })
        }

        FormLabel {
            text: Translation.tr("monitors connected")
        }
    }

    ChipInput {
        Layout.fillWidth: true
        values: row.trigger.names
        placeholder: Translation.tr("Or a specific monitor name")
        suggestions: Array.from(Hyprland.monitors.values).map(m => ({ label: m.name, value: m.name }))
        onChanged: list => row.set({ names: list })
    }

    FormHint {
        visible: row.trigger.names.length > 0
        text: Translation.tr("With names set, the count is ignored.")
    }
}
