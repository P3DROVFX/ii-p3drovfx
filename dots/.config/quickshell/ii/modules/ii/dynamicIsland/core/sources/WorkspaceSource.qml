pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import qs.modules.common

/**
 * The focused workspace changed.
 *
 * Two traps here, both of which the old island fell into. Deriving the id from the
 * island window's own monitor turned *moving the focus between monitors* into a
 * workspace change, and the "previous" value was a binding on the current one, so the
 * comparison was a value against itself and the notch never fired at all. The previous
 * id is therefore plain state, seeded once.
 */
TransientSource {
    id: source

    activityId: "workspaces"
    ttlMs: 2000
    cooldownMs: 120

    readonly property int currentId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    readonly property string currentName: Hyprland.focusedWorkspace ? (Hyprland.focusedWorkspace.name ?? "") : ""
    property int previousId: -1

    readonly property bool ignoreSpecial: true

    onCurrentIdChanged: {
        const from = source.previousId;
        source.previousId = source.currentId;
        if (from === -1 || source.currentId === -1 || from === source.currentId)
            return;
        // Scratchpads come and go under a keybind of their own; announcing them as a
        // workspace change is noise.
        if (source.ignoreSpecial && source.currentName.startsWith("special"))
            return;
        source.trigger({ from: from, to: source.currentId, name: source.currentName });
    }

    Component.onCompleted: source.previousId = source.currentId
}
