pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Slim OutlookCalendarImport stand-in for standalone apps.
 */
Singleton {
    id: root

    property bool syncing: false
    property string lastError: ""
    property string lastStatus: ""

    function syncNow() {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "calendar", "sync"]);
    }
}
