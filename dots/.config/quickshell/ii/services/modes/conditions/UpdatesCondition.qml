import QtQuick
import qs.services
import ".."

/**
 * At least `atLeast` package updates are pending (per the bar's updates
 * checker). Without the checker this never holds.
 */
ModeCondition {
    id: root
    readonly property int atLeast: Math.max(1, Number(root.params?.atLeast) || 1)

    satisfied: Updates.available && Updates.count >= root.atLeast
    reason: Updates.available ? `${Updates.count} update${Updates.count === 1 ? "" : "s"}` : "checker off"
}
