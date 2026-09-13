pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `keyboardLayout` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        FormLabel {
            text: Translation.tr("Layout code")
        }

        PlainField {
            Layout.preferredWidth: 120
            monospace: true
            value: row.trigger.code
            placeholder: "fr"
            onCommitted: v => row.set({ code: v })
        }

        Repeater {
            model: Array.from(HyprlandXkb.layoutCodes ?? []).filter((c, i, a) => c && a.indexOf(c) === i)

            delegate: SmallButton {
                required property string modelData
                buttonText: modelData
                onClicked: row.set({ code: modelData })
            }
        }
    }

    FormHint {
        text: HyprlandXkb.currentLayoutCode.length
            ? Translation.tr("Active now: %1 (%2)").arg(HyprlandXkb.currentLayoutName).arg(HyprlandXkb.currentLayoutCode)
            : Translation.tr("Switch layouts once so the shell learns the codes.")
    }
}
