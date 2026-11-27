pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Slim NotesService stand-in for standalone apps: reads notes titles and opens
 * the shell's Notes app when creating/opening an event note.
 */
Singleton {
    id: root

    property var tabsData: []

    function create(title, initialBody = "") {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "notes", "open"]);
        return 0;
    }

    FileView {
        id: notesFile
        path: Qt.resolvedUrl(Directories.notesPath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(notesFile.text());
                root.tabsData = Array.isArray(parsed) ? parsed : (Array.isArray(parsed?.tabs) ? parsed.tabs : []);
            } catch (e) {
                root.tabsData = [];
            }
        }
        onLoadFailed: root.tabsData = []
    }
}
