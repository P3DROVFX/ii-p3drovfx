pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `modeActive` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
RowLayout {
    required property var row

    spacing: 10

    FormLabel {
        text: Translation.tr("Mode")
    }

    StyledComboBox {
        Layout.preferredWidth: 220
        model: [Translation.tr("Any mode")].concat(Modes.modes.map(m => m.name))
        currentIndex: Math.max(0, Modes.modeIndex(row.trigger.id) + 1)
        onActivated: index => row.set({ id: index === 0 ? "" : (Modes.modes[index - 1]?.id ?? "") })
    }
}
