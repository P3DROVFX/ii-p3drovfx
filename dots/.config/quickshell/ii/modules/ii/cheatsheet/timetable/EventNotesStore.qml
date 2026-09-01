import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Owner of timetable-event-notes.json: links a calendar event identity to a
 * note title in the existing notes overlay.
 *
 * Deliberately lives inside the timetable module and derives its storage
 * location from the existing notes file directory — nothing outside this
 * module is modified. Persistence follows the three-layer guard from
 * AGENTS.md: atomic writes, a readiness gate before any write, and a
 * retry-then-accept policy when the file is briefly missing around hot
 * reloads.
 */
Item {
    id: root

    readonly property string filePath: {
        let base = String(Directories.notesPath ?? "");
        if (base.startsWith("file://"))
            base = base.slice(7);
        const slash = base.lastIndexOf("/");
        return (slash >= 0 ? base.slice(0, slash + 1) : "") + "timetable-event-notes.json";
    }
    /** [{key: "uid:<uid>" | "k:<content>@<ms>", title: "<note title>"}] */
    property var entries: []
    property bool ready: false
    property real initTimestamp: Date.now()

    function indexFor(key) {
        const wanted = String(key ?? "");
        if (wanted.length === 0)
            return -1;
        for (let i = 0; i < root.entries.length; i++) {
            if (String(root.entries[i]?.key ?? "") === wanted)
                return i;
        }
        return -1;
    }

    function titleFor(key) {
        const index = root.indexFor(key);
        return index >= 0 ? String(root.entries[index].title ?? "") : "";
    }

    function setLink(key, title) {
        const next = Array.from(root.entries).filter(entry => String(entry?.key ?? "") !== String(key));
        next.push({ key: String(key), title: String(title ?? "") });
        root.entries = next;
        writeTimer.restart();
    }

    Timer {
        id: writeTimer
        interval: 100
        onTriggered: {
            if (!root.ready) {
                writeTimer.restart();
                return;
            }
            fileView.setText(JSON.stringify({ version: 1, entries: root.entries }, null, 2));
        }
    }

    Timer {
        id: retryTimer
        interval: 1500
        onTriggered: fileView.reload()
    }

    FileView {
        id: fileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        atomicWrites: true
        onLoaded: {
            try {
                const parsed = JSON.parse(fileView.text());
                root.entries = Array.isArray(parsed?.entries) ? parsed.entries : [];
            } catch (e) {
                root.entries = [];
            }
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                return;
            // Hot reloads can race the watcher with an inode swap; only trust
            // "really missing" after the grace period, otherwise retry once.
            if (Date.now() - root.initTimestamp > 2000)
                root.ready = true;
            else
                retryTimer.restart();
        }
    }
}
