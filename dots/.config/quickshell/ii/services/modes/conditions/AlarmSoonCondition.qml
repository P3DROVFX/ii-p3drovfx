import QtQuick
import qs.services
import ".."

/**
 * An alarm — on this PC, on the phone, or either — rings within `minutes`. Holds for
 * the whole stretch before it, so a "while" mode can dim things down ahead of it.
 */
ModeCondition {
    id: root
    readonly property string source: String(root.params?.source ?? "any")
    readonly property int minutes: Math.max(1, Number(root.params?.minutes) || 60)

    function evaluate() {
        const now = Date.now();
        const horizon = now + root.minutes * 60000;
        let at = null;
        if (root.source !== "phone") {
            const next = AlarmService.nextAlarm(new Date());
            if (next && next.at.getTime() <= horizon)
                at = next.at;
        }
        if (root.source !== "pc") {
            const phone = PhoneAlarmService.nextAt;
            if (phone && phone.getTime() > now && phone.getTime() <= horizon && (!at || phone < at))
                at = phone;
        }
        root.satisfied = at !== null;
        root.reason = at ? Qt.formatTime(at, "HH:mm") : "";
    }

    readonly property Timer poll: Timer {
        interval: 30000
        repeat: true
        running: root.armed
        triggeredOnStart: true
        onTriggered: root.evaluate()
    }

    readonly property Connections alarms: Connections {
        target: AlarmService
        function onAlarmsChanged() { root.evaluate(); }
    }

    readonly property Connections phone: Connections {
        target: PhoneAlarmService
        function onNextAtChanged() { root.evaluate(); }
    }
}
