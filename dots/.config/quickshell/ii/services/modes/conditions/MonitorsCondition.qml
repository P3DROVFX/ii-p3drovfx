import QtQuick
import Quickshell.Hyprland
import qs.services
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * At least `count` monitors are connected, or — when `names` is given — any
 * of those monitors is. "Docked" without a dock sensor.
 */
ModeCondition {
    id: root
    readonly property int count: Math.max(1, Number(root.params?.count) || 2)
    readonly property var names: ModeSchema.stringList(root.params?.names)
    readonly property var monitors: Array.from(Hyprland.monitors?.values ?? [])
    readonly property var present: root.monitors.map(m => m.name)

    readonly property bool byName: root.names.length > 0
        && root.names.some(n => root.present.indexOf(n) !== -1)
    satisfied: root.names.length > 0 ? root.byName : root.monitors.length >= root.count
    reason: root.names.length > 0
        ? (root.names.find(n => root.present.indexOf(n) !== -1) ?? "")
        : `${root.monitors.length} monitor${root.monitors.length === 1 ? "" : "s"}`
}
