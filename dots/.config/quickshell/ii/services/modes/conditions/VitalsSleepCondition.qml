import QtQuick
import qs.services
import ".."

/**
 * Last night's sleep from ii Vitals: the main night that ended today, its length in
 * minutes (`metric: "duration"`) or its score (`"score"`) below `below` and/or above
 * `above`. Holds nothing before the night has synced, or for a night without a score.
 */
ModeCondition {
    id: root
    readonly property string metric: root.params?.metric === "score" ? "score" : "duration"
    readonly property var below: root.params?.below ?? null
    readonly property var above: root.params?.above ?? null

    readonly property string today: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")
    readonly property var night: {
        void VitalsService.dataVersion;
        return VitalsService.summary(root.today)?.sleep ?? null;
    }
    readonly property var value: root.night === null ? null
        : root.metric === "score" ? (root.night.score ?? null) : root.night.min

    satisfied: root.value !== null
        && (root.below === null || root.value < Number(root.below))
        && (root.above === null || root.value > Number(root.above))
    reason: !VitalsService.enabled ? "vitals off"
        : root.night === null ? "no night synced yet"
        : root.metric === "score" ? `score ${root.value ?? "none"}`
        : `${Math.floor(root.night.min / 60)} h ${root.night.min % 60} min`
}
