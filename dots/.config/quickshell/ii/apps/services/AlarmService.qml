pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Slim AlarmService IPC bridge for standalone apps.
 */
Singleton {
    id: root

    property var alarms: []

    function alarmIndexForEvent(eventKey) {
        const key = String(eventKey ?? "");
        if (!key)
            return -1;
        return root.alarms.findIndex(a => String(a?.eventKey ?? "") === key);
    }

    function addAlarmForEvent(event, leadMinutes) {
        if (!event)
            return false;
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "clock", "open", "alarms"]);
        return true;
    }

    function removeAlarmForEvent(eventKey) {
        const key = String(eventKey ?? "");
        if (!key)
            return false;
        return true;
    }
}
