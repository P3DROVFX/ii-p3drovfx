import QtQuick
import qs
import qs.services
import ".."

/**
 * Event: something happens to a clock alarm — it starts ringing (the default, and all
 * this trigger did before `event` existed), is dismissed, snoozed, or was missed while
 * the machine was off or asleep.
 */
ModeCondition {
    id: root
    readonly property string event: String(root.params?.event ?? "ringing")

    function fire(kind, alarm) {
        if (root.event !== kind)
            return;
        const label = String(alarm?.label ?? "");
        root.pulse(`${kind}${label.length ? ": " + label : ""}`);
    }

    readonly property Connections link: Connections {
        target: AlarmService
        function onAlarmRang(alarm) { root.fire("ringing", alarm); }
        function onAlarmDismissed(alarm) { root.fire("dismissed", alarm); }
        function onAlarmSnoozed(alarm) { root.fire("snoozed", alarm); }
        function onAlarmMissed(alarm, at) { root.fire("missed", alarm); }
    }
}
