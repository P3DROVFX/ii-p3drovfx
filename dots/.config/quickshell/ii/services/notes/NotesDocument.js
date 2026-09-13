.pragma library

// The notes document model, and every operation that can change it.
//
// A note is not a string. `notes.json` made it one, and that decision is what makes the
// current notes unable to hold a picture, a code snippet or an indented list: the only
// thing a string can carry is more string. Here a note is an ordered list of *blocks*,
// each one addressable by a stable id, and the structure — what is a heading, what is a
// list, where the drawing goes — is the block's type rather than syntax buried in text.
//
// Everything in this file is pure. No QML, no singletons, no file access, no clock it
// does not receive. That is deliberate: the shell can only be tested by running the
// shell, and the arithmetic of a document is the part most worth checking without one.
// The same reason `StrokeGeometry.js` exists next to the ink instead of inside it.
//
// Two rules the rest of the app depends on:
//
//   1. Nothing here throws. A document read back from a half-written file, from an older
//      schema, or from something that was never a document at all, normalises into a
//      valid document. A note that opens empty is a bad day; a note that crashes the
//      editor is a lost note.
//
//   2. Nothing here mutates its input. `applyOps` returns a new document and the exact
//      operations that undo it. Undo, redo and revision history are all that invariant.

var DOCUMENT_SCHEMA = 1;
var INDEX_SCHEMA = 1;

var MAX_INDENT = 5;
var MAX_HEADING_LEVEL = 3;
var PREVIEW_LENGTH = 160;
var TITLE_LENGTH = 120;
var WORDS_PER_MINUTE = 220;

var LIST_STYLES = ["bullet", "number", "checkbox"];
var CALLOUT_TONES = ["info", "success", "warning", "error"];
var PAPER_STYLES = ["plain", "grid", "dots", "ruled", "ruled-margin", "isometric", "graph"];
var EMBED_KINDS = ["latex", "mermaid"];

/**
 * Every block type, and the fields it owns with their defaults.
 *
 * The table is the schema. Normalisation is driven by it rather than by a switch per
 * type, so adding a block type is one entry here plus a delegate — and an unknown field
 * arriving from a newer version of the app is dropped rather than carried into code that
 * does not expect it.
 */
var BLOCK_FIELDS = {
    text: { text: "", indent: 0 },
    heading: { text: "", level: 1 },
    list: { text: "", indent: 0, style: "bullet", checked: false },
    code: { text: "", language: "" },
    quote: { text: "", indent: 0 },
    callout: { text: "", tone: "info" },
    divider: {},
    image: { asset: "", caption: "", width: 0 },
    ink: { asset: "", aspect: 1.5, strokes: "" },
    table: { header: true, columns: 2, rows: [] },
    linkPreview: { url: "", title: "", description: "", image: "", favicon: "", fetchedAt: 0 },
    fileLink: { path: "", mime: "", size: 0, thumb: "", copied: false },
    audio: { asset: "", duration: 0 },
    embed: { kind: "latex", text: "" }
};

var BLOCK_TYPES = Object.keys(BLOCK_FIELDS);

/// Block types whose `text` field is prose the user typed. Preview, search and word
/// count read these and skip the rest; a file path is not something anyone searches for
/// by accident.
var TEXTUAL_TYPES = ["text", "heading", "list", "quote", "callout"];

// ── Identity ────────────────────────────────────────────────────────────────

var _idCounter = 0;

/**
 * A new id, unique even for ids minted in the same millisecond.
 *
 * The timestamp alone is not enough: splitting a block makes two ids in the same tick,
 * and two blocks sharing an id is a document where editing one edits the other.
 */
function newId(prefix) {
    _idCounter = (_idCounter + 1) % 1000000;
    var stamp = Date.now().toString(36);
    var salt = Math.floor(Math.random() * 1679616).toString(36);
    return String(prefix || "id") + "_" + stamp + "_" + _idCounter.toString(36) + "_" + salt;
}

function newNoteId() { return newId("nt"); }
function newBlockId() { return newId("bk"); }
function newNotebookId() { return newId("nb"); }
function newSectionId() { return newId("sc"); }

// ── Coercion helpers ────────────────────────────────────────────────────────

function clamp(value, low, high) {
    var number = Number(value);
    if (!isFinite(number))
        return low;
    return Math.max(low, Math.min(high, number));
}

function asString(value) {
    if (value === null || value === undefined)
        return "";
    if (typeof value === "string")
        return value;
    if (typeof value === "number" || typeof value === "boolean")
        return String(value);
    return "";
}

/// A single line, trimmed and capped. Titles come from user text and from imports, and a
/// newline inside one turns every list that renders it into a broken row.
function asLine(value, limit) {
    var text = asString(value).replace(/[\r\n\t]+/g, " ").trim();
    var cap = limit === undefined ? TITLE_LENGTH : limit;
    return text.length > cap ? text.slice(0, cap) : text;
}

function asInt(value, fallback) {
    var number = Number(value);
    if (!isFinite(number))
        return fallback === undefined ? 0 : fallback;
    return Math.round(number);
}

function asBool(value) {
    return value === true || value === "true" || value === 1;
}

function oneOf(value, allowed, fallback) {
    var text = asString(value);
    return allowed.indexOf(text) >= 0 ? text : fallback;
}

function asArray(value) {
    return Array.isArray(value) ? value : [];
}

// ── Blocks ──────────────────────────────────────────────────────────────────

/**
 * A new block of `type`, with `props` applied over the type's defaults.
 *
 * An unknown type becomes a text block rather than nothing: a document that lost a block
 * because a caller mistyped a string is worse than one carrying an empty paragraph.
 */
function block(type, props) {
    var kind = BLOCK_FIELDS[type] ? type : "text";
    var made = { id: newBlockId(), type: kind };
    var defaults = BLOCK_FIELDS[kind];
    for (var key in defaults)
        made[key] = cloneValue(defaults[key]);
    var overrides = props && typeof props === "object" ? props : {};
    for (var given in overrides) {
        if (given === "id") {
            var id = asString(overrides.id);
            if (id.length > 0)
                made.id = id;
        } else if (defaults.hasOwnProperty(given)) {
            made[given] = overrides[given];
        }
    }
    return normalizeBlock(made);
}

function cloneValue(value) {
    if (Array.isArray(value))
        return value.map(cloneValue);
    if (value && typeof value === "object") {
        var copy = {};
        for (var key in value)
            copy[key] = cloneValue(value[key]);
        return copy;
    }
    return value;
}

/**
 * Any value into a valid block.
 *
 * Total by construction: the type falls back to text, every field is coerced to the type
 * of its default, and anything the table does not name is dropped.
 */
function normalizeBlock(value) {
    var source = value && typeof value === "object" ? value : {};
    var type = BLOCK_FIELDS[source.type] ? source.type : "text";
    var defaults = BLOCK_FIELDS[type];
    var id = asString(source.id);
    var made = { id: id.length > 0 ? id : newBlockId(), type: type };

    for (var key in defaults) {
        var fallback = defaults[key];
        var given = source[key];
        if (typeof fallback === "string")
            made[key] = asString(given);
        else if (typeof fallback === "number")
            made[key] = isFinite(Number(given)) ? Number(given) : fallback;
        else if (typeof fallback === "boolean")
            made[key] = given === undefined ? fallback : asBool(given);
        else if (Array.isArray(fallback))
            made[key] = asArray(given);
        else
            made[key] = cloneValue(fallback);
    }

    if (made.hasOwnProperty("indent"))
        made.indent = clamp(asInt(made.indent, 0), 0, MAX_INDENT);
    if (type === "heading")
        made.level = clamp(asInt(made.level, 1), 1, MAX_HEADING_LEVEL);
    if (type === "list")
        made.style = oneOf(made.style, LIST_STYLES, "bullet");
    if (type === "callout")
        made.tone = oneOf(made.tone, CALLOUT_TONES, "info");
    if (type === "embed")
        made.kind = oneOf(made.kind, EMBED_KINDS, "latex");
    if (type === "image")
        made.width = clamp(made.width, 0, 1);
    if (type === "ink")
        made.aspect = made.aspect > 0 ? clamp(made.aspect, 0.1, 10) : 1.5;
    if (type === "audio")
        made.duration = Math.max(0, made.duration);
    if (type === "fileLink")
        made.size = Math.max(0, asInt(made.size, 0));
    if (type === "linkPreview")
        made.fetchedAt = Math.max(0, asInt(made.fetchedAt, 0));
    if (type === "table")
        normalizeTable(made);

    return made;
}

/// A table is a rectangle. Rows of differing length render as a grid with holes in it,
/// and a row longer than the column count silently loses cells at the edge.
function normalizeTable(made) {
    var rows = asArray(made.rows).map(function (row) {
        return asArray(row).map(asString);
    });
    var widest = rows.reduce(function (most, row) { return Math.max(most, row.length); }, 0);
    var columns = clamp(asInt(made.columns, 2), 1, 24);
    columns = Math.max(columns, Math.min(widest, 24));
    made.columns = columns;
    made.rows = rows.map(function (row) {
        var padded = row.slice(0, columns);
        while (padded.length < columns)
            padded.push("");
        return padded;
    });
    if (made.rows.length === 0)
        made.rows = [emptyRow(columns)];
}

function emptyRow(columns) {
    var row = [];
    for (var i = 0; i < columns; i++)
        row.push("");
    return row;
}

function isTextual(blockValue) {
    return TEXTUAL_TYPES.indexOf(blockValue.type) >= 0;
}

// ── Documents ───────────────────────────────────────────────────────────────

/// A brand new document: one empty paragraph. Zero blocks is an editor with nowhere to
/// put the cursor, which reads to the user as a note that refuses to open.
function newDocument(noteId) {
    return {
        id: asString(noteId) || newNoteId(),
        schema: DOCUMENT_SCHEMA,
        blocks: [block("text", {})]
    };
}

/**
 * Any value into a valid document.
 *
 * Idempotent: normalising an already-normalised document returns an equal one. That is
 * what lets the store normalise on read and on write without the file drifting.
 */
function normalizeDocument(value, noteId) {
    var source = value && typeof value === "object" ? value : {};
    var blocks = asArray(source.blocks).map(normalizeBlock);
    blocks = withUniqueIds(blocks);
    if (blocks.length === 0)
        blocks = [block("text", {})];
    return {
        id: asString(source.id) || asString(noteId) || newNoteId(),
        schema: DOCUMENT_SCHEMA,
        blocks: blocks
    };
}

/// Duplicate ids are the one corruption that normalisation cannot leave alone: two blocks
/// answering to the same id makes every operation ambiguous, and the editor edits both.
function withUniqueIds(blocks) {
    var seen = {};
    return blocks.map(function (item) {
        if (seen[item.id]) {
            var copy = cloneValue(item);
            copy.id = newBlockId();
            seen[copy.id] = true;
            return copy;
        }
        seen[item.id] = true;
        return item;
    });
}

/// Documents written by an older schema come back through here. Version 1 is the first,
/// so there is nothing to move yet — the hook exists so the first migration has an
/// obvious place to live instead of being invented under pressure.
function migrateDocument(value, noteId) {
    var source = value && typeof value === "object" ? value : {};
    var schema = asInt(source.schema, 0);
    if (schema > DOCUMENT_SCHEMA) {
        // Written by a newer app. Normalising drops what this version does not know
        // rather than refusing to open the note.
        return normalizeDocument(source, noteId);
    }
    return normalizeDocument(source, noteId);
}

function indexOfBlock(document, blockId) {
    var blocks = document.blocks;
    for (var i = 0; i < blocks.length; i++) {
        if (blocks[i].id === blockId)
            return i;
    }
    return -1;
}

function blockById(document, blockId) {
    var at = indexOfBlock(document, blockId);
    return at < 0 ? null : document.blocks[at];
}

// ── Operations ──────────────────────────────────────────────────────────────

/**
 * Applies `ops` to `document`, returning the new document and the operations that undo it.
 *
 * The single entry point for every change. Not because indirection is nice, but because
 * undo, revision history and (later) sync conflict resolution all need a description of
 * *what changed* rather than two documents to diff — and a codebase where the editor
 * mutates blocks in place cannot produce one.
 *
 * The inverse list is returned already reversed, so applying it in order undoes the batch.
 * The round trip is a contract: applying ops then their inverse yields the original
 * document, field for field.
 */
function applyOps(document, ops) {
    var working = normalizeDocument(document);
    var list = asArray(ops);
    var inverse = [];
    var changed = false;

    for (var i = 0; i < list.length; i++) {
        var result = applyOne(working, list[i]);
        if (!result.changed)
            continue;
        working = result.document;
        inverse.push(result.inverse);
        changed = true;
    }

    inverse.reverse();
    return { document: working, inverse: inverse, changed: changed };
}

function unchanged(document) {
    return { document: document, inverse: null, changed: false };
}

function applyOne(document, op) {
    var kind = asString(op && op.op);
    switch (kind) {
    case "insert": return opInsert(document, op);
    case "update": return opUpdate(document, op);
    case "delete": return opDelete(document, op);
    case "move": return opMove(document, op);
    case "indent": return opIndent(document, op);
    case "setType": return opSetType(document, op);
    case "split": return opSplit(document, op);
    case "merge": return opMerge(document, op);
    default: return unchanged(document);
    }
}

function replaceBlocks(document, blocks) {
    return { id: document.id, schema: document.schema, blocks: blocks };
}

function opInsert(document, op) {
    var made = op.block && op.block.id ? normalizeBlock(op.block) : block(op.block && op.block.type, op.block);
    if (indexOfBlock(document, made.id) >= 0)
        made = normalizeBlock(Object.assign({}, made, { id: newBlockId() }));
    var at = clamp(asInt(op.index, document.blocks.length), 0, document.blocks.length);
    var blocks = document.blocks.slice();
    blocks.splice(at, 0, made);
    return {
        document: replaceBlocks(document, blocks),
        inverse: { op: "delete", id: made.id },
        changed: true
    };
}

function opUpdate(document, op) {
    var at = indexOfBlock(document, asString(op.id));
    if (at < 0)
        return unchanged(document);
    var current = document.blocks[at];
    var patch = op.patch && typeof op.patch === "object" ? op.patch : {};
    var previous = {};
    var next = cloneValue(current);
    var touched = false;

    for (var key in patch) {
        if (key === "id" || key === "type")
            continue;
        if (!BLOCK_FIELDS[current.type].hasOwnProperty(key))
            continue;
        previous[key] = cloneValue(current[key]);
        next[key] = patch[key];
        touched = true;
    }
    if (!touched)
        return unchanged(document);

    next = normalizeBlock(next);
    if (JSON.stringify(next) === JSON.stringify(current))
        return unchanged(document);

    var blocks = document.blocks.slice();
    blocks[at] = next;
    return {
        document: replaceBlocks(document, blocks),
        inverse: { op: "update", id: current.id, patch: previous },
        changed: true
    };
}

function opDelete(document, op) {
    var at = indexOfBlock(document, asString(op.id));
    if (at < 0)
        return unchanged(document);
    // The last block never leaves. Deleting it would produce a document with nowhere to
    // type, and the editor would have to invent a block back — from where, with what id.
    if (document.blocks.length === 1)
        return unchanged(document);
    var removed = document.blocks[at];
    var blocks = document.blocks.slice();
    blocks.splice(at, 1);
    return {
        document: replaceBlocks(document, blocks),
        inverse: { op: "insert", index: at, block: cloneValue(removed) },
        changed: true
    };
}

function opMove(document, op) {
    var from = indexOfBlock(document, asString(op.id));
    if (from < 0)
        return unchanged(document);
    var to = clamp(asInt(op.to, from), 0, document.blocks.length - 1);
    if (to === from)
        return unchanged(document);
    var blocks = document.blocks.slice();
    var moved = blocks.splice(from, 1)[0];
    blocks.splice(to, 0, moved);
    return {
        document: replaceBlocks(document, blocks),
        inverse: { op: "move", id: moved.id, to: from },
        changed: true
    };
}

/**
 * Indentation as a property of the block, never as spaces in the text.
 *
 * The inverse carries the delta that was *applied*, not the one that was asked for.
 * Indenting a block already at the ceiling changes nothing, and an inverse built from
 * the requested delta would un-indent a block that never moved.
 */
function opIndent(document, op) {
    var at = indexOfBlock(document, asString(op.id));
    if (at < 0)
        return unchanged(document);
    var current = document.blocks[at];
    if (!BLOCK_FIELDS[current.type].hasOwnProperty("indent"))
        return unchanged(document);
    var wanted = clamp(current.indent + asInt(op.delta, 0), 0, MAX_INDENT);
    var applied = wanted - current.indent;
    if (applied === 0)
        return unchanged(document);
    var blocks = document.blocks.slice();
    blocks[at] = normalizeBlock(Object.assign(cloneValue(current), { indent: wanted }));
    return {
        document: replaceBlocks(document, blocks),
        inverse: { op: "indent", id: current.id, delta: -applied },
        changed: true
    };
}

/**
 * Turns a block into another type, keeping the id and carrying the text across.
 *
 * The id survives because this is the same block to the user — the paragraph they were
 * typing became a heading. A new id here would lose the cursor and break undo's anchor.
 */
function opSetType(document, op) {
    var at = indexOfBlock(document, asString(op.id));
    if (at < 0)
        return unchanged(document);
    var current = document.blocks[at];
    var type = BLOCK_FIELDS[op.type] ? op.type : null;
    if (!type)
        return unchanged(document);

    var props = op.props && typeof op.props === "object" ? cloneValue(op.props) : {};
    if (BLOCK_FIELDS[type].hasOwnProperty("text") && !props.hasOwnProperty("text"))
        props.text = asString(current.text);
    if (BLOCK_FIELDS[type].hasOwnProperty("indent") && !props.hasOwnProperty("indent"))
        props.indent = asInt(current.indent, 0);
    props.id = current.id;

    var next = block(type, props);
    if (JSON.stringify(next) === JSON.stringify(current))
        return unchanged(document);

    var blocks = document.blocks.slice();
    blocks[at] = next;
    return {
        document: replaceBlocks(document, blocks),
        // Restoring the whole previous block, not a field patch: a type change discards
        // fields the new type does not have, and a patch cannot bring back a field the
        // block no longer declares.
        inverse: { op: "setType", id: current.id, type: current.type, props: cloneValue(current) },
        changed: true
    };
}

/// Enter in the middle of a paragraph. The tail becomes a new block of the same type,
/// which is what makes a list stay a list when you split an item.
function opSplit(document, op) {
    var at = indexOfBlock(document, asString(op.id));
    if (at < 0)
        return unchanged(document);
    var current = document.blocks[at];
    if (!BLOCK_FIELDS[current.type].hasOwnProperty("text"))
        return unchanged(document);

    var text = asString(current.text);
    var offset = clamp(asInt(op.offset, text.length), 0, text.length);
    var head = text.slice(0, offset);
    var tail = text.slice(offset);

    // Undoing a merge, not splitting a paragraph. `restore` carries the block that was
    // absorbed — its id, its type and its fields — because a split that derived the tail
    // from the head would give the checkbox back as a paragraph, under a new id that
    // nothing else in the document refers to.
    if (op.restore && typeof op.restore === "object") {
        var restored = normalizeBlock(Object.assign(cloneValue(op.restore), { text: tail }));
        var restoredBlocks = document.blocks.slice();
        restoredBlocks[at] = normalizeBlock(Object.assign(cloneValue(current), { text: head }));
        restoredBlocks.splice(at + 1, 0, restored);
        return {
            document: replaceBlocks(document, restoredBlocks),
            inverse: { op: "merge", id: restored.id },
            changed: true
        };
    }

    var props = { text: tail };
    if (BLOCK_FIELDS[current.type].hasOwnProperty("indent"))
        props.indent = current.indent;
    if (current.type === "list") {
        props.style = current.style;
        // A split checkbox starts unchecked. Carrying the tick over marks a task nobody
        // has done yet, which is a wrong fact rather than a cosmetic slip.
        props.checked = false;
    }
    // A split heading continues as a paragraph: pressing Enter at the end of a title
    // means "now the body", every time.
    var tailType = current.type === "heading" ? "text" : current.type;
    if (tailType !== current.type)
        props.indent = 0;

    var tailBlock = block(tailType, props);
    var blocks = document.blocks.slice();
    blocks[at] = normalizeBlock(Object.assign(cloneValue(current), { text: head }));
    blocks.splice(at + 1, 0, tailBlock);

    return {
        document: replaceBlocks(document, blocks),
        inverse: { op: "merge", id: tailBlock.id },
        changed: true
    };
}

/// Backspace at the start of a block: it joins the one above.
function opMerge(document, op) {
    var at = indexOfBlock(document, asString(op.id));
    if (at <= 0)
        return unchanged(document);
    var current = document.blocks[at];
    var previous = document.blocks[at - 1];
    if (!BLOCK_FIELDS[current.type].hasOwnProperty("text")
        || !BLOCK_FIELDS[previous.type].hasOwnProperty("text"))
        return unchanged(document);

    var offset = asString(previous.text).length;
    var joined = normalizeBlock(Object.assign(cloneValue(previous), {
        text: asString(previous.text) + asString(current.text)
    }));

    var blocks = document.blocks.slice();
    blocks[at - 1] = joined;
    blocks.splice(at, 1);

    return {
        document: replaceBlocks(document, blocks),
        // The inverse must restore the block that was absorbed, id included — a plain
        // split would mint a new id and every reference to the old one would dangle.
        inverse: { op: "split", id: previous.id, offset: offset, restore: cloneValue(current) },
        changed: true
    };
}

// ── Derived facts ───────────────────────────────────────────────────────────

/// Everything the index needs to know about a document without opening it again.
function statsOf(document) {
    var doc = normalizeDocument(document);
    var words = 0;
    var characters = 0;
    var hasInk = false;
    var hasImages = false;
    var hasCode = false;

    for (var i = 0; i < doc.blocks.length; i++) {
        var item = doc.blocks[i];
        if (item.type === "ink")
            hasInk = true;
        else if (item.type === "image")
            hasImages = true;
        else if (item.type === "code")
            hasCode = true;
        if (!isTextual(item))
            continue;
        var text = asString(item.text).trim();
        characters += text.length;
        if (text.length > 0)
            words += text.split(/\s+/).length;
    }

    return {
        blockCount: doc.blocks.length,
        words: words,
        characters: characters,
        readingMinutes: words === 0 ? 0 : Math.max(1, Math.ceil(words / WORDS_PER_MINUTE)),
        hasInk: hasInk,
        hasImages: hasImages,
        hasCode: hasCode
    };
}

/// The prose of a document, for search and for preview. Paths, urls and table cells are
/// left out on purpose: matching a note because it happens to link to a file named
/// `report` is a false positive the user cannot explain.
function plainText(document) {
    var doc = normalizeDocument(document);
    var parts = [];
    for (var i = 0; i < doc.blocks.length; i++) {
        if (!isTextual(doc.blocks[i]))
            continue;
        var text = asString(doc.blocks[i].text).trim();
        if (text.length > 0)
            parts.push(text);
    }
    return parts.join("\n");
}

/// The line the list shows under the title. Built here rather than in the list so every
/// surface — app, desktop widget, sidebar tab, search result — shows the same words.
function previewOf(document) {
    var text = plainText(document)
        // Links become what they say. A preview full of `[label](https://…)` spends its
        // hundred and sixty characters on addresses nobody reads at that size.
        .replace(/!\[[^\]]*\]\([^)]*\)/g, " ")
        .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
        .replace(/\[\[([^\]|]*)(?:\|([^\]]*))?\]\]/g, "$1")
        .replace(/[*_`>#~]/g, "")
        .replace(/\s+/g, " ")
        .trim();
    return text.length > PREVIEW_LENGTH ? text.slice(0, PREVIEW_LENGTH).trim() : text;
}

/// A title from the content, for a note nobody named. The first heading if there is one,
/// otherwise the first line of prose.
function titleOf(document, fallback) {
    var doc = normalizeDocument(document);
    for (var i = 0; i < doc.blocks.length; i++) {
        if (doc.blocks[i].type !== "heading")
            continue;
        var heading = asLine(doc.blocks[i].text);
        if (heading.length > 0)
            return heading;
    }
    for (var j = 0; j < doc.blocks.length; j++) {
        if (!isTextual(doc.blocks[j]))
            continue;
        var line = asLine(asString(doc.blocks[j].text).split("\n")[0]);
        if (line.length > 0)
            return line;
    }
    return asLine(fallback);
}

/// The Material Symbol the note shows when the user has not chosen one. Derived from what
/// the note actually holds, so a page of drawing does not look like a page of prose.
function iconFor(document) {
    var stats = statsOf(document);
    if (stats.hasInk)
        return "draw";
    if (stats.hasImages)
        return "image";
    if (stats.hasCode)
        return "code";
    return "article";
}

// ── Index records ───────────────────────────────────────────────────────────

function newNote(props) {
    var source = props && typeof props === "object" ? props : {};
    var now = asInt(source.created, Date.now());
    return normalizeNote({
        id: source.id || newNoteId(),
        title: source.title,
        icon: source.icon || "article",
        notebookId: source.notebookId,
        sectionId: source.sectionId,
        tags: source.tags,
        pinned: source.pinned,
        favorite: source.favorite,
        color: source.color,
        paper: source.paper,
        created: now,
        modified: asInt(source.modified, now),
        preview: source.preview,
        blockCount: source.blockCount,
        hasInk: source.hasInk,
        hasImages: source.hasImages,
        locked: source.locked,
        reminder: source.reminder,
        reminderDone: source.reminderDone,
        trashedAt: source.trashedAt,
        cloud: source.cloud
    });
}

function normalizeNote(value) {
    var source = value && typeof value === "object" ? value : {};
    var cloud = source.cloud && typeof source.cloud === "object" ? source.cloud : {};
    return {
        id: asString(source.id) || newNoteId(),
        title: asLine(source.title),
        icon: asLine(source.icon, 64) || "article",
        notebookId: asString(source.notebookId),
        sectionId: asString(source.sectionId),
        tags: asArray(source.tags).map(function (tag) { return asLine(tag, 48); })
            .filter(function (tag) { return tag.length > 0; })
            .filter(function (tag, at, all) { return all.indexOf(tag) === at; }),
        pinned: asBool(source.pinned),
        favorite: asBool(source.favorite),
        color: asLine(source.color, 32),
        paper: oneOf(source.paper, PAPER_STYLES, ""),
        created: Math.max(0, asInt(source.created, 0)),
        modified: Math.max(0, asInt(source.modified, 0)),
        preview: asString(source.preview).slice(0, PREVIEW_LENGTH),
        blockCount: Math.max(0, asInt(source.blockCount, 0)),
        hasInk: asBool(source.hasInk),
        hasImages: asBool(source.hasImages),
        locked: asBool(source.locked),
        /// When to say something about this note, or zero for never.
        ///
        /// A field on the record rather than a bag called `meta`. The first version of
        /// the reminder wrote `{ meta: { reminder: ... } }`, which this function has
        /// always dropped on the floor: every reminder was accepted, saved nowhere, and
        /// never delivered.
        reminder: Math.max(0, asInt(source.reminder, 0)),
        /// Set once it has been said, so it is said once.
        reminderDone: asBool(source.reminderDone),
        // Zero means "not in the trash". A separate boolean plus a date is two facts that
        // can disagree, and the one that disagrees is always the one being read.
        trashedAt: Math.max(0, asInt(source.trashedAt, 0)),
        cloud: {
            keepId: asString(cloud.keepId),
            keepEtag: asString(cloud.keepEtag),
            syncedAt: Math.max(0, asInt(cloud.syncedAt, 0)),
            dirty: cloud.dirty === undefined ? true : asBool(cloud.dirty)
        }
    };
}

function normalizeSection(value, order) {
    var source = value && typeof value === "object" ? value : {};
    return {
        id: asString(source.id) || newSectionId(),
        title: asLine(source.title),
        order: asInt(source.order, order || 0)
    };
}

function normalizeNotebook(value, order) {
    var source = value && typeof value === "object" ? value : {};
    return {
        id: asString(source.id) || newNotebookId(),
        title: asLine(source.title),
        icon: asLine(source.icon, 64) || "book",
        color: asLine(source.color, 32),
        order: asInt(source.order, order || 0),
        sections: asArray(source.sections).map(normalizeSection)
    };
}

/**
 * Any value into a valid index.
 *
 * A note pointing at a notebook that is not there is repaired rather than dropped: the
 * note is the thing worth keeping, and an orphan filed under nothing is still readable.
 */
function normalizeIndex(value) {
    var source = value && typeof value === "object" ? value : {};
    var notebooks = asArray(source.notebooks).map(normalizeNotebook);
    var known = {};
    notebooks.forEach(function (notebook) {
        known[notebook.id] = {};
        notebook.sections.forEach(function (section) { known[notebook.id][section.id] = true; });
    });

    var notes = asArray(source.notes).map(normalizeNote).map(function (note) {
        if (note.notebookId.length > 0 && !known[note.notebookId]) {
            note.notebookId = "";
            note.sectionId = "";
        } else if (note.sectionId.length > 0 && !known[note.notebookId][note.sectionId]) {
            note.sectionId = "";
        }
        return note;
    });

    var seen = {};
    notes = notes.filter(function (note) {
        if (seen[note.id])
            return false;
        seen[note.id] = true;
        return true;
    });

    return { schema: INDEX_SCHEMA, notebooks: notebooks, notes: notes };
}

function emptyIndex() {
    return { schema: INDEX_SCHEMA, notebooks: [], notes: [] };
}

/// Refreshes the derived fields of one note's index record from its document. The store
/// calls this on every flush; nothing else should be computing a preview.
function noteFromDocument(note, document, modified) {
    var stats = statsOf(document);
    var updated = normalizeNote(note);
    updated.preview = previewOf(document);
    updated.blockCount = stats.blockCount;
    updated.hasInk = stats.hasInk;
    updated.hasImages = stats.hasImages;
    updated.modified = Math.max(0, asInt(modified, updated.modified));
    updated.cloud.dirty = true;
    if (updated.title.length === 0)
        updated.title = titleOf(document, "");
    return updated;
}
