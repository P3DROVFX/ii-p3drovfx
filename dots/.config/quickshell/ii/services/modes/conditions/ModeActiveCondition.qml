import QtQuick
import qs.services
import ".."

/**
 * The mode with `id` is active (routines: "when Work starts, also…").
 * Without an id: any mode is active.
 */
ModeCondition {
    id: root
    readonly property string modeId: String(root.params?.id ?? "")
    satisfied: root.modeId.length ? Modes.activeModeId === root.modeId : Modes.active
    reason: Modes.activeMode?.name ?? ""
}
