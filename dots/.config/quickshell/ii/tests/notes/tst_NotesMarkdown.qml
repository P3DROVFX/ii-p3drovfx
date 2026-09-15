import QtQuick
import QtTest
import "../../services/notes/NotesDocument.js" as Doc
import "../../services/notes/NotesMarkdown.js" as Markdown

TestCase {
    name: "NotesMarkdown"

    function json(value) { return JSON.stringify(value); }

    /// Ids are minted fresh on import and are not part of what markdown carries. The
    /// round trip is about the content surviving, not about the identifiers.
    function shape(document) {
        return document.blocks.map(function (item) {
            const copy = JSON.parse(JSON.stringify(item));
            delete copy.id;
            return copy;
        });
    }

    function roundTrip(blocks) {
        const before = Doc.normalizeDocument({ blocks: blocks });
        const after = Markdown.fromMarkdown(Markdown.toMarkdown(before));
        compare(json(shape(after)), json(shape(before)));
        return after;
    }

    // ── Lossless round trips ──────────────────────────────────────────────

    function test_headings_survive_with_their_level() {
        roundTrip([
            { type: "heading", level: 1, text: "One" },
            { type: "heading", level: 2, text: "Two" },
            { type: "heading", level: 3, text: "Three" }
        ]);
    }

    function test_paragraphs_survive_with_their_indentation() {
        roundTrip([
            { type: "text", text: "Flat" },
            { type: "text", text: "Indented once", indent: 1 }
        ]);
    }

    function test_every_list_style_survives_nested() {
        roundTrip([
            { type: "list", style: "bullet", text: "Bullet" },
            { type: "list", style: "bullet", text: "Nested bullet", indent: 1 },
            { type: "list", style: "number", text: "Numbered" },
            { type: "list", style: "checkbox", checked: false, text: "Open task" },
            { type: "list", style: "checkbox", checked: true, text: "Done task", indent: 2 }
        ]);
    }

    function test_code_survives_with_its_language() {
        roundTrip([
            { type: "code", language: "python", text: "def hello():\n    return 1" },
            { type: "code", language: "", text: "plain" }
        ]);
    }

    function test_quotes_and_callouts_survive() {
        // Callouts travel as GitHub alerts rather than an invented syntax, so they still
        // render as callouts anywhere the export is opened.
        roundTrip([
            { type: "quote", text: "Quoted line" },
            { type: "callout", tone: "info", text: "A note" },
            { type: "callout", tone: "success", text: "A tip" },
            { type: "callout", tone: "warning", text: "Careful" },
            { type: "callout", tone: "error", text: "Do not" }
        ]);
    }

    function test_dividers_images_and_ink_survive() {
        roundTrip([
            { type: "divider" },
            { type: "image", asset: "photo.png", caption: "A caption" },
            { type: "ink", asset: "sketch.png", aspect: 1.5, strokes: "" }
        ]);
    }

    function test_tables_survive() {
        roundTrip([
            { type: "table", header: true, columns: 3, rows: [["a", "b", "c"], ["1", "2", "3"]] }
        ]);
    }

    function test_a_whole_note_survives() {
        roundTrip([
            { type: "heading", level: 1, text: "Meeting" },
            { type: "text", text: "Discussed the **budget** and the [plan](https://example.com)." },
            { type: "list", style: "checkbox", checked: true, text: "Send the quote" },
            { type: "list", style: "checkbox", checked: false, text: "Follow up", indent: 1 },
            { type: "code", language: "sh", text: "echo hi" },
            { type: "callout", tone: "warning", text: "Deadline is Friday" },
            { type: "divider" },
            { type: "ink", asset: "board.png", aspect: 1.5, strokes: "" }
        ]);
    }

    // ── Documented degradations ───────────────────────────────────────────

    function test_a_link_card_comes_back_as_a_link() {
        // A card is a rendering of a link. Markdown has links and no cards, and pretending
        // otherwise would mean encoding UI state in a comment.
        const before = Doc.normalizeDocument({
            blocks: [{ type: "linkPreview", url: "https://example.com", title: "Example" }]
        });
        const after = Markdown.fromMarkdown(Markdown.toMarkdown(before));
        compare(after.blocks[0].type, "text");
        compare(after.blocks[0].text, "[Example](https://example.com)");
    }

    function test_a_file_card_comes_back_as_a_link() {
        const before = Doc.normalizeDocument({
            blocks: [{ type: "fileLink", path: "/home/someone/report.pdf" }]
        });
        const after = Markdown.fromMarkdown(Markdown.toMarkdown(before));
        compare(after.blocks[0].type, "text");
        compare(after.blocks[0].text, "[report.pdf](file:///home/someone/report.pdf)");
    }

    function test_ink_keeps_its_picture_but_loses_its_strokes() {
        // The vector strokes are a file beside the note; markdown cannot carry a sidecar.
        const before = Doc.normalizeDocument({
            blocks: [{ type: "ink", asset: "s.png", aspect: 2.4, strokes: "s.json" }]
        });
        const after = Markdown.fromMarkdown(Markdown.toMarkdown(before));
        compare(after.blocks[0].type, "ink");
        compare(after.blocks[0].asset, "s.png");
        compare(after.blocks[0].strokes, "");
        compare(after.blocks[0].aspect, 1.5);
    }

    function test_a_headerless_table_comes_back_with_a_header() {
        // Markdown tables are defined with a header row. "No header" is a rendering choice
        // the format cannot state.
        const before = Doc.normalizeDocument({
            blocks: [{ type: "table", header: false, columns: 2, rows: [["a", "b"]] }]
        });
        const after = Markdown.fromMarkdown(Markdown.toMarkdown(before));
        verify(after.blocks[0].header);
    }

    // ── Import from text nobody wrote for us ──────────────────────────────

    function test_arbitrary_text_never_throws_and_never_loses_a_line() {
        const cases = [null, undefined, "", "   ", "just words", "```\nunclosed", "| broken |", "###"];
        for (const value of cases) {
            const document = Markdown.fromMarkdown(value);
            verify(document.blocks.length >= 1);
        }
        compare(Markdown.fromMarkdown("just words").blocks[0].text, "just words");
    }

    function test_four_space_nesting_is_read_as_nesting() {
        // Editors disagree about two spaces or four. Reading both keeps an imported file
        // nested the way its author saw it.
        const document = Markdown.fromMarkdown("- one\n    - two");
        compare(document.blocks[1].indent, 2);
        compare(Markdown.fromMarkdown("- one\n  - two").blocks[1].indent, 1);
    }

    function test_consecutive_paragraph_lines_are_one_block() {
        const document = Markdown.fromMarkdown("first line\nsecond line\n\nnew paragraph");
        compare(document.blocks.length, 2);
        compare(document.blocks[0].text, "first line\nsecond line");
    }

    function test_a_mermaid_fence_is_a_diagram_not_a_code_block() {
        const document = Markdown.fromMarkdown("```mermaid\ngraph TD;\n```");
        compare(document.blocks[0].type, "embed");
        compare(document.blocks[0].kind, "mermaid");
    }

    function test_a_math_fence_is_latex() {
        const document = Markdown.fromMarkdown("$$\nx^2\n$$");
        compare(document.blocks[0].type, "embed");
        compare(document.blocks[0].kind, "latex");
        compare(document.blocks[0].text, "x^2");
    }

    function test_import_undoes_the_asset_prefix_an_export_added() {
        const before = Doc.normalizeDocument({ blocks: [{ type: "image", asset: "photo.png" }] });
        const text = Markdown.toMarkdown(before, { assetPrefix: "assets/" });
        compare(text, "![](assets/photo.png)");
        const after = Markdown.fromMarkdown(text, { assetPrefix: "assets/" });
        compare(after.blocks[0].asset, "photo.png");
    }

    function test_list_items_stay_tight() {
        // A blank line between items makes a loose list, which renders with paragraph
        // spacing inside every bullet.
        const text = Markdown.toMarkdown(Doc.normalizeDocument({
            blocks: [
                { type: "list", style: "bullet", text: "one" },
                { type: "list", style: "bullet", text: "two" }
            ]
        }));
        compare(text, "- one\n- two");
    }

    function test_a_cell_containing_a_pipe_survives() {
        const before = Doc.normalizeDocument({
            blocks: [{ type: "table", columns: 2, rows: [["a|b", "c"]] }]
        });
        const after = Markdown.fromMarkdown(Markdown.toMarkdown(before));
        compare(after.blocks[0].rows[0][0], "a|b");
    }

    // ── Re-anchoring a parsed document onto the one it replaces ───────────

    function test_merging_keeps_the_block_ids_the_editor_is_pointing_at() {
        // A surface that re-parses on every keystroke would otherwise replace the whole
        // document each time: undo with nothing stable to anchor to, and a cursor sitting
        // in a block that no longer exists.
        const before = Doc.normalizeDocument({
            blocks: [
                { id: "one", type: "heading", text: "Title" },
                { id: "two", type: "text", text: "Body" }
            ]
        });
        const merged = Markdown.mergeParsed(before, Markdown.fromMarkdown("# Title\n\nBody edited"));
        compare(merged.blocks[0].id, "one");
        compare(merged.blocks[1].id, "two");
        compare(merged.blocks[1].text, "Body edited");
    }

    function test_merging_restores_what_markdown_cannot_write_down() {
        const before = Doc.normalizeDocument({
            blocks: [
                { id: "ink", type: "ink", asset: "s.png", aspect: 2.4, strokes: "s.json" },
                { id: "img", type: "image", asset: "p.png", width: 0.5 }
            ]
        });
        const merged = Markdown.mergeParsed(before, Markdown.fromMarkdown(Markdown.toMarkdown(before)));
        compare(merged.blocks[0].aspect, 2.4);
        compare(merged.blocks[0].strokes, "s.json");
        compare(merged.blocks[0].id, "ink");
        compare(merged.blocks[1].width, 0.5);
    }

    function test_a_drawing_that_moved_is_still_the_same_drawing() {
        // Matched by the file it names, not by position: a block that names a file is the
        // same block wherever it ended up.
        const before = Doc.normalizeDocument({
            blocks: [
                { id: "ink", type: "ink", asset: "s.png", aspect: 3, strokes: "s.json" },
                { id: "txt", type: "text", text: "after" }
            ]
        });
        const merged = Markdown.mergeParsed(before, Markdown.fromMarkdown("after\n\n![ink](s.png)"));
        compare(merged.blocks[1].id, "ink");
        compare(merged.blocks[1].aspect, 3);
    }

    function test_a_block_with_no_counterpart_simply_arrives() {
        const before = Doc.normalizeDocument({ blocks: [{ id: "one", type: "text", text: "a" }] });
        const merged = Markdown.mergeParsed(before, Markdown.fromMarkdown("a\n\nb\n\nc"));
        compare(merged.blocks.length, 3);
        compare(merged.blocks[0].id, "one");
        verify(merged.blocks[1].id !== "one");
    }

    function test_merging_onto_nothing_is_just_the_parsed_document() {
        const merged = Markdown.mergeParsed(null, Markdown.fromMarkdown("# Hi"));
        compare(merged.blocks[0].type, "heading");
        compare(merged.blocks[0].text, "Hi");
    }
}
