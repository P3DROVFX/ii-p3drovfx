pragma Singleton

import QtQuick
import Quickshell

/**
 * Slim CalendarService bridge for standalone apps.
 * Forwards ICS imports to the running shell's CalendarService via IPC so the app
 * never boots khal/vdirsyncer or calendar models in its own process.
 */
Singleton {
    id: root

    function importFromIcs(path, autoDelete = false) {
        const sourcePath = String(path ?? "").trim();
        if (!sourcePath)
            return false;
        Quickshell.execDetached([
            "qs", "-c", "ii", "ipc", "call", "calendar", "importIcs",
            sourcePath, autoDelete ? "true" : "false"
        ]);
        return true;
    }
}
