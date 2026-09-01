pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `notify` action. `row` is the ActionRow this form
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
            text: Translation.tr("Title")
        }

        PlainField {
            Layout.fillWidth: true
            value: String(row.obj.title ?? "")
            placeholder: Translation.tr("Routine ran")
            onCommitted: v => row.patchValue({ title: v })
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            Layout.preferredWidth: 60
            text: Translation.tr("Body")
        }

        PlainField {
            Layout.fillWidth: true
            value: String(row.obj.body ?? "")
            placeholder: Translation.tr("Optional")
            onCommitted: v => row.patchValue({ body: v })
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            Layout.preferredWidth: 60
            text: Translation.tr("Icon")
        }

        PlainField {
            Layout.fillWidth: true
            monospace: true
            value: String(row.obj.icon ?? "")
            placeholder: Translation.tr("Icon name or file, optional")
            onCommitted: v => row.patchValue({ icon: v })
        }
    }

    FormHint {
        text: Translation.tr("Sent as a desktop notification, so it shows in the notification list too.")
    }
}
