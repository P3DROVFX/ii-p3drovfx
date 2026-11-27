import QtQuick
import qs.services
import ".."

/**
 * Today's energy score from ii Vitals below `below` and/or above `above`. The phone
 * works it out in the morning; until today's has synced this holds nothing.
 */
ModeCondition {
    id: root
    readonly property var below: root.params?.below ?? null
    readonly property var above: root.params?.above ?? null

    readonly property string today: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")
    readonly property var score: {
        void VitalsService.dataVersion;
        return VitalsService.summary(root.today)?.sc?.energy ?? null;
    }

    satisfied: root.score !== null
        && (root.below === null || root.score < Number(root.below))
        && (root.above === null || root.score > Number(root.above))
    reason: !VitalsService.enabled ? "vitals off" : root.score === null ? "no score yet today" : `energy ${root.score}`
}
