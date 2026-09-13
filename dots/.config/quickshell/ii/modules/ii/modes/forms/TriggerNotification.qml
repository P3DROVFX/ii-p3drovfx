pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `notification` event. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            Layout.preferredWidth: 90
            text: Translation.tr("From app")
        }

        PlainField {
            Layout.fillWidth: true
            value: row.trigger.app
            placeholder: Translation.tr("Part of the app's name — empty means any app")
            onCommitted: v => row.set({ app: v })
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            Layout.preferredWidth: 90
            text: Translation.tr("Containing")
        }

        PlainField {
            Layout.fillWidth: true
            value: row.trigger.text
            placeholder: Translation.tr("Text in the title or body — optional")
            onCommitted: v => row.set({ text: v })
        }
    }

    FormHint {
        readonly property var names: Array.from(Notifications.appNameList ?? []).slice(0, 6)
        visible: names.length > 0
        text: Translation.tr("Recently: %1").arg(names.join(", "))
    }
}
