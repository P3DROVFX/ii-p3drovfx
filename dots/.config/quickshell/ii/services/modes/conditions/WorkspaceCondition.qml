import QtQuick
import Quickshell.Hyprland
import qs.services
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * The focused workspace is one of `names` (ids or names), or — with
 * `special` — a special workspace (scratchpad) is open on the focused
 * monitor.
 */
ModeCondition {
    id: root
    readonly property var names: ModeSchema.stringList(root.params?.names).map(n => n.toLowerCase())
    readonly property bool wantSpecial: root.params?.special === true

    readonly property var focused: Hyprland.focusedWorkspace
    readonly property string focusedName: String(root.focused?.name ?? "").toLowerCase()
    readonly property string focusedId: String(root.focused?.id ?? "")

    readonly property string monitorName: Hyprland.focusedMonitor?.name ?? ""
    readonly property string specialName: {
        const m = ModeSchema.toArray(HyprlandData.monitors).find(x => x && x.name === root.monitorName);
        return String(m?.specialWorkspace?.name ?? "");
    }

    readonly property bool byName: root.names.length > 0
        && (root.names.indexOf(root.focusedName) !== -1 || root.names.indexOf(root.focusedId) !== -1)

    satisfied: root.wantSpecial ? root.specialName.length > 0 : root.byName
    reason: root.wantSpecial ? root.specialName.replace(/^special:/, "")
        : (root.focused ? (root.focusedName || root.focusedId) : "")
}
