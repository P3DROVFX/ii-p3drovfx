pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Slim CalendarSubscriptions stand-in for standalone apps: updates subscription
 * URLs in the shell config via IPC.
 */
Singleton {
    id: root

    property bool applying: false
    property bool syncInProgress: false
    property string lastError: ""

    function addSubscription(url) {
        const clean = String(url ?? "").trim();
        if (!clean)
            return false;
        const current = Array.from(Config.options?.calendar?.timetable?.subscriptions ?? []);
        if (!current.includes(clean)) {
            current.push(clean);
            Config.setShellOption("calendar.timetable.subscriptions", current);
        }
        return true;
    }

    function removeSubscription(url) {
        const clean = String(url ?? "").trim();
        const current = Array.from(Config.options?.calendar?.timetable?.subscriptions ?? []).filter(u => u !== clean);
        Config.setShellOption("calendar.timetable.subscriptions", current);
        return true;
    }
}
