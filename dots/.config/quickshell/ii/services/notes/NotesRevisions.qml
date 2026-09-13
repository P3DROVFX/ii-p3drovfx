pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * Revision history and snapshot manager for the Notes app.
 *
 * Automatically captures point-in-time snapshots of notes on significant edits,
 * cloud syncs, or manual requests, and computes block-level diffs for visual inspection
 * and restoration.
 */
Singleton {
    id: root

    readonly property string notesFolder: Directories.notesDir
    readonly property string helperScript: `${Directories.scriptPath}/notes/notes_store.py`

    property string currentNoteId: ""
    property var currentRevisions: []
    property bool loading: false

    signal revisionsLoaded(string noteId, var revisions)
    signal snapshotSaved(string noteId, int timestamp)

    // ── Save Snapshot ──────────────────────────────────────────────────────

    function saveSnapshot(noteId, title, blocks, author) {
        if (!noteId || !blocks)
            return;
        const payload = {
            noteId: noteId,
            timestamp: Date.now(),
            date: new Date().toISOString(),
            title: title || "",
            blocks: blocks,
            author: author || "local"
        };

        saveProcess.payload = JSON.stringify(payload);
        saveProcess.command = ["python3", root.helperScript, "save-revision", root.notesFolder, noteId];
        saveProcess.running = true;
    }

    Process {
        id: saveProcess
        property string payload: ""

        onRunningChanged: {
            if (!saveProcess.running)
                return;
            saveProcess.stdinEnabled = true;
            saveProcess.write(saveProcess.payload);
            saveProcess.stdinEnabled = false;
        }

        stdout: StdioCollector {
            id: saveOutput
            onStreamFinished: {
                try {
                    const res = JSON.parse(saveOutput.text.trim());
                    if (res.ok) {
                        root.snapshotSaved(root.currentNoteId, res.timestamp);
                    }
                } catch (e) {}
            }
        }
    }

    // ── List Revisions ─────────────────────────────────────────────────────

    function listRevisions(noteId) {
        if (!noteId) {
            root.currentRevisions = [];
            return;
        }
        root.currentNoteId = noteId;
        root.loading = true;
        listProcess.command = ["python3", root.helperScript, "list-revisions", root.notesFolder, noteId];
        listProcess.running = true;
    }

    Process {
        id: listProcess
        stdout: StdioCollector {
            id: listOutput
            onStreamFinished: {
                root.loading = false;
                try {
                    const res = JSON.parse(listOutput.text.trim());
                    if (res.ok && Array.isArray(res.revisions)) {
                        root.currentRevisions = res.revisions;
                        root.revisionsLoaded(root.currentNoteId, res.revisions);
                        return;
                    }
                } catch (e) {}
                root.currentRevisions = [];
            }
        }
    }

    // ── Read Revision ──────────────────────────────────────────────────────

    property var _pendingCallbacks: ({})

    function readRevision(noteId, timestamp, callback) {
        if (!noteId || !timestamp)
            return;
        const key = `${noteId}_${timestamp}`;
        root._pendingCallbacks[key] = callback;

        const proc = readComp.createObject(root, {
            noteId: noteId,
            timestamp: timestamp,
            key: key
        });
        proc.start();
    }

    Component {
        id: readComp
        QtObject {
            id: obj
            property string noteId: ""
            property var timestamp: 0
            property string key: ""

            function start() {
                p.command = ["python3", root.helperScript, "read-revision", root.notesFolder, obj.noteId, String(obj.timestamp)];
                p.running = true;
            }

            property Process proc: Process {
                id: p
                stdout: StdioCollector {
                    id: c
                    onStreamFinished: {
                        let doc = null;
                        try {
                            const res = JSON.parse(c.text.trim());
                            if (res.ok && res.revision)
                                doc = res.revision;
                        } catch (e) {}

                        const cb = root._pendingCallbacks[obj.key];
                        if (typeof cb === "function") {
                            delete root._pendingCallbacks[obj.key];
                            cb(doc);
                        }
                        obj.destroy();
                    }
                }
            }
        }
    }

    // ── Diff Algorithm ─────────────────────────────────────────────────────

    /**
     * Computes block-level diff between two versions of a document.
     * Returns an array of items: { kind: "same"|"added"|"deleted"|"modified", currentText, revText, currentType, revType }
     */
    function computeDiff(currentBlocks, revisionBlocks) {
        const cur = Array.isArray(currentBlocks) ? currentBlocks : [];
        const rev = Array.isArray(revisionBlocks) ? revisionBlocks : [];
        const diff = [];

        const curMap = {};
        for (let i = 0; i < cur.length; i++) {
            if (cur[i] && cur[i].id)
                curMap[cur[i].id] = cur[i];
        }

        const revMap = {};
        for (let j = 0; j < rev.length; j++) {
            if (rev[j] && rev[j].id)
                revMap[rev[j].id] = rev[j];
        }

        // Check revision blocks against current
        for (let j = 0; j < rev.length; j++) {
            const r = rev[j];
            if (!r) continue;
            const c = curMap[r.id];
            if (!c) {
                // Was in revision, deleted in current
                diff.push({
                    kind: "deleted",
                    text: r.text || "",
                    type: r.type || "text",
                    revBlock: r,
                    curBlock: null
                });
            } else if ((c.text || "") !== (r.text || "") || c.type !== r.type) {
                // Changed
                diff.push({
                    kind: "modified",
                    text: c.text || "",
                    oldText: r.text || "",
                    type: c.type || "text",
                    revBlock: r,
                    curBlock: c
                });
            } else {
                // Identical
                diff.push({
                    kind: "same",
                    text: c.text || "",
                    type: c.type || "text",
                    revBlock: r,
                    curBlock: c
                });
            }
        }

        // Check blocks added in current that weren't in revision
        for (let i = 0; i < cur.length; i++) {
            const c = cur[i];
            if (!c) continue;
            if (!revMap[c.id]) {
                diff.push({
                    kind: "added",
                    text: c.text || "",
                    type: c.type || "text",
                    revBlock: null,
                    curBlock: c
                });
            }
        }

        return diff;
    }
}
