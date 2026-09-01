pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Owner of custom-lyrics.json: hand-written .lrc keyed by track.
 *
 * There is no word-level timing source in this stack, and LRCLib's coverage
 * has holes, so the escape hatch is letting the user paste their own LRC for
 * a track. That content can't be re-fetched from anywhere, so persistence
 * follows the AGENTS.md three-layer guard: atomic writes, a readiness gate
 * before any write, and a retry-then-accept policy around hot reloads.
 */
Singleton {
    id: root

    /** { "<title>||<artist>": "<raw lrc text>" } */
    property var entries: ({})
    property bool ready: false
    readonly property real initTimestamp: Date.now()

    function keyFor(title, artist) {
        const t = String(title ?? "").trim().toLowerCase();
        const a = String(artist ?? "").trim().toLowerCase();
        return t.length === 0 ? "" : `${t}||${a}`;
    }

    function get(title, artist) {
        const key = root.keyFor(title, artist);
        if (key.length === 0)
            return "";
        return String(root.entries[key] ?? "");
    }

    function has(title, artist) {
        return root.get(title, artist).length > 0;
    }

    function set(title, artist, lrcText) {
        const key = root.keyFor(title, artist);
        if (key.length === 0)
            return;

        const next = Object.assign({}, root.entries);
        const trimmed = String(lrcText ?? "").trim();
        if (trimmed.length === 0)
            delete next[key];
        else
            next[key] = trimmed;

        root.entries = next;
        writeTimer.restart();
    }

    function remove(title, artist) {
        root.set(title, artist, "");
    }

    Timer {
        id: writeTimer
        interval: 100
        onTriggered: {
            if (!root.ready) {
                writeTimer.restart();
                return;
            }
            fileView.setText(JSON.stringify({
                version: 1,
                entries: root.entries
            }, null, 2));
        }
    }

    Timer {
        id: retryTimer
        interval: 1500
        onTriggered: fileView.reload()
    }

    FileView {
        id: fileView
        path: Qt.resolvedUrl(Directories.customLyricsPath)
        watchChanges: true
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(fileView.text());
                root.entries = (parsed && typeof parsed.entries === "object" && parsed.entries)
                    ? parsed.entries : {};
            } catch (e) {
                root.entries = {};
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
