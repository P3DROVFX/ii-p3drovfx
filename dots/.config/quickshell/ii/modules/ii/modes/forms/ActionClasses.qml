pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts
import "../../../../services/modes/ModeSchema.js" as ModeSchema

/**
 * Parameters of the `classes` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 8

    ChipInput {
        Layout.fillWidth: true
        values: Array.isArray(row.value) || ModeSchema.isArrayLike(row.value)
            ? ModeSchema.stringList(row.value) : ModeSchema.stringList(row.obj.classes)
        placeholder: Translation.tr("Window class to close gracefully")
        suggestions: ModeUi.windowSuggestions()
        onChanged: list => row.setValue(list)
    }

    FormHint {
        text: Translation.tr("Windows are asked to close, never killed.")
    }
}
