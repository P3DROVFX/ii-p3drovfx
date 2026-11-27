import QtQuick
import qs.services
import ".."

/**
 * Today's steps from ii Vitals have reached the phone's step goal. A state, so a
 * "when" routine fires on the crossing (the phone pushes every 10 min, so within about
 * that) and a "while" one holds until midnight. Once reached it stays reached for the
 * day: a re-sync from another steps source can dip under the goal for one push, and
 * that would fire a "when" routine twice.
 */
ModeCondition {
    id: root
    readonly property string today: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")
    readonly property var goal: VitalsService.meta?.goals?.steps ?? null
    readonly property var steps: {
        void VitalsService.dataVersion;
        return VitalsService.summary(root.today)?.t?.steps ?? null;
    }
    readonly property bool reached: root.goal > 0 && root.steps !== null && root.steps >= root.goal
    property string reachedOn: ""

    onReachedChanged: {
        if (root.reached)
            root.reachedOn = root.today;
    }
    Component.onCompleted: {
        if (root.reached)
            root.reachedOn = root.today;
    }

    satisfied: root.reachedOn === root.today
    reason: !VitalsService.enabled ? "vitals off"
        : !(root.goal > 0) ? "no step goal from the phone"
        : `${root.steps ?? 0} of ${root.goal} steps`
}
