pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

/**
 * Slim OutlookIcsImport stand-in for standalone apps.
 */
Singleton {
    id: root

    property bool scanning: false
    property string lastError: ""
    property string lastStatus: ""

    function scanNow() {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "calendar", "sync"]);
    }
}
