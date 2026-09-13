pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.modules.common
import "NotesDocument.js" as Doc

/**
 * The notes store on disk: the index, one file per document, and the structural
 * operations that are awkward from QML.
 *
 * The split of labour is deliberate.
 *
 *   - The **index** is a single watched `FileView`. It is small, always loaded, and it is
 *     what every surface that only lists notes needs — the app's list, the desktop
 *     widgets, search. Watching it is also how two surfaces stay in step.
 *   - A **document** is a `NotesDocumentFile` of its own, so typing in one note writes one
 *     small file. This is the whole reason the store is not one JSON blob.
 *   - **Structural work** — creating the tree, committing a migration as one batch,
 *     deleting everything belonging to a note, copying a file in — goes to
 *     `scripts/notes/notes_store.py`. Those are multi-file and involve binaries, and QML
 *     runs on the GUI thread.
 *
 * Nothing here knows what a note *means*. Block structure, markdown and the migration
 * transform live in the `.js` modules, which is what lets them be tested without a shell.
 */
Scope {
    id: root

    readonly property string dir: Directories.notesDir
    readonly property string indexPath: Directories.notesIndexPath
    readonly property string docsDir: Directories.notesDocsDir
    readonly property string assetsDir: Directories.notesAssetsDir
    readonly property string scriptPath: `${Directories.scriptPath}/notes/notes_store.py`

    /// The normalised index. Never null, even before the first load.
    property var index: Doc.emptyIndex()

    /// The tree exists and the index has been read (or found absent).
    property bool initialised: false
    property bool indexLoaded: false
    /// True until the first index read settles, so callers can tell "no notes yet" from
    /// "not read yet" — the difference between an empty state and a migration.
    property bool hasIndexFile: false
    property string lastError: ""

    signal ready()
    signal indexUpdated()
    signal documentReady(string noteId, var document)
    signal writeFinished(bool ok, string error)
    signal committed(string tag, var result)
    /// A file that has been copied into a note's own folder, by the name it landed under.
    /// Asynchronous because the copy is: the helper renames around collisions, so the name
    /// is not known until it answers.
    signal assetImported(string noteId, string name)
    /// A JSON sidecar read back from a note's asset folder. `contents` is null when the
    /// file is not there, which is how a drawing made before strokes were kept says so.
    signal assetRead(string noteId, string name, var contents)

    // ── Documents ─────────────────────────────────────────────────────────
    // Every note in the index is kept resident.
    //
    // Not a cache policy so much as an honest description of who is asking: the desktop
    // widgets and the overlay render *every* note's text, so an LRU would thrash on the
    // first paint. It is still strictly better than what came before, where all of it also
    // lived in memory *and* was rewritten whole on every keystroke. When those surfaces
    // move to the index-and-preview API this becomes a real LRU, and the constraint
    // disappears with them.

    property var residentIds: []

    function refreshResidents(): void {
        const wanted = Doc.asArray(root.index.notes)
            .filter(note => note.trashedAt === 0)
            .map(note => note.id);
        if (JSON.stringify(wanted) !== JSON.stringify(root.residentIds))
            root.residentIds = wanted;
    }

    function fileFor(noteId): var {
        for (let i = 0; i < files.count; i++) {
            const candidate = files.objectAt(i);
            if (candidate && candidate.noteId === noteId)
                return candidate;
        }
        return null;
    }

    function documentOf(noteId): var {
        const file = root.fileFor(noteId);
        return file ? file.document : null;
    }

    /**
     * A document for a note whose writer does not exist yet.
     *
     * Called before the index entry that brings the writer into being. The alternative —
     * write the index, then hand the document to whatever object appeared — is a race
     * against object creation, and the loser is somebody's first paragraph.
     */
    property var seeds: ({})

    function seedDocument(noteId: string, document: var): void {
        root.seeds[noteId] = Doc.normalizeDocument(document, noteId);
    }

    function takeSeed(noteId: string): var {
        const seed = root.seeds[noteId] ?? null;
        if (seed !== null)
            root.seeds[noteId] = undefined;
        return seed;
    }

    function putDocument(noteId: string, document: var): bool {
        const file = root.fileFor(noteId);
        if (!file)
            return false;
        file.put(document);
        return true;
    }

    function flushDocument(noteId: string): void {
        const file = root.fileFor(noteId);
        if (file)
            file.flush();
    }

    function flushAll(): void {
        indexDebounce.stop();
        root.writeIndexNow();
        for (let i = 0; i < files.count; i++) {
            const file = files.objectAt(i);
            if (file)
                file.flush();
        }
    }

    readonly property bool writing: {
        if (indexFile.writing || indexDirty)
            return true;
        for (let i = 0; i < files.count; i++) {
            const file = files.objectAt(i);
            if (file && (file.writing || file.dirty))
                return true;
        }
        return false;
    }

    Instantiator {
        id: files
        model: root.residentIds
        delegate: NotesDocumentFile {
            required property string modelData
            noteId: modelData
            path: `${root.docsDir}/${modelData}.json`
            initialDocument: root.takeSeed(modelData)
            onDocumentLoaded: (id, value) => root.documentReady(id, value)
            onDocumentSaved: () => root.writeFinished(true, "")
            onDocumentFailed: (id, reason) => {
                root.lastError = reason;
                root.writeFinished(false, reason);
            }
        }
    }

    // ── The index ─────────────────────────────────────────────────────────

    property bool indexDirty: false
    property var pendingIndex: null

    function putIndex(value: var): void {
        root.index = Doc.normalizeIndex(value);
        root.pendingIndex = root.index;
        root.indexDirty = true;
        root.refreshResidents();
        root.indexUpdated();
        indexDebounce.restart();
    }

    function writeIndexNow(): void {
        if (!root.indexDirty || root.pendingIndex === null)
            return;
        const payload = JSON.stringify(root.pendingIndex, null, 2);
        root.indexDirty = false;
        if (payload === indexFile.text()) {
            root.writeFinished(true, "");
            return;
        }
        indexFile.writing = true;
        indexFile.setText(payload);
    }

    Timer {
        id: indexDebounce
        // Longer than a document's: the index changes on structure, not on typing, and a
        // burst of them (a migration, a bulk delete) should land as one write.
        interval: 600
        onTriggered: root.writeIndexNow()
    }

    FileView {
        id: indexFile
        property bool writing: false
        path: Qt.resolvedUrl(root.indexPath)
        watchChanges: true
        atomicWrites: true

        onLoaded: {
            root.indexLoaded = true;
            root.hasIndexFile = true;
            // Our own write coming back. Reading it would undo edits still in the
            // debounce.
            if (indexFile.writing || root.indexDirty)
                return;
            let parsed = null;
            try {
                parsed = JSON.parse(indexFile.text());
            } catch (error) {
                root.lastError = "index.json could not be parsed";
                parsed = null;
            }
            root.index = Doc.normalizeIndex(parsed);
            root.refreshResidents();
            root.indexUpdated();
        }

        onSaved: {
            indexFile.writing = false;
            root.writeFinished(true, "");
            if (root.indexDirty)
                indexDebounce.restart();
        }

        onSaveFailed: error => {
            indexFile.writing = false;
            root.lastError = `index.json save failed: ${error}`;
            root.writeFinished(false, root.lastError);
        }

        onLoadFailed: error => {
            indexFile.writing = false;
            root.indexLoaded = true;
            if (error === FileViewError.FileNotFound) {
                // No store yet. Whether that means "migrate" or "start empty" is the
                // service's call, not this object's.
                root.hasIndexFile = false;
                return;
            }
            root.lastError = `index.json load failed: ${error}`;
            root.settle();
        }
    }

    /**
     * Takes an index that is already on disk as the current one, without writing it back.
     *
     * Used right after a migration commit. `reload()` cannot be relied on there: a
     * `FileView` that has loaded once does not re-announce a load, so the store would sit
     * on the empty index it had before the helper ran.
     */
    function adoptIndex(value: var): void {
        root.index = Doc.normalizeIndex(value);
        root.hasIndexFile = true;
        root.indexDirty = false;
        root.pendingIndex = null;
        root.refreshResidents();
        root.indexUpdated();
    }

    /// Re-reads the index from disk. Used after a migration commit, so what the store
    /// shows is what the helper actually wrote rather than the plan it was handed.
    function reloadIndex(): void {
        indexFile.reload();
    }

    /**
     * `ready` fires once, when both halves of the bootstrap have landed.
     *
     * Declared rather than called from each site because the two halves race: the index
     * `FileView` loads as soon as its path is bound, which is usually *before* the helper
     * that creates the directory has finished. Calling `settle()` from the load handler
     * then did nothing — and `reload()` afterwards does not re-emit `loaded` when the
     * content has not changed, so the second chance never came and `ready` never fired.
     */
    readonly property bool bootstrapped: root.initialised && root.indexLoaded
    onBootstrappedChanged: root.settle()

    function settle(): void {
        if (!root.bootstrapped || root.readySent)
            return;
        root.readySent = true;
        root.ready();
    }

    property bool readySent: false

    // ── Structural operations ─────────────────────────────────────────────
    // One helper at a time, in the order asked for. Two of these running at once would
    // race the same directory.

    property var pending: []

    function enqueue(op: var): void {
        root.pending.push(op);
        if (!opProc.running)
            root.runNext();
    }

    function runNext(): void {
        if (opProc.running || root.pending.length === 0)
            return;
        const op = root.pending.shift();
        opProc.op = op;
        opProc.payload = op.stdin ?? "";
        opProc.command = ["python3", root.scriptPath, ...op.args];
        opProc.running = true;
    }

    function init(): void {
        root.enqueue({ tag: "init", args: ["init", root.dir] });
    }

    /**
     * Files, binary copies and renames applied as one step.
     *
     * A migration is all three at once, and half a migration is worse than none: it would
     * leave an index behind, and the next launch skips migrating when an index is there.
     */
    function commit(batch: var, tag: string): void {
        root.enqueue({ tag: tag, args: ["commit", root.dir], stdin: JSON.stringify(batch) });
    }

    function purge(noteId: string): void {
        root.enqueue({ tag: "purge", args: ["purge", root.dir, noteId] });
    }

    /// Makes sure a note's asset folder exists, and says when it does.
    ///
    /// A drawing is saved by grabbing the sheet and writing the image straight to a path,
    /// which fails if the folder is not there yet — and `mkdir` fired and forgotten is a
    /// race whose loser is somebody's drawing.
    signal assetsReady(string noteId)

    function prepareAssets(noteId: string): void {
        root.enqueue({ tag: "prepareAssets", noteId: noteId,
                       args: ["prepare-assets", root.dir, noteId] });
    }

    /// Reads a JSON sidecar out of a note's asset folder.
    function readAsset(noteId: string, name: string): void {
        root.enqueue({ tag: "readAsset", noteId: noteId, name: name,
                       args: ["read-asset", root.dir, noteId, name] });
    }

    /// Writes one, through the same batch commit everything else uses.
    function writeAsset(noteId: string, name: string, contents: var): void {
        root.commit({ files: [{ path: `assets/${noteId}/${name}`, contents: contents }] }, "writeAsset");
    }

    function importAsset(noteId: string, source: string): void {
        root.enqueue({ tag: "importAsset", noteId: noteId,
                       args: ["import-asset", root.dir, noteId, source] });
    }

    /// Absolute path of an asset. An absolute value is passed through: a drawing made by
    /// the tablet's live draw is written outside the store and referenced where it lies
    /// until something moves it.
    function assetPath(noteId: string, asset: string): string {
        const name = String(asset ?? "");
        if (name.length === 0)
            return "";
        return name.charAt(0) === "/" ? name : `${root.assetsDir}/${noteId}/${name}`;
    }

    function applyResult(op: var, raw: string): void {
        if (!op)
            return;
        let parsed = null;
        try {
            parsed = JSON.parse(String(raw ?? "").trim() || "{}");
        } catch (error) {
            parsed = { error: "the notes store helper returned invalid JSON" };
        }
        if (parsed.error) {
            root.lastError = String(parsed.error);
            console.warn("[NotesStore]", op.tag, "failed:", root.lastError);
        }
        if (op.tag === "init") {
            root.initialised = true;
            root.hasIndexFile = parsed.hasIndex === true;
            // Reading only now: before the tree exists the load is a guaranteed miss, and
            // the miss is what the service reads as "migrate".
            // Only worth re-reading if the eager load has not already happened.
            if (!root.indexLoaded)
                indexFile.reload();
        }
        if (op.tag === "prepareAssets" && parsed.ok === true)
            root.assetsReady(String(op.noteId ?? ""));
        if (op.tag === "readAsset")
            root.assetRead(String(op.noteId ?? ""), String(op.name ?? ""),
                           parsed.missing === true ? null : (parsed.contents ?? null));
        if (op.tag === "importAsset" && parsed.ok === true)
            root.assetImported(String(op.noteId ?? ""), String(parsed.name ?? ""));
        root.committed(String(op.tag ?? ""), parsed);
    }

    Process {
        id: opProc
        property var op: null
        property string payload: ""
        property bool outputSeen: false

        onRunningChanged: {
            if (!opProc.running)
                return;
            opProc.outputSeen = false;
            // Closing stdin is what makes the helper read: it blocks on EOF, so the
            // channel is opened and closed whether or not there is a payload.
            opProc.stdinEnabled = true;
            opProc.write(opProc.payload);
            opProc.stdinEnabled = false;
        }

        stdout: StdioCollector {
            id: opCollector
            onStreamFinished: {
                opProc.outputSeen = true;
                root.applyResult(opProc.op, opCollector.text);
            }
        }

        onExited: {
            if (!opProc.outputSeen)
                root.applyResult(opProc.op, JSON.stringify({ error: "the notes store helper exited without an answer" }));
            Qt.callLater(root.runNext);
        }
    }

    Component.onCompleted: root.init()
    Component.onDestruction: root.flushAll()
}
