import QtQuick
import qs
import ".."

/**
 * The screen is locked (`is: true`, default) or unlocked (`is: false`).
 */
ModeCondition {
    id: root
    readonly property bool wantLocked: root.params?.is !== false
    satisfied: GlobalStates.screenLocked === root.wantLocked
    reason: GlobalStates.screenLocked ? "locked" : "unlocked"
}
