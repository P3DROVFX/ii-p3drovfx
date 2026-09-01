import QtQuick
import Quickshell.Hyprland
import "../ModeSchema.js" as ModeSchema
import ".."

/**
 * Event: a Hyprland global shortcut is pressed. The shell registers it as
 * `quickshell:modes-<name>` (name defaults to the routine's id); the user
 * binds a key to it in their Hyprland config.
 */
ModeCondition {
    id: root
    readonly property string name: ModeSchema.shortcutName(root.params, root.ownerId)

    readonly property GlobalShortcut shortcut: GlobalShortcut {
        appid: "quickshell"
        name: `modes-${root.name}`
        description: `Modes & Routines: ${root.ownerId}`
        onPressed: root.pulse(`quickshell:modes-${root.name}`)
    }
}
