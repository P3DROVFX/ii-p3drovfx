pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * The System Health assistant's finished answers, one per subject, kept on disk.
 *
 * An answer outlives its sheet, the tab, the window and a shell restart; only the
 * card's close button removes it. Each subject keeps a short thread: a follow-up adds a
 * turn, at most `maxTurns`. Keys are the assistant's subject keys ("overview",
 * "finding:<id>", "crash:<exe>", "journal:<fp>"). Only finished answers are kept: a run
 * cut off half way has nothing worth reading later.
 *
 * Entries saved before threads ({ question, answer, proposal }) read as one turn.
 *
 * One top-level `var` in the adapter, as AppUsage and AiUsage do: a `var` inside a
 * nested JsonObject trips Quickshell's JSON adapter.
 */
Singleton {
    id: root

    /// { key: { turns: [{ q, a, proposal }], folded, at, goneAt, autoFolded } }
    property var entries: ({})
    property bool ready: false
    /// Old answers make way for new ones past this many subjects.
    readonly property int maxEntries: 40
    /// A thread keeps its last this many questions.
    readonly property int maxTurns: 6

    readonly property string path: FileUtils.trimFileProtocol(`${Directories.state}/user/health/answers.json`)

    function entry(key: string): var {
        return root.entries[key] ?? null;
    }

    /// An entry's turns, oldest first; [] for none.
    function turnsOf(e: var): var {
        if (!e)
            return [];
        if (Array.isArray(e.turns))
            return e.turns;
        return e.answer ? [{ q: String(e.question ?? ""), a: String(e.answer), proposal: e.proposal ?? null }] : [];
    }

    /// Saves a thread: `value` is { turns, folded }.
    function put(key: string, value: var): void {
        if (key.length === 0)
            return;
        const turns = Array.from(value?.turns ?? []).slice(-root.maxTurns).map(t => ({
            q: String(t?.q ?? ""),
            a: String(t?.a ?? ""),
            proposal: t?.proposal ?? null
        }));
        const next = Object.assign({}, root.entries);
        next[key] = {
            turns: turns,
            folded: value?.folded === true,
            at: Date.now(),
            goneAt: 0
        };
        const keys = Object.keys(next).sort((a, b) => (next[b].at ?? 0) - (next[a].at ?? 0));
        for (const old of keys.slice(root.maxEntries))
            delete next[old];
        root.entries = next;
        saveTimer.restart();
    }

    function patch(key: string, fields: var): void {
        const current = root.entries[key];
        if (!current)
            return;
        const next = Object.assign({}, root.entries);
        next[key] = Object.assign({}, current, fields);
        root.entries = next;
        saveTimer.restart();
    }

    /// Changes the newest turn of a thread (its proposal, once used).
    function patchLastTurn(key: string, fields: var): void {
        const turns = root.turnsOf(root.entries[key]).slice();
        if (turns.length === 0)
            return;
        turns[turns.length - 1] = Object.assign({}, turns[turns.length - 1], fields);
        root.patch(key, { turns: turns, question: undefined, answer: undefined, proposal: undefined });
    }

    /// How long an answer outlives its subject: a finding fixed, a crash group gone.
    readonly property double goneKeepMs: 7 * 24 * 3600 * 1000

    /// Marks answers whose subject is gone (`goneAt`), and drops them a week later.
    /// Run whenever the helper has finished a scan, so "gone" is not just "not read yet".
    function sweep(): void {
        if (!root.ready || !HealthService.synced)
            return;
        const now = Date.now();
        const next = Object.assign({}, root.entries);
        let changed = false;
        for (const key of Object.keys(next)) {
            const e = next[key];
            const exists = HealthService.subjectExists(key);
            if (exists && e.goneAt) {
                next[key] = Object.assign({}, e, { goneAt: 0 });
                changed = true;
            } else if (!exists && !e.goneAt) {
                next[key] = Object.assign({}, e, { goneAt: now });
                changed = true;
            } else if (!exists && now - e.goneAt > root.goneKeepMs) {
                delete next[key];
                changed = true;
            }
        }
        if (changed) {
            root.entries = next;
            saveTimer.restart();
        }
    }

    Connections {
        target: HealthService
        function onSyncedChanged() {
            root.sweep();
        }
    }
    onReadyChanged: root.sweep()

    function remove(key: string): void {
        if (root.entries[key] === undefined)
            return;
        const next = Object.assign({}, root.entries);
        delete next[key];
        root.entries = next;
        saveTimer.restart();
    }

    Timer {
        id: saveTimer
        interval: 400
        onTriggered: {
            // A change before the file was read would otherwise overwrite what it holds.
            if (!root.ready) {
                saveTimer.restart();
                return;
            }
            adapter.entries = root.entries;
            fileView.writeAdapter();
        }
    }

    FileView {
        id: fileView
        path: root.path
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const loaded = adapter.entries;
            if (loaded && typeof loaded === "object" && !Array.isArray(loaded))
                root.entries = Object.assign({}, loaded, root.entries);
            root.ready = true;
        }
        onLoadFailed: error => {
            // No file yet is the normal first start; anything else still must not
            // block saving.
            root.ready = true;
        }

        adapter: JsonAdapter {
            id: adapter
            property var entries: ({})
        }
    }
}
