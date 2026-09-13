.pragma library
.import "NotesDocument.js" as Doc
.import "NotesMarkdown.js" as Markdown

// From `notes.json` to the notes store.
//
// The old shape is one file holding a flat list of tabs, each a title, an icon, a string
// of content and optionally the absolute path of one drawing. The new shape is an index
// plus one document per note, with assets filed under the note that owns them.
//
// This module does the *transform* and nothing else. It reads no files and writes none:
// it takes the parsed legacy value and returns a description of the store that should
// exist, including which sketch files should be copied where. That is what makes a dry
// run possible — the same code that performs the migration can be asked what it would do
// without being allowed to do it, which is the only honest way to promise that the
// original file is not touched.

/**
 * The plan for migrating `legacy` into the store.
 *
 * Options:
 *   now              - the clock, injected so a test is not at the mercy of one
 *   notebookTitle    - the notebook every migrated note lands in (translated by the caller)
 *   sectionTitle     - the section inside it
 *   dropEmptyDefaults- skip untouched default tabs ("Tab 3" with nothing in it). Default
 *                      true: those carry no information, and three empty notes on first
 *                      launch look like the migration invented them.
 *
 * Returns { index, documents, assets, stats, skipped } where `documents` is a list of
 * { noteId, document } and `assets` a list of { noteId, from, to } copies to perform.
 */
function migrateLegacy(legacy, options) {
    var opts = options && typeof options === "object" ? options : {};
    var now = Number(opts.now) || Date.now();
    var dropEmpty = opts.dropEmptyDefaults === undefined ? true : opts.dropEmptyDefaults === true;

    var source = legacy && typeof legacy === "object" ? legacy : {};
    var tabs = Array.isArray(source.tabs) ? source.tabs : [];

    var notebookId = Doc.newNotebookId();
    var sectionId = Doc.newSectionId();
    var notebook = {
        id: notebookId,
        title: String(opts.notebookTitle || "Notes"),
        icon: "book",
        color: "",
        order: 0,
        sections: [{ id: sectionId, title: String(opts.sectionTitle || "General"), order: 0 }]
    };

    var notes = [];
    var documents = [];
    var assets = [];
    var skipped = [];
    var withInk = 0;

    for (var i = 0; i < tabs.length; i++) {
        var tab = tabs[i] && typeof tabs[i] === "object" ? tabs[i] : {};
        var title = String(tab.title === null || tab.title === undefined ? "" : tab.title).trim();
        var content = String(tab.content === null || tab.content === undefined ? "" : tab.content);
        var sketch = String(tab.sketch === null || tab.sketch === undefined ? "" : tab.sketch).trim();

        if (dropEmpty && isUntouchedDefault(title, content, sketch)) {
            skipped.push({ position: i, title: title });
            continue;
        }

        var noteId = Doc.newNoteId();
        var document = Markdown.fromMarkdown(content, { noteId: noteId });

        if (sketch.length > 0) {
            var assetName = baseName(sketch);
            assets.push({ noteId: noteId, from: sketch, to: assetName });
            // Appended rather than placed first: in the old model the drawing was a
            // property of the note, with no position at all, and the end is where a
            // reader expects the picture that came with the text.
            document.blocks.push(Doc.block("ink", { asset: assetName }));
            withInk++;
        }

        document = Doc.normalizeDocument(document, noteId);
        var stamp = timestampFor(sketch, now);
        var note = Doc.newNote({
            id: noteId,
            title: title,
            icon: String(tab.icon || "").trim() || Doc.iconFor(document),
            notebookId: notebookId,
            sectionId: sectionId,
            created: stamp,
            modified: stamp
        });
        note = Doc.noteFromDocument(note, document, stamp);
        if (note.title.length === 0)
            note.title = String(opts.untitled || "Untitled note");

        notes.push(note);
        documents.push({ noteId: noteId, document: document });
    }

    var index = Doc.normalizeIndex({
        schema: Doc.INDEX_SCHEMA,
        // A notebook with nothing in it would be an empty shelf the user never asked for.
        notebooks: notes.length > 0 ? [notebook] : [],
        notes: notes
    });

    return {
        index: index,
        documents: documents,
        assets: assets,
        skipped: skipped,
        stats: {
            tabs: tabs.length,
            notes: notes.length,
            skipped: skipped.length,
            withInk: withInk,
            withText: notes.filter(function (note) { return note.preview.length > 0; }).length
        }
    };
}

/// A tab the user never touched: the default name the old service hands out, no text and
/// no drawing. A note deliberately named "Tab 4" that has content in it is not this.
function isUntouchedDefault(title, content, sketch) {
    if (content.trim().length > 0 || sketch.length > 0)
        return false;
    return title.length === 0 || /^Tab \d+$/.test(title);
}

function baseName(path) {
    var parts = String(path).split("/");
    return parts[parts.length - 1] || String(path);
}

/**
 * The date a note was made, recovered from its sketch filename when there is one.
 *
 * The old format stored no dates at all, so every migrated note would otherwise be
 * created at the instant of the migration — a notes list sorted by date showing a year of
 * drawings all made this morning. `NotesService.newSketchPath` timestamps the file, and
 * that timestamp is the only real date the old format ever recorded.
 */
function timestampFor(sketchPath, fallback) {
    var match = /(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})-(\d{3})Z/.exec(String(sketchPath));
    if (!match)
        return fallback;
    var iso = match[1] + "-" + match[2] + "-" + match[3] + "T"
        + match[4] + ":" + match[5] + ":" + match[6] + "." + match[7] + "Z";
    var parsed = Date.parse(iso);
    return isFinite(parsed) ? parsed : fallback;
}

/// The files a completed migration should produce, as { path, contents } pairs relative to
/// the store root. The caller writes them; nothing here knows what a filesystem is.
function filesFor(plan) {
    var files = [{ path: "index.json", contents: plan.index }];
    for (var i = 0; i < plan.documents.length; i++) {
        files.push({
            path: "docs/" + plan.documents[i].noteId + ".json",
            contents: plan.documents[i].document
        });
    }
    return files;
}
