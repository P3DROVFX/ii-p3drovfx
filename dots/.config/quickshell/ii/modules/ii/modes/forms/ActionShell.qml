pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `shell` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            Layout.preferredWidth: 60
            text: Translation.tr("On start")
        }

        PlainField {
            Layout.fillWidth: true
            monospace: true
            value: String(typeof row.value === "object" ? (row.obj.start ?? "") : (row.value ?? ""))
            placeholder: Translation.tr("Command, run with sh -c")
            onCommitted: v => row.patchValue({ start: v, end: row.obj.end ?? "" })
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            Layout.preferredWidth: 60
            text: Translation.tr("On end")
        }

        PlainField {
            Layout.fillWidth: true
            monospace: true
            value: String(row.obj.end ?? "")
            placeholder: Translation.tr("Optional")
            onCommitted: v => row.patchValue({ start: row.obj.start ?? "", end: v })
        }
    }
}
