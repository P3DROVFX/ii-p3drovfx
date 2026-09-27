import QtQuick
import qs.services
import ".."

/**
 * Bedtime's own schedule: winding down before the target, past it, or either. Off on
 * nights bedtime does not apply to, and while bedtime is switched off.
 */
ModeCondition {
    id: root
    readonly property string phase: String(root.params?.phase ?? "either")

    satisfied: BedtimeService.phase !== "none"
        && (root.phase === "either" || BedtimeService.phase === root.phase)
    reason: BedtimeService.phase
}
