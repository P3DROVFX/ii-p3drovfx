pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `audioDevice` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.kind
        onPicked: v => row.set({ kind: v })
        options: [
            { displayName: Translation.tr("Output"), value: "sink" },
            { displayName: Translation.tr("Input"), value: "source" }
        ]
    }

    PlainField {
        Layout.fillWidth: true
        value: row.trigger.match
        placeholder: Translation.tr("Part of the device name, e.g. WH-1000XM")
        onCommitted: v => row.set({ match: v })
    }
}
