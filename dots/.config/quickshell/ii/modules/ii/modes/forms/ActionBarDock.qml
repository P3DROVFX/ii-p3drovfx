pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.modes
import QtQuick
import QtQuick.Layouts

/**
 * Parameters of the `barDock` action. `row` is the ActionRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("Bar")
        }

        FormChoice {
            current: row.obj.bar ?? "keep"
            onPicked: v => row.patchValue({ bar: v })
            options: [
                { displayName: Translation.tr("Keep"), value: "keep" },
                { displayName: Translation.tr("Auto-hide"), value: "autoHide" },
                { displayName: Translation.tr("Always shown"), value: "fixed" }
            ]
        }
    }

    RowLayout {
        spacing: 10

        FormLabel {
            text: Translation.tr("Dock")
        }

        FormChoice {
            current: row.obj.dock ?? "keep"
            onPicked: v => row.patchValue({ dock: v })
            options: [
                { displayName: Translation.tr("Keep"), value: "keep" },
                { displayName: Translation.tr("Hidden"), value: "hide" },
                { displayName: Translation.tr("Shown"), value: "show" }
            ]
        }
    }
}
