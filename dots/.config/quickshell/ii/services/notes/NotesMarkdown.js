.pragma library
.import "NotesDocument.js" as Doc

// Markdown in and out of the block model.
//
// Markdown is the export format, the import format and the escape hatch — the raw-text
// mode a note can be opened in when the block editor is in the way. It is deliberately
// *not* the storage format: a note also holds drawings, previews and file references,
// and a format that has to encode those in comments is a format that loses them.
//
// The round trip is a contract, checked by `tests/notes/tst_NotesMarkdown.qml`:
//
//   document -> toMarkdown -> fromMarkdown -> the same blocks, field for field,
//
// for heading, text, list (all three styles, with indent), code (with language), quote,
// callout, divider, image, ink and table. What degrades, and why:
//
//   - `linkPreview`, `fileLink`, `audio`  come back as text holding a markdown link.
//     A card is a rendering of a link; markdown has links and no cards.
//   - `ink`             keeps its file but loses `aspect` and the vector strokes. The
//     strokes live in a file beside the note, and markdown cannot carry a sidecar.
//   - `table.header:false`  comes back as `true`. Markdown tables are defined with a
//     header row; a headerless table is a rendering choice this format cannot state.
//   - a `text` block indented two levels or more exports with four leading spaces, which
//     a strict CommonMark renderer elsewhere shows as a code block. Our own parser reads
//     it back as indentation, so a round trip through this app is lossless; a round trip
//     through GitHub is not.

var INDENT_UNIT = "  ";

/// Callout tones and the GitHub alert names they travel as. Alerts were chosen over an
/// invented syntax because they already render as callouts everywhere that matters.
var TONE_TO_ALERT = { info: "NOTE", success: "TIP", warning: "WARNING", error: "CAUTION" };
var ALERT_TO_TONE = { NOTE: "info", TIP: "success", IMPORTANT: "info", WARNING: "warning", CAUTION: "error" };

function repeat(text, times) {
    var out = "";
    for (var i = 0; i < times; i++)
        out += text;
    return out;
}

function pad(indent) {
    return repeat(INDENT_UNIT, Math.max(0, Number(indent) || 0));
}

// ── Document to markdown ────────────────────────────────────────────────────

/**
 * The whole document as markdown text.
 *
 * `options.assetPrefix` is prepended to every asset name, so an export can point at the
 * folder it copied the files into ("assets/") while the app's raw-text mode points at
 * nothing and shows the bare name.
 */
function toMarkdown(document, options) {
    var doc = Doc.normalizeDocument(document);
    var opts = options && typeof options === "object" ? options : {};
    var prefix = typeof opts.assetPrefix === "string" ? opts.assetPrefix : "";
    var pieces = [];

    for (var i = 0; i < doc.blocks.length; i++) {
        var current = doc.blocks[i];
        var text = blockToMarkdown(current, prefix);
        if (text === null)
            continue;
        // Consecutive list items stay adjacent. A blank line between them makes a "loose"
        // list, which renders with paragraph spacing inside every bullet.
        var previous = i > 0 ? doc.blocks[i - 1] : null;
        var tight = previous && previous.type === "list" && current.type === "list";
        pieces.push({ text: text, tight: tight });
    }

    var out = "";
    for (var j = 0; j < pieces.length; j++) {
        if (j > 0)
            out += pieces[j].tight ? "\n" : "\n\n";
        out += pieces[j].text;
    }
    return out;
}

function blockToMarkdown(item, prefix) {
    switch (item.type) {
    case "heading":
        return repeat("#", item.level) + " " + item.text;
    case "text":
        return pad(item.indent) + item.text;
    case "list":
        return pad(item.indent) + listMarker(item) + item.text;
    case "quote":
        return pad(item.indent) + "> " + item.text;
    case "callout":
        return calloutToMarkdown(item);
    case "code":
        return "```" + item.language + "\n" + item.text + "\n```";
    case "divider":
        return "---";
    case "image":
        return "![" + escapeBrackets(item.caption) + "](" + prefix + item.asset + ")";
    case "ink":
        return "![ink](" + prefix + item.asset + ")";
    case "audio":
        return "[audio](" + prefix + item.asset + ")";
    case "table":
        return tableToMarkdown(item);
    case "linkPreview":
        return "[" + escapeBrackets(item.title || item.url) + "](" + item.url + ")";
    case "fileLink":
        return "[" + escapeBrackets(baseName(item.path)) + "](" + fileUrl(item.path) + ")";
    case "embed":
        return item.kind === "mermaid"
            ? "```mermaid\n" + item.text + "\n```"
            : "$$\n" + item.text + "\n$$";
    default:
        return null;
    }
}

function listMarker(item) {
    if (item.style === "checkbox")
        return item.checked ? "- [x] " : "- [ ] ";
    if (item.style === "number")
        return "1. ";
    return "- ";
}

function calloutToMarkdown(item) {
    var alert = TONE_TO_ALERT[item.tone] || "NOTE";
    var lines = String(item.text).split("\n");
    var out = "> [!" + alert + "]";
    for (var i = 0; i < lines.length; i++)
        out += "\n> " + lines[i];
    return out;
}

function tableToMarkdown(item) {
    var rows = item.rows;
    if (rows.length === 0)
        return "";
    var out = "| " + rows[0].map(escapePipes).join(" | ") + " |";
    out += "\n|" + repeat(" --- |", item.columns);
    for (var i = 1; i < rows.length; i++)
        out += "\n| " + rows[i].map(escapePipes).join(" | ") + " |";
    return out;
}

function escapePipes(cell) {
    return String(cell).replace(/\|/g, "\\|");
}

function escapeBrackets(text) {
    return String(text).replace(/[\[\]]/g, "");
}

function baseName(path) {
    var parts = String(path).split("/");
    return parts[parts.length - 1] || String(path);
}

function fileUrl(path) {
    var text = String(path);
    return text.indexOf("://") >= 0 ? text : "file://" + text;
}

// ── Markdown to document ────────────────────────────────────────────────────

var FENCE = /^\s*```([A-Za-z0-9_+#.-]*)\s*$/;
var HEADING = /^(#{1,6})\s+(.*)$/;
var DIVIDER = /^\s*(?:-{3,}|_{3,}|\*{3,})\s*$/;
var CHECKBOX = /^(\s*)[-*+]\s+\[([ xX])\]\s?(.*)$/;
var BULLET = /^(\s*)[-*+]\s+(.*)$/;
var NUMBERED = /^(\s*)\d+[.)]\s+(.*)$/;
var QUOTE = /^(\s*)>\s?(.*)$/;
var ALERT = /^\[!([A-Z]+)\]\s*$/;
var IMAGE = /^\s*!\[([^\]]*)\]\(([^)]*)\)\s*$/;
var LINK_ONLY = /^\s*\[([^\]]*)\]\(([^)]*)\)\s*$/;
var TABLE_ROW = /^\s*\|(.*)\|\s*$/;
var TABLE_RULE = /^\s*\|[\s:|-]+\|\s*$/;
var MATH_FENCE = /^\s*\$\$\s*$/;

/**
 * Markdown text into a document.
 *
 * `options.noteId` names the document; `options.assetPrefix` is stripped from image paths
 * so an import undoes what the matching export did.
 *
 * Never throws. Anything it cannot classify becomes a paragraph, which is the honest
 * answer for arbitrary text and keeps an import from losing lines it did not understand.
 */
function fromMarkdown(text, options) {
    var opts = options && typeof options === "object" ? options : {};
    var prefix = typeof opts.assetPrefix === "string" ? opts.assetPrefix : "";
    var lines = String(text === null || text === undefined ? "" : text)
        .replace(/\r\n?/g, "\n").split("\n");
    var blocks = [];
    var paragraph = [];
    var paragraphIndent = 0;

    function flushParagraph() {
        if (paragraph.length === 0)
            return;
        var joined = paragraph.join("\n").trim();
        paragraph = [];
        if (joined.length === 0)
            return;
        blocks.push(Doc.block("text", { text: joined, indent: paragraphIndent }));
        paragraphIndent = 0;
    }

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];

        if (line.trim().length === 0) {
            flushParagraph();
            continue;
        }

        var fence = FENCE.exec(line);
        if (fence) {
            flushParagraph();
            var body = [];
            i++;
            while (i < lines.length && !FENCE.test(lines[i])) {
                body.push(lines[i]);
                i++;
            }
            var language = fence[1] || "";
            if (language === "mermaid")
                blocks.push(Doc.block("embed", { kind: "mermaid", text: body.join("\n") }));
            else
                blocks.push(Doc.block("code", { language: language, text: body.join("\n") }));
            continue;
        }

        if (MATH_FENCE.test(line)) {
            flushParagraph();
            var math = [];
            i++;
            while (i < lines.length && !MATH_FENCE.test(lines[i])) {
                math.push(lines[i]);
                i++;
            }
            blocks.push(Doc.block("embed", { kind: "latex", text: math.join("\n") }));
            continue;
        }

        if (DIVIDER.test(line)) {
            flushParagraph();
            blocks.push(Doc.block("divider", {}));
            continue;
        }

        var heading = HEADING.exec(line);
        if (heading) {
            flushParagraph();
            blocks.push(Doc.block("heading", { level: heading[1].length, text: heading[2].trim() }));
            continue;
        }

        var checkbox = CHECKBOX.exec(line);
        if (checkbox) {
            flushParagraph();
            blocks.push(Doc.block("list", {
                style: "checkbox",
                checked: checkbox[2].toLowerCase() === "x",
                indent: indentOf(checkbox[1]),
                text: checkbox[3].trim()
            }));
            continue;
        }

        var numbered = NUMBERED.exec(line);
        if (numbered) {
            flushParagraph();
            blocks.push(Doc.block("list", {
                style: "number", indent: indentOf(numbered[1]), text: numbered[2].trim()
            }));
            continue;
        }

        var bullet = BULLET.exec(line);
        if (bullet) {
            flushParagraph();
            blocks.push(Doc.block("list", {
                style: "bullet", indent: indentOf(bullet[1]), text: bullet[2].trim()
            }));
            continue;
        }

        var quote = QUOTE.exec(line);
        if (quote) {
            flushParagraph();
            i = consumeQuote(lines, i, blocks);
            continue;
        }

        if (TABLE_ROW.test(line) && i + 1 < lines.length && TABLE_RULE.test(lines[i + 1])) {
            flushParagraph();
            i = consumeTable(lines, i, blocks);
            continue;
        }

        var image = IMAGE.exec(line);
        if (image) {
            flushParagraph();
            var asset = stripPrefix(image[2].trim(), prefix);
            if (image[1].trim() === "ink")
                blocks.push(Doc.block("ink", { asset: asset }));
            else
                blocks.push(Doc.block("image", { asset: asset, caption: image[1].trim() }));
            continue;
        }

        var link = LINK_ONLY.exec(line);
        if (link && link[1].trim() === "audio") {
            flushParagraph();
            blocks.push(Doc.block("audio", { asset: stripPrefix(link[2].trim(), prefix) }));
            continue;
        }

        if (paragraph.length === 0)
            paragraphIndent = indentOf(leadingSpace(line));
        paragraph.push(line.trim());
    }
    flushParagraph();

    return Doc.normalizeDocument({ id: opts.noteId, blocks: blocks }, opts.noteId);
}

/// Two spaces to a level, and an odd space rounds down. Editors disagree about whether a
/// nested bullet takes two spaces or four; reading both keeps an imported file nested the
/// way its author saw it.
function indentOf(spaces) {
    var text = String(spaces || "").replace(/\t/g, INDENT_UNIT);
    return Math.min(Doc.MAX_INDENT, Math.floor(text.length / INDENT_UNIT.length));
}

function leadingSpace(line) {
    var match = /^(\s*)/.exec(String(line));
    return match ? match[1] : "";
}

function stripPrefix(value, prefix) {
    var text = String(value);
    if (prefix.length > 0 && text.indexOf(prefix) === 0)
        return text.slice(prefix.length);
    return text;
}

/// A run of `>` lines is one block. An alert marker on the first line makes it a callout;
/// anything else is a quote.
function consumeQuote(lines, start, blocks) {
    var body = [];
    var indent = 0;
    var at = start;
    while (at < lines.length) {
        var match = QUOTE.exec(lines[at]);
        if (!match)
            break;
        if (body.length === 0)
            indent = indentOf(match[1]);
        body.push(match[2]);
        at++;
    }

    var alert = body.length > 0 ? ALERT.exec(body[0].trim()) : null;
    if (alert) {
        var tone = ALERT_TO_TONE[alert[1]] || "info";
        blocks.push(Doc.block("callout", { tone: tone, text: body.slice(1).join("\n").trim() }));
    } else {
        blocks.push(Doc.block("quote", { indent: indent, text: body.join("\n").trim() }));
    }
    return at - 1;
}

function consumeTable(lines, start, blocks) {
    var rows = [splitRow(lines[start])];
    var at = start + 2; // header row, then the rule
    while (at < lines.length && TABLE_ROW.test(lines[at]) && !TABLE_RULE.test(lines[at])) {
        rows.push(splitRow(lines[at]));
        at++;
    }
    var columns = rows.reduce(function (most, row) { return Math.max(most, row.length); }, 1);
    blocks.push(Doc.block("table", { columns: columns, rows: rows, header: true }));
    return at - 1;
}

/**
 * A table row into its cells, honouring `\|` as a literal pipe.
 *
 * Scanned by hand rather than split by a regex: the natural expression needs a lookbehind
 * to tell an escaped pipe from a separator, and QML's JavaScript engine does not support
 * lookbehind. It does not raise either — the split simply never matches, and every row
 * arrives as one cell containing the whole line.
 */
function splitRow(line) {
    var inner = TABLE_ROW.exec(line);
    var body = inner ? inner[1] : String(line);
    var cells = [];
    var current = "";
    for (var i = 0; i < body.length; i++) {
        var ch = body.charAt(i);
        if (ch === "\\" && body.charAt(i + 1) === "|") {
            current += "|";
            i++;
        } else if (ch === "|") {
            cells.push(current.trim());
            current = "";
        } else {
            current += ch;
        }
    }
    cells.push(current.trim());
    return cells;
}

// ── Putting a parsed document back onto the one it came from ────────────────

/**
 * Fields a block owns that markdown has no way to write down.
 *
 * They are not lost when a document is edited as text — they are restored from the
 * document that was there before, matched block to block. Without this, editing a note in
 * a markdown-shaped surface silently flattens the drawing's proportions and throws away
 * its vector strokes, and the user's only clue is that the picture looks wrong later.
 */
var CARRIED_FIELDS = { ink: ["aspect", "strokes"], image: ["width"], table: ["header"] };

/**
 * `parsed` re-anchored onto `previous`.
 *
 * Two things are recovered. The fields above, and — just as important — the **block ids**.
 * `fromMarkdown` mints a fresh id for every block, so a surface that re-parsed on each
 * keystroke would replace the whole document every time: undo would have nothing stable
 * to point at, revisions would show every line as changed, and the editor's cursor would
 * be inside a block that no longer exists.
 *
 * Matching is by asset for the blocks that name a file, and otherwise the next unclaimed
 * block of the same type, preferring one whose text is identical. That is a heuristic and
 * it is allowed to be: being wrong costs a new id for one block, never content.
 */
function mergeParsed(previous, parsed) {
    var before = Doc.normalizeDocument(previous);
    var after = Doc.normalizeDocument(parsed, before.id);
    var claimed = {};

    var blocks = after.blocks.map(function (item) {
        var donor = findDonor(before.blocks, item, claimed);
        if (!donor)
            return item;
        claimed[donor.id] = true;
        var merged = { id: donor.id };
        for (var key in item) {
            if (key !== "id")
                merged[key] = item[key];
        }
        var carried = CARRIED_FIELDS[item.type] || [];
        for (var i = 0; i < carried.length; i++) {
            if (donor.hasOwnProperty(carried[i]))
                merged[carried[i]] = donor[carried[i]];
        }
        return Doc.normalizeBlock(merged);
    });

    return Doc.normalizeDocument({ id: before.id, blocks: blocks }, before.id);
}

function findDonor(candidates, item, claimed) {
    var sameType = [];
    for (var i = 0; i < candidates.length; i++) {
        if (candidates[i].type !== item.type || claimed[candidates[i].id])
            continue;
        // A block that names a file is the same block as long as it names the same file,
        // wherever it moved to in the document.
        if (item.hasOwnProperty("asset") && item.asset.length > 0)
            return candidates[i].asset === item.asset ? candidates[i] : null;
        sameType.push(candidates[i]);
    }
    if (sameType.length === 0)
        return null;
    for (var j = 0; j < sameType.length; j++) {
        if (sameType[j].hasOwnProperty("text") && sameType[j].text === item.text)
            return sameType[j];
    }
    return sameType[0];
}
