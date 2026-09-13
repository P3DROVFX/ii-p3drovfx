pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services
import qs.services.notes
import "notes/NotesDocument.js" as Doc
import "notes/NotesMarkdown.js" as Markdown
import "notes/NotesMigration.js" as Migration

/**
 * The single owner of the notes store.
 *
 * A note used to be `{ title, icon, content, sketch }` inside one `notes.json` that was
 * read and rewritten in full on every keystroke. It is now an entry in an index plus a
 * document of addressable blocks in a file of its own — which is what lets a note hold a
 * heading, an indented list, a code block, a picture and a drawing at once, and what stops
 * typing in one note from rewriting every other one.
 *
 * Two APIs live here on purpose.
 *
 *   **The store API** (`notes`, `createNote`, `applyOps`, `loadDocument`, …) is what the
 *   notes app is built on.
 *
 *   **The legacy API** (`tabsData`, `updateTab`, `replaceTabs`, `createSketch`, …) is the
 *   exact surface the game overlay, the two desktop widgets and the AI integration
 *   already call, projected onto the new model. Those surfaces are not touched in this
 *   change and must not regress: a note written in the overlay is the same note the app
 *   opens, in both directions, from the first commit rather than at the end.
 *
 * The bridge is temporary by design. It goes when those surfaces are ported.
 */
Singleton {
    id: root

    readonly property NotesStore store: NotesStore {
        onReady: root.onStoreReady()
        onIndexUpdated: root.rebuildProjection()
        onDocumentReady: (noteId, document) => root.onDocumentReady(noteId, document)
        onWriteFinished: (ok, error) => root.writeFinished(ok, error)
        onCommitted: (tag, result) => root.onCommitted(tag, result)
        onAssetImported: (noteId, name) => root.assetImported(noteId, name)
        onAssetRead: (noteId, name, contents) => root.assetRead(noteId, name, contents)
        onAssetsReady: noteId => root.assetsReady(noteId)
    }

    // ── State ─────────────────────────────────────────────────────────────

    /// The store is readable and, if there was anything to migrate, migrated.
    property bool ready: false
    property string lastError: store.lastError

    readonly property var index: store.index
    /// Notes that are not in the trash, in index order.
    readonly property var notes: Doc.asArray(store.index.notes).filter(note => note.trashedAt === 0)
    readonly property var notebooks: Doc.asArray(store.index.notebooks)

    signal dataChanged()
    signal writeFinished(bool success, string error)
    signal noteChanged(string noteId)
    signal migrationCompleted(int count)
    /// A file has been copied into a note's folder and can be referenced by name.
    signal assetImported(string noteId, string name)
    signal assetRead(string noteId, string name, var contents)
    signal assetsReady(string noteId)

    // ── Store API ─────────────────────────────────────────────────────────

    function noteById(noteId: string): var {
        return root.notes.find(note => note.id === noteId) ?? null;
    }

    function noteIndexOf(noteId: string): int {
        return root.notes.findIndex(note => note.id === noteId);
    }

    function documentOf(noteId: string): var {
        return store.documentOf(noteId);
    }

    function assetPath(noteId: string, asset: string): string {
        return store.assetPath(noteId, asset);
    }

    /**
     * Copies a file into a note's own folder.
     *
     * The answer arrives on `assetImported`, not as a return value: the helper renames
     * around a name that is already taken, so what the file ends up called is not known
     * until it has been written.
     */
    function importAsset(noteId: string, source: string): void {
        store.importAsset(noteId, source);
    }

    /**
     * The vector strokes of a drawing, kept beside the picture rather than inside the note.
     *
     * A full page of ink is thousands of points, and the document is read and rewritten
     * every time somebody types a character in the same note. The picture is what every
     * surface shows; the strokes are what makes a second edit *continue* the drawing
     * instead of painting over a flat image.
     */
    /// Creates a note's asset folder and answers on `assetsReady`. Saving an image writes
    /// straight to a path, so the folder has to be there before the grab is written.
    function prepareAssets(noteId: string): void {
        store.prepareAssets(noteId);
    }

    function newInkAsset(): string {
        return `ink-${new Date().toISOString().replace(/[:.]/g, "-")}.png`;
    }

    function readStrokes(noteId: string, name: string): void {
        store.readAsset(noteId, name);
    }

    function writeStrokes(noteId: string, name: string, strokes: var): void {
        store.writeAsset(noteId, name, { version: 1, strokes: strokes });
    }

    function newStrokesName(): string {
        return `strokes-${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
    }

    /**
     * Writes the index, replacing the note records wholesale.
     *
     * Everything that changes structure goes through here so there is one place that
     * normalises, refreshes residents and republishes.
     */
    function commitIndex(notesList: var, notebooksList = null): void {
        store.putIndex({
            schema: Doc.INDEX_SCHEMA,
            notebooks: notebooksList === null ? store.index.notebooks : notebooksList,
            notes: notesList
        });
    }

    function allNoteRecords(): var {
        return Doc.asArray(store.index.notes).map(note => Doc.normalizeNote(note));
    }

    function defaultNotebookId(): string {
        const books = Doc.asArray(store.index.notebooks);
        return books.length > 0 ? books[0].id : "";
    }

    function defaultSectionId(): string {
        const books = Doc.asArray(store.index.notebooks);
        if (books.length === 0)
            return "";
        const sections = Doc.asArray(books[0].sections);
        return sections.length > 0 ? sections[0].id : "";
    }

    /// Makes sure there is somewhere for a note to live. A store whose only notebook was
    /// deleted still has to accept the next note.
    function ensureNotebook(): void {
        if (Doc.asArray(store.index.notebooks).length > 0)
            return;
        const notebook = Doc.normalizeNotebook({
            title: Translation.tr("Notes"),
            icon: "book",
            sections: [{ title: Translation.tr("General") }]
        });
        store.putIndex({
            schema: Doc.INDEX_SCHEMA,
            notebooks: [notebook],
            notes: store.index.notes
        });
    }

    function createNote(options = null): string {
        root.ensureNotebook();
        const opts = options ?? ({});
        const note = Doc.newNote({
            title: opts.title,
            icon: opts.icon,
            notebookId: opts.notebookId ?? root.defaultNotebookId(),
            sectionId: opts.sectionId ?? root.defaultSectionId(),
            tags: opts.tags,
            created: Date.now()
        });
        const document = opts.document
            ? Doc.normalizeDocument(opts.document, note.id)
            : Doc.newDocument(note.id);

        // Seeded first: committing the index is what creates the object that owns this
        // note's file, and handing it the document afterwards would be a race with it.
        store.seedDocument(note.id, document);
        const records = root.allNoteRecords();
        records.push(Doc.noteFromDocument(note, document, note.created));
        root.commitIndex(records);
        return note.id;
    }

    /// Applies block operations to a note and writes the result. The one mutation path.
    function applyOps(noteId: string, ops: var): var {
        const current = store.documentOf(noteId);
        if (current === null)
            return { ok: false, error: "notLoaded" };
        const result = Doc.applyOps(current, ops);
        if (!result.changed)
            return { ok: true, changed: false, inverse: [] };
        // Before the change lands, not after: a version you can go back to is the note as
        // it was, and the only moment that document still exists is this one.
        root.snapshotIfDue(noteId, current);
        root.writeDocument(noteId, result.document);
        return { ok: true, changed: true, inverse: result.inverse };
    }

    /// When each note was last kept, in memory only: a fresh shell takes one snapshot per
    /// note on the first edit, which is exactly the restore point somebody wants.
    property var snapshotTimes: ({})

    /// A quarter of an hour between automatic versions.
    ///
    /// Short enough that an afternoon of writing leaves a trail, long enough that a
    /// sentence typed at speed does not write fifty files. The helper keeps the last fifty
    /// per note and drops the rest, so this cannot grow without bound.
    readonly property int snapshotInterval: 15 * 60 * 1000

    function snapshotIfDue(noteId, document): void {
        if (!document)
            return;
        const now = Date.now();
        const last = root.snapshotTimes[noteId] ?? 0;
        if (now - last < root.snapshotInterval)
            return;
        const times = Object.assign({}, root.snapshotTimes);
        times[noteId] = now;
        root.snapshotTimes = times;
        const record = root.allNoteRecords().find(note => note.id === noteId);
        NotesRevisions.saveSnapshot(noteId, record ? record.title : "", document.blocks, "auto");
    }

    function updateMeta(noteId: string, patch: var): bool {
        const records = root.allNoteRecords();
        const at = records.findIndex(note => note.id === noteId);
        if (at < 0)
            return false;
        const merged = Object.assign({}, records[at], patch ?? {});
        merged.id = records[at].id;
        records[at] = Doc.normalizeNote(merged);
        root.commitIndex(records);
        return true;
    }

    /// To the trash, not gone. `trashedAt` is the single fact: a note is in the trash if
    /// and only if it carries a date.
    function deleteNote(noteId: string): bool {
        return root.updateMeta(noteId, { trashedAt: Date.now() });
    }

    function restoreNote(noteId: string): bool {
        return root.updateMeta(noteId, { trashedAt: 0 });
    }

    /// Irreversible: the record, the document, the assets and the revisions.
    function purgeNote(noteId: string): bool {
        const records = root.allNoteRecords().filter(note => note.id !== noteId);
        root.commitIndex(records);
        store.purge(noteId);
        return true;
    }

    function flush(noteId = ""): void {
        if (String(noteId ?? "").length > 0)
            store.flushDocument(noteId);
        else
            store.flushAll();
    }

    // ── Writing a document ────────────────────────────────────────────────
    // A note's file only exists once the index that names it does, and the object that
    // owns that file is created from the index. So a document written in the same turn as
    // the note was created can arrive before its writer does; it waits here rather than
    // being dropped.

    property var pendingDocuments: ({})

    function writeDocument(noteId: string, document: var): void {
        const normalised = Doc.normalizeDocument(document, noteId);
        root.contentOverrides[noteId] = undefined;
        if (!store.putDocument(noteId, normalised)) {
            root.pendingDocuments[noteId] = normalised;
            pendingWriteTimer.restart();
            return;
        }
        root.refreshNoteRecord(noteId, normalised);
        root.rebuildProjection();
        root.noteChanged(noteId);
    }

    function updateDocument(noteId, document) {
        root.writeDocument(noteId, document);
    }

    function restoreRevision(noteId, revisionDoc) {
        if (!noteId || !revisionDoc)
            return false;
        root.writeDocument(noteId, revisionDoc);
        if (revisionDoc.title)
            root.updateMeta(noteId, { title: revisionDoc.title });
        return true;
    }

    /// Whether any note is waiting to be mentioned, so the timer below can stay stopped
    /// the rest of the time instead of waking every twenty seconds to find nothing.
    readonly property bool remindersPending: root.notes.some(note => note.reminder > 0 && !note.reminderDone)

    Timer {
        id: reminderTimer
        interval: 20000
        repeat: true
        running: root.ready && root.remindersPending
        // Once on arming, too: a reminder that came due while the shell was not running
        // should be said when it starts, not twenty seconds later.
        triggeredOnStart: true
        onTriggered: {
            const now = Date.now();
            for (const note of Array.from(root.notes)) {
                if (note.reminder <= 0 || note.reminderDone || note.reminder > now)
                    continue;
                Notifications.publishInternalNotification({
                    summary: note.title.length > 0 ? note.title : Translation.tr("A note"),
                    body: note.preview.length > 0 ? note.preview : Translation.tr("You asked to be reminded about this note."),
                    appName: "Notes",
                    appIcon: "note_stack"
                });
                root.updateMeta(note.id, { reminderDone: true });
            }
        }
    }

    Timer {
        id: pendingWriteTimer
        interval: 50
        repeat: true
        onTriggered: {
            let remaining = false;
            for (const noteId in root.pendingDocuments) {
                const document = root.pendingDocuments[noteId];
                if (document === undefined)
                    continue;
                if (store.putDocument(noteId, document)) {
                    root.pendingDocuments[noteId] = undefined;
                    root.refreshNoteRecord(noteId, document);
                    root.noteChanged(noteId);
                } else {
                    remaining = true;
                }
            }
            if (!remaining) {
                pendingWriteTimer.stop();
                root.rebuildProjection();
            }
        }
    }

    /// Keeps the index's derived fields — preview, counts, icon, modified — in step with
    /// the document. Nothing else computes a preview, so every surface shows the same
    /// words.
    function refreshNoteRecord(noteId: string, document: var): void {
        const records = root.allNoteRecords();
        const at = records.findIndex(note => note.id === noteId);
        if (at < 0)
            return;
        const updated = Doc.noteFromDocument(records[at], document, Date.now());
        if (updated.icon === "article")
            updated.icon = Doc.iconFor(document);
        if (JSON.stringify(updated) === JSON.stringify(records[at]))
            return;
        records[at] = updated;
        root.commitIndex(records);
    }

    function onDocumentReady(noteId, document) {
        // A document read from disk is the truth again; whatever text the bridge was
        // holding verbatim for this note no longer applies.
        root.contentOverrides[noteId] = undefined;
        root.rebuildProjection();
    }

    // ── Bootstrap and migration ───────────────────────────────────────────

    property bool legacySettled: false
    property var legacyValue: null
    property bool migrating: false

    function onStoreReady() {
        root.maybeMigrate();
    }

    function maybeMigrate() {
        if (root.ready || root.migrating || !store.initialised || !store.indexLoaded)
            return;
        if (store.hasIndexFile) {
            root.ready = true;
            root.rebuildProjection();
            root.reportReady("opened");
            return;
        }
        if (!root.legacySettled) {
            // Nothing on disk. Now — and only now — is the old file worth opening.
            root.legacyWanted = true;
            return;
        }

        root.migrating = true;
        const plan = Migration.migrateLegacy(root.legacyValue, {
            now: Date.now(),
            notebookTitle: Translation.tr("Notes"),
            sectionTitle: Translation.tr("General"),
            untitled: Translation.tr("Untitled note")
        });

        const batch = {
            files: Migration.filesFor(plan),
            copies: plan.assets.map(asset => ({
                from: asset.from,
                to: `assets/${asset.noteId}/${asset.to}`
            })),
            // Renamed, never deleted: it is the only copy of everything written before the
            // app existed.
            renames: plan.stats.notes > 0 && root.legacyValue !== null
                ? [{ from: Directories.notesPath, to: Directories.notesLegacyBackupPath }]
                : []
        };
        // The copies name the file inside the store; the block names it relative to the
        // note, which is what `assetPath` resolves.
        store.commit(batch, "migrate");
        root.migratedIndex = plan.index;
        root.migrationCount = plan.stats.notes;
    }

    property int migrationCount: 0
    property var migratedIndex: null

    /// One line saying what the store holds. The notes app does not exist yet, so this is
    /// the only way to see that the bridge found the notes rather than an empty store —
    /// and it stays useful afterwards, when somebody asks why a note is missing.
    function reportReady(how) {
        const drawings = root.notes.filter(note => note.hasInk).length;
        console.log(`[NotesService] ${how}: ${root.notes.length} notes, ${drawings} with ink,`,
                    `${Doc.asArray(store.index.notes).length - root.notes.length} in the trash`);
    }

    function onCommitted(tag, result) {
        if (tag !== "migrate")
            return;
        root.migrating = false;
        root.ready = true;
        if (result.error) {
            root.lastError = String(result.error);
            root.rebuildProjection();
            return;
        }
        // The helper reported which files it actually wrote, so the plan's index is what
        // is on disk. Adopting it is not an optimisation: a FileView that has loaded once
        // does not re-announce a load, so a reload alone would leave the store holding the
        // empty index it had a moment ago.
        store.adoptIndex(root.migratedIndex);
        root.migratedIndex = null;
        root.reportReady(`migrated ${root.migrationCount} note(s) from notes.json`);
        if (root.migrationCount > 0)
            root.migrationCompleted(root.migrationCount);
    }

    /// Set only when the store turned out to have no index. A shell that has already
    /// migrated never opens `notes.json` again — reading a file that was deliberately
    /// renamed would log a failure on every single startup, for nothing.
    property bool legacyWanted: false

    FileView {
        // Read only. The legacy file is never written again; it is renamed once its notes
        // have been carried across.
        id: legacyFile
        path: root.legacyWanted ? Qt.resolvedUrl(Directories.notesPath) : ""

        onLoaded: {
            try {
                root.legacyValue = JSON.parse(legacyFile.text());
            } catch (error) {
                root.legacyValue = null;
            }
            root.legacySettled = true;
            root.maybeMigrate();
        }

        onLoadFailed: {
            // No legacy file at all — a fresh install. There is simply nothing to carry.
            root.legacyValue = null;
            root.legacySettled = true;
            root.maybeMigrate();
        }
    }

    // ── The legacy bridge ─────────────────────────────────────────────────

    readonly property var defaultTabs: [
        { title: "Tab 1", icon: "article", content: "" }
    ]

    /// The projection the old surfaces read. One tab per non-trashed note, in index order.
    property var tabsData: ({ tabs: [] })

    /// Text the bridge hands back exactly as it was given.
    ///
    /// Re-deriving it from the document would round-trip through markdown, and a
    /// normalisation that changed one character while somebody was typing would reset
    /// their text field under the cursor.
    property var contentOverrides: ({})

    readonly property bool writing: store.writing
    /// The old service exposed a pending-write buffer and the overlay reads it to draw a
    /// "saving" hint. There is no single buffer any more, so this answers the only
    /// question that was ever asked of it: is anything still on its way to disk.
    readonly property var pendingData: store.writing ? ({}) : null

    /// The blocks markdown shows as text. Ink is projected as the separate `sketch` field
    /// the old shape has, so a drawing never appears to the user as `![ink](…)` inside
    /// their own text.
    function textBlocksOf(document): var {
        return Doc.asArray(document.blocks).filter(item => item.type !== "ink");
    }

    function inkBlocksOf(document): var {
        return Doc.asArray(document.blocks).filter(item => item.type === "ink");
    }

    function legacyContentOf(noteId, document): string {
        const override = root.contentOverrides[noteId];
        if (override !== undefined)
            return override;
        return Markdown.toMarkdown({ id: noteId, blocks: root.textBlocksOf(document) });
    }

    function legacySketchOf(noteId, document): string {
        const ink = root.inkBlocksOf(document);
        return ink.length > 0 ? store.assetPath(noteId, ink[0].asset) : "";
    }

    function rebuildProjection(): void {
        const tabs = root.notes.map(note => {
            const document = store.documentOf(note.id);
            if (document === null) {
                // The record exists, the file has not arrived yet. The preview is the
                // honest answer for one frame; it is replaced as soon as the file loads.
                return { noteId: note.id, title: note.title, icon: note.icon,
                         content: note.preview, sketch: "" };
            }
            return {
                noteId: note.id,
                title: note.title,
                icon: note.icon,
                content: root.legacyContentOf(note.id, document),
                sketch: root.legacySketchOf(note.id, document)
            };
        });
        const next = { tabs: tabs };
        if (JSON.stringify(next) === JSON.stringify(root.tabsData))
            return;
        root.tabsData = next;
        root.dataChanged();
    }

    function noteIdForTab(index: int): string {
        const tabs = Doc.asArray(root.tabsData.tabs);
        if (index < 0 || index >= tabs.length)
            return "";
        return String(tabs[index].noteId ?? "");
    }

    function snapshot(): var {
        return JSON.parse(JSON.stringify(root.tabsData));
    }

    function reload(): void {
        store.reloadIndex();
    }

    /**
     * Replaces a note's text, keeping everything markdown cannot say.
     *
     * The drawing is the reason this is not just a parse: markdown carries the file a
     * drawing points at but not its proportions or its vector strokes, and re-anchoring
     * onto the previous document is what keeps an edit to the *text* from quietly
     * flattening the *picture*.
     */
    function documentFromLegacyContent(noteId, content): var {
        const previous = store.documentOf(noteId) ?? Doc.newDocument(noteId);
        const parsed = Markdown.fromMarkdown(content, { noteId: noteId });
        const blocks = Doc.asArray(parsed.blocks).concat(root.inkBlocksOf(previous));
        return Markdown.mergeParsed(previous, { id: noteId, blocks: blocks });
    }

    function updateTab(index: int, content: string): bool {
        const noteId = root.noteIdForTab(index);
        if (noteId.length === 0)
            return false;
        const text = String(content ?? "");
        if (root.contentOverrides[noteId] === text)
            return true;
        const document = root.documentFromLegacyContent(noteId, text);
        root.writeDocument(noteId, document);
        root.contentOverrides[noteId] = text;
        root.rebuildProjection();
        return true;
    }

    function updateTabMetadata(index: int, title: string, icon: string): bool {
        const noteId = root.noteIdForTab(index);
        if (noteId.length === 0)
            return false;
        return root.updateMeta(noteId, {
            title: String(title ?? "").split("\n")[0] || "Tab",
            icon: String(icon ?? "article").split("\n")[0] || "article"
        });
    }

    function deleteTab(index: int): bool {
        const noteId = root.noteIdForTab(index);
        if (noteId.length === 0)
            return false;
        root.deleteNote(noteId);
        // The old shape can never be empty: the overlay draws a tab strip and an editor,
        // and both need something to point at.
        if (root.notes.length === 0)
            root.createNote({ title: "Tab 1" });
        return true;
    }

    /**
     * The whole tab list at once — how the old surfaces add and remove notes.
     *
     * Matched by the `noteId` the projection carries on each tab. The callers all build
     * their new list by slicing the one they were given, so the tabs that survive keep
     * their identity, and only the ones they invented arrive without an id.
     */
    function replaceTabs(value: var): bool {
        const incoming = Doc.asArray(value?.tabs);
        const existing = root.allNoteRecords();
        const known = {};
        existing.forEach(note => known[note.id] = note);

        const kept = {};
        const order = [];
        for (const tab of incoming) {
            const noteId = String(tab?.noteId ?? "");
            if (noteId.length > 0 && known[noteId] && known[noteId].trashedAt === 0) {
                kept[noteId] = true;
                order.push(noteId);
                const record = known[noteId];
                const title = String(tab.title ?? "").split("\n")[0];
                const icon = String(tab.icon ?? "article").split("\n")[0] || "article";
                if (record.title !== title || record.icon !== icon)
                    known[noteId] = Doc.normalizeNote(Object.assign({}, record, { title: title, icon: icon }));
                const currentContent = root.legacyContentOf(noteId, store.documentOf(noteId) ?? Doc.newDocument(noteId));
                const wanted = String(tab.content ?? "");
                if (currentContent !== wanted)
                    root.updateTabById(noteId, wanted);
                continue;
            }
            order.push(root.createNoteFromTab(tab));
        }

        // Anything the caller left out is a note they removed.
        const records = root.allNoteRecords().map(note => {
            if (known[note.id] && known[note.id] !== note)
                note = known[note.id];
            if (note.trashedAt === 0 && !kept[note.id] && !order.includes(note.id))
                return Doc.normalizeNote(Object.assign({}, note, { trashedAt: Date.now() }));
            return note;
        });
        root.commitIndex(records);
        return true;
    }

    function updateTabById(noteId, content) {
        const text = String(content ?? "");
        root.writeDocument(noteId, root.documentFromLegacyContent(noteId, text));
        root.contentOverrides[noteId] = text;
    }

    function createNoteFromTab(tab): string {
        const content = String(tab?.content ?? "");
        const sketch = String(tab?.sketch ?? "");
        const noteId = root.createNote({
            title: String(tab?.title ?? "").split("\n")[0],
            icon: String(tab?.icon ?? "article").split("\n")[0] || "article"
        });
        const blocks = Doc.asArray(Markdown.fromMarkdown(content, { noteId: noteId }).blocks);
        if (sketch.length > 0)
            blocks.push(Doc.block("ink", { asset: sketch }));
        root.writeDocument(noteId, { id: noteId, blocks: blocks });
        root.contentOverrides[noteId] = content;
        return noteId;
    }

    function append(index: int, text: string, provenance = null): var {
        const noteId = root.noteIdForTab(index);
        if (noteId.length === 0)
            return { ok: false, error: "unknownNote" };
        const addition = String(text ?? "").trim();
        if (addition.length === 0)
            return { ok: false, error: "emptyText" };

        const document = store.documentOf(noteId);
        if (document === null)
            return { ok: false, error: "notReady" };
        const previous = root.legacyContentOf(noteId, document).trimEnd();
        const merged = previous.length > 0 ? `${previous}\n\n${addition}` : addition;
        root.updateTabById(noteId, merged);
        root.rebuildProjection();

        const note = root.noteById(noteId);
        return {
            ok: true,
            index: root.noteIndexOf(noteId),
            title: note ? note.title : "",
            content: merged,
            provenance: root.safeProvenance(provenance)
        };
    }

    function create(title: string, content: string, provenance = null): var {
        if (!root.ready)
            return { ok: false, error: "notReady" };
        const noteTitle = String(title ?? "").trim() || Translation.tr("AI note");
        const noteContent = String(content ?? "").trim();
        if (noteContent.length === 0)
            return { ok: false, error: "emptyText" };
        const noteId = root.createNoteFromTab({
            title: noteTitle.slice(0, 120), icon: "article", content: noteContent
        });
        root.rebuildProjection();
        return {
            ok: true,
            index: root.noteIndexOf(noteId),
            title: noteTitle.slice(0, 120),
            content: noteContent,
            provenance: root.safeProvenance(provenance)
        };
    }

    // ── Sketches ──────────────────────────────────────────────────────────

    /**
     * Where the next drawing goes.
     *
     * Still the legacy sketches folder, and still timestamped. The tablet's live draw
     * writes the file before any note exists to attach it to, so it cannot be written
     * inside a note's asset folder — the note is created afterwards, from the path.
     */
    function newSketchPath(): string {
        const stamp = new Date().toISOString().replace(/[:.]/g, "-");
        return `${Directories.noteSketchesDir}/sketch-${stamp}.png`;
    }

    function ensureSketchDir(): void {
        sketchDirMaker.running = false;
        Qt.callLater(() => sketchDirMaker.running = true);
    }

    Process {
        id: sketchDirMaker
        command: ["mkdir", "-p", Directories.noteSketchesDir]
    }

    function createSketch(path: string, title): var {
        const file = String(path ?? "").trim();
        if (file.length === 0)
            return { ok: false, error: "emptyPath" };
        if (!root.ready)
            return { ok: false, error: "notReady" };
        const noteTitle = String(title ?? "").trim()
            || Translation.tr("Sketch %1").arg(Qt.formatDateTime(new Date(), "d MMM, HH:mm"));
        const noteId = root.createNote({ title: noteTitle.slice(0, 120), icon: "draw" });
        root.writeDocument(noteId, {
            id: noteId,
            blocks: [Doc.block("text", {}), Doc.block("ink", { asset: file })]
        });
        root.rebuildProjection();
        return { ok: true, index: root.noteIndexOf(noteId), title: noteTitle, sketch: file };
    }

    function setSketch(index: int, path: string): bool {
        const noteId = root.noteIdForTab(index);
        if (noteId.length === 0)
            return false;
        const document = store.documentOf(noteId);
        if (document === null)
            return false;
        const file = String(path ?? "");
        const blocks = root.textBlocksOf(document);
        if (file.length > 0)
            blocks.push(Doc.block("ink", { asset: file }));
        root.writeDocument(noteId, { id: noteId, blocks: blocks });
        if (file.length > 0) {
            const note = root.noteById(noteId);
            if (note && note.icon === "article")
                root.updateMeta(noteId, { icon: "draw" });
        }
        root.rebuildProjection();
        return true;
    }

    function clearSketch(index: int): bool {
        return root.setSketch(index, "");
    }

    function safeProvenance(value): var {
        const candidate = value ?? ({});
        return {
            sessionId: String(candidate.sessionId ?? "").slice(0, 120),
            messageId: String(candidate.messageId ?? "").slice(0, 120)
        };
    }
}
