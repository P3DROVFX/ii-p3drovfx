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
 * Parameters of the `workspace` condition. `row` is the TriggerRow this form
 * unfolds from; every change goes back through it.
 */
ColumnLayout {
    required property var row

    spacing: 10

    FormChoice {
        current: row.trigger.special === true ? "special" : "named"
        onPicked: v => row.set({ special: v === "special" })
        options: [
            { displayName: Translation.tr("One of these"), value: "named" },
            { displayName: Translation.tr("A special workspace is open"), value: "special" }
        ]
    }

    ChipInput {
        Layout.fillWidth: true
        visible: row.trigger.special !== true
        values: row.trigger.names
        placeholder: Translation.tr("Workspace number or name")
        suggestions: Array.from(Hyprland.workspaces?.values ?? [])
            .filter(w => w && w.id > 0)
            .map(w => ({ label: String(w.name ?? w.id), value: String(w.name ?? w.id) }))
        onChanged: list => row.set({ names: list })
    }

    FormHint {
        visible: row.trigger.special !== true
        text: Translation.tr("Holds while the focused workspace is one of them.")
    }
}
