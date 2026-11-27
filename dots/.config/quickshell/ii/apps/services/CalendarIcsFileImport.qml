pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

/**
 * Slim CalendarIcsFileImport stand-in for standalone apps: imports local .ics
 * files directly through CalendarService.
 */
Singleton {
    id: root

    property string lastStatus: ""

    function importSourceFile(path) {
        const clean = String(path ?? "").trim();
        if (!clean)
            return false;
        const ok = CalendarService.importFromIcs(clean, false);
        root.lastStatus = ok ? Translation.tr("Imported calendar file.") : Translation.tr("Could not import file.");
        return ok;
    }

    function open() {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "calendar", "open"]);
    }
}
