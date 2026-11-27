pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Read-only Config for standalone apps (qs -p apps/<app>.qml).
 *
 * The shell's Config is an 8.7k-line JsonAdapter that binds to dozens of services
 * and writes config.json back; an app importing it boots half the shell. This one
 * parses the shell's config.json once, keeps only the sections shared widgets read,
 * follows later edits, and never writes. App-owned settings go to their own file
 * under Directories.appsState, not here: the shell's adapter drops keys it does not know.
 */
Singleton {
    id: root

    // What the shared widgets and the generated Appearance read, as dotted paths:
    // whole sections, or single leaves of shell sections the tokens peek at (bar
    // sizes, dock height). Add a path when a reused widget needs it; anything else
    // stays out of the app's heap.
    readonly property var sections: [
        "appearance", "interactions", "language", "time", "apps", "userProfile",
        "bar.sizes", "bar.verbose", "bar.tooltips", "dock.height", "search.appearance", "background.widgets.gridStep"
    ]

    property var options: ({})
    property bool ready: false

    // Kept so code written for the shell's Config still runs; nothing is written.
    property bool blockWrites: true
    property int readWriteDelay: 0

    function load(content: string): void {
        let parsed;
        try {
            parsed = JSON.parse(content);
        } catch (e) {
            if (!root.ready)
                console.warn("[apps Config] config.json unreadable, using defaults:", e);
            return; // the shell is mid-write: the next change event brings the full file
        }
        const picked = {};
        for (const path of root.sections) {
            const keys = path.split(".");
            let src = parsed;
            let dst = picked;
            for (let i = 0; i < keys.length - 1; i++) {
                src = src?.[keys[i]];
                if (dst[keys[i]] === undefined)
                    dst[keys[i]] = {};
                dst = dst[keys[i]];
            }
            const leaf = keys[keys.length - 1];
            dst[leaf] = src?.[leaf] ?? (keys.length === 1 ? {} : undefined);
        }
        root.options = picked;
        root.ready = true;
    }

    FileView {
        id: configFile
        path: `${Directories.shellConfig}/config.json`
        watchChanges: true
        blockAllReads: true
        onFileChanged: reload()
        onLoaded: root.load(text())
    }

    // Parse before any binding asks for options: the singleton is built on first access.
    Component.onCompleted: root.load(configFile.text())
}
