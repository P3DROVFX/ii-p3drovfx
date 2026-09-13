import QtQuick
import QtTest
import "../../services/notes/NotesDocument.js" as Doc

TestCase {
    name: "NotesDocument"

    function json(value) { return JSON.stringify(value); }

    // ── Normalisation is total ────────────────────────────────────────────

    function test_anything_at_all_normalises_into_a_document() {
        // A half-written file, a value that was never a document, a null. Each one is a
        // note the user still expects to open.
        const cases = [null, undefined, 0, "text", [], { blocks: "no" }, { blocks: [null, 7] }];
        for (const value of cases) {
            const document = Doc.normalizeDocument(value);
            verify(document.blocks.length >= 1);
            compare(document.schema, Doc.DOCUMENT_SCHEMA);
            verify(document.id.length > 0);
        }
    }

    function test_an_empty_document_still_has_somewhere_to_type() {
        // Zero blocks is an editor with no cursor position, which reads as a note that
        // refuses to open.
        const document = Doc.normalizeDocument({ blocks: [] });
        compare(document.blocks.length, 1);
        compare(document.blocks[0].type, "text");
    }

    function test_normalising_twice_changes_nothing() {
        // The store normalises on read and on write. If that were not idempotent the file
        // would drift on every open, and every open would look like an edit to sync.
        const once = Doc.normalizeDocument({
            id: "nt_1",
            blocks: [
                { id: "bk_1", type: "heading", level: 9, text: "Title" },
                { id: "bk_2", type: "list", style: "nonsense", indent: 99, text: "Item" },
                { id: "bk_3", type: "table", columns: 1, rows: [["a", "b", "c"], ["d"]] }
            ]
        });
        compare(json(Doc.normalizeDocument(once)), json(once));
    }

    function test_unknown_types_and_fields_do_not_survive() {
        const document = Doc.normalizeDocument({
            blocks: [{ id: "bk_1", type: "hologram", text: "hi", nonsense: 5 }]
        });
        compare(document.blocks[0].type, "text");
        compare(document.blocks[0].text, "hi");
        verify(document.blocks[0].nonsense === undefined);
    }

    function test_two_blocks_never_answer_to_the_same_id() {
        // Every operation addresses a block by id. Duplicates make each one ambiguous,
        // and the editor ends up editing both.
        const document = Doc.normalizeDocument({
            blocks: [{ id: "same", type: "text", text: "a" }, { id: "same", type: "text", text: "b" }]
        });
        verify(document.blocks[0].id !== document.blocks[1].id);
        compare(document.blocks[1].text, "b");
    }

    // ── Field discipline ──────────────────────────────────────────────────

    function test_values_are_clamped_to_what_the_ui_can_draw() {
        compare(Doc.block("heading", { level: 42 }).level, Doc.MAX_HEADING_LEVEL);
        compare(Doc.block("heading", { level: 0 }).level, 1);
        compare(Doc.block("text", { indent: 400 }).indent, Doc.MAX_INDENT);
        compare(Doc.block("text", { indent: -3 }).indent, 0);
        compare(Doc.block("list", { style: "spiral" }).style, "bullet");
        compare(Doc.block("callout", { tone: "beige" }).tone, "info");
        compare(Doc.block("embed", { kind: "html" }).kind, "latex");
        compare(Doc.block("image", { width: 5 }).width, 1);
        compare(Doc.block("ink", { aspect: 0 }).aspect, 1.5);
    }

    function test_a_table_is_always_a_rectangle() {
        // A short row renders as a grid with a hole in it; a long one loses cells at the
        // edge without saying so.
        const table = Doc.block("table", { columns: 2, rows: [["a", "b", "c"], ["d"]] });
        compare(table.columns, 3);
        compare(json(table.rows), json([["a", "b", "c"], ["d", "", ""]]));
        compare(Doc.block("table", { rows: [] }).rows.length, 1);
    }

    function test_titles_never_carry_a_newline() {
        // A note list draws one row per note; a newline in the title breaks the row.
        const note = Doc.normalizeNote({ title: "first\nsecond" });
        compare(note.title, "first second");
    }

    // ── Operations ────────────────────────────────────────────────────────

    function baseDocument() {
        return Doc.normalizeDocument({
            id: "nt_test",
            blocks: [
                { id: "a", type: "heading", level: 1, text: "Title" },
                { id: "b", type: "text", text: "Hello world" },
                { id: "c", type: "list", style: "checkbox", checked: false, text: "Task", indent: 1 }
            ]
        });
    }

    /// The contract undo is built on: whatever an operation did, applying the inverse it
    /// returned puts the document back exactly as it was.
    function assertRoundTrip(ops) {
        const before = baseDocument();
        const forward = Doc.applyOps(before, ops);
        verify(forward.changed, "expected the operation to change something");
        const back = Doc.applyOps(forward.document, forward.inverse);
        compare(json(back.document), json(before));
    }

    function test_insert_round_trips() {
        assertRoundTrip([{ op: "insert", index: 1, block: { type: "quote", text: "Quoted" } }]);
    }

    function test_update_round_trips() {
        assertRoundTrip([{ op: "update", id: "b", patch: { text: "Changed" } }]);
    }

    function test_delete_round_trips_with_its_position() {
        assertRoundTrip([{ op: "delete", id: "b" }]);
    }

    function test_move_round_trips() {
        assertRoundTrip([{ op: "move", id: "a", to: 2 }]);
    }

    function test_indent_round_trips() {
        assertRoundTrip([{ op: "indent", id: "c", delta: 1 }]);
    }

    function test_settype_round_trips() {
        assertRoundTrip([{ op: "setType", id: "b", type: "heading", props: { level: 2 } }]);
    }

    function test_split_round_trips() {
        assertRoundTrip([{ op: "split", id: "b", offset: 5 }]);
    }

    function test_merge_round_trips() {
        assertRoundTrip([{ op: "merge", id: "c" }]);
    }

    function test_a_whole_batch_round_trips_in_order() {
        assertRoundTrip([
            { op: "update", id: "b", patch: { text: "One" } },
            { op: "insert", index: 0, block: { type: "divider" } },
            { op: "indent", id: "c", delta: 2 },
            { op: "move", id: "a", to: 3 },
            { op: "delete", id: "b" }
        ]);
    }

    function test_nothing_happening_is_reported_as_nothing() {
        const before = baseDocument();
        const result = Doc.applyOps(before, [
            { op: "update", id: "does-not-exist", patch: { text: "x" } },
            { op: "delete", id: "also-missing" },
            { op: "move", id: "a", to: 0 },
            { op: "nonsense" },
            { op: "update", id: "b", patch: { text: "Hello world" } }
        ]);
        verify(!result.changed);
        compare(result.inverse.length, 0);
        compare(json(result.document), json(before));
    }

    function test_operations_do_not_mutate_what_they_were_given() {
        // The editor keeps the previous document for undo. An op that edited it in place
        // would quietly rewrite history.
        const before = baseDocument();
        const snapshot = json(before);
        Doc.applyOps(before, [{ op: "update", id: "b", patch: { text: "Changed" } }]);
        compare(json(before), snapshot);
    }

    function test_the_last_block_cannot_be_deleted() {
        const single = Doc.normalizeDocument({ blocks: [{ id: "only", type: "text", text: "x" }] });
        const result = Doc.applyOps(single, [{ op: "delete", id: "only" }]);
        verify(!result.changed);
        compare(result.document.blocks.length, 1);
    }

    function test_indent_at_the_ceiling_undoes_by_what_it_actually_moved() {
        // An inverse built from the requested delta would un-indent a block that never
        // moved, and the block would drift left every time undo ran.
        const document = Doc.normalizeDocument({
            blocks: [{ id: "a", type: "text", text: "x", indent: Doc.MAX_INDENT - 1 }]
        });
        const forward = Doc.applyOps(document, [{ op: "indent", id: "a", delta: 5 }]);
        compare(forward.document.blocks[0].indent, Doc.MAX_INDENT);
        compare(forward.inverse[0].delta, -1);
        const back = Doc.applyOps(forward.document, forward.inverse);
        compare(back.document.blocks[0].indent, Doc.MAX_INDENT - 1);
    }

    function test_update_refuses_to_change_identity_or_type() {
        const forward = Doc.applyOps(baseDocument(), [
            { op: "update", id: "b", patch: { id: "hijacked", type: "code", text: "kept" } }
        ]);
        const changed = forward.document.blocks[1];
        compare(changed.id, "b");
        compare(changed.type, "text");
        compare(changed.text, "kept");
    }

    function test_changing_type_keeps_the_block_the_user_is_typing_in() {
        // Same block to the user: their paragraph became a heading. A new id here loses
        // the cursor and unanchors undo.
        const forward = Doc.applyOps(baseDocument(), [{ op: "setType", id: "b", type: "heading" }]);
        compare(forward.document.blocks[1].id, "b");
        compare(forward.document.blocks[1].type, "heading");
        compare(forward.document.blocks[1].text, "Hello world");
    }

    function test_splitting_a_heading_continues_as_body_text() {
        // Enter at the end of a title means "now the body", every time.
        const forward = Doc.applyOps(baseDocument(), [{ op: "split", id: "a", offset: 5 }]);
        compare(forward.document.blocks[0].type, "heading");
        compare(forward.document.blocks[1].type, "text");
    }

    function test_splitting_a_checked_task_does_not_tick_the_new_one() {
        const document = Doc.normalizeDocument({
            blocks: [{ id: "a", type: "list", style: "checkbox", checked: true, text: "buy milk" }]
        });
        const forward = Doc.applyOps(document, [{ op: "split", id: "a", offset: 3 }]);
        compare(forward.document.blocks[1].style, "checkbox");
        verify(!forward.document.blocks[1].checked, "a split task must not claim to be done");
    }

    function test_merging_the_first_block_is_refused() {
        const result = Doc.applyOps(baseDocument(), [{ op: "merge", id: "a" }]);
        verify(!result.changed);
    }

    // ── Derived facts ─────────────────────────────────────────────────────

    function test_stats_count_prose_and_notice_media() {
        const document = Doc.normalizeDocument({
            blocks: [
                { type: "heading", text: "Two words" },
                { type: "text", text: "three little words" },
                { type: "ink", asset: "a.png" },
                { type: "image", asset: "b.png" },
                { type: "code", language: "js", text: "const x = 1" }
            ]
        });
        const stats = Doc.statsOf(document);
        compare(stats.blockCount, 5);
        compare(stats.words, 5);
        verify(stats.hasInk);
        verify(stats.hasImages);
        verify(stats.hasCode);
        compare(stats.readingMinutes, 1);
    }

    function test_preview_and_plain_text_leave_paths_out() {
        // Matching a note because it links to a file called "report" is a hit the user
        // cannot explain from what they can see.
        const document = Doc.normalizeDocument({
            blocks: [
                { type: "text", text: "Visible prose" },
                { type: "fileLink", path: "/home/someone/report.pdf" },
                { type: "linkPreview", url: "https://example.com/secret" }
            ]
        });
        compare(Doc.plainText(document), "Visible prose");
        compare(Doc.previewOf(document), "Visible prose");
    }

    function test_a_title_is_found_in_the_content_when_nobody_named_the_note() {
        compare(Doc.titleOf(Doc.normalizeDocument({
            blocks: [{ type: "text", text: "body" }, { type: "heading", text: "The heading" }]
        }), "fallback"), "The heading");
        compare(Doc.titleOf(Doc.normalizeDocument({
            blocks: [{ type: "text", text: "First line\nsecond line" }]
        }), "fallback"), "First line");
        compare(Doc.titleOf(Doc.normalizeDocument({ blocks: [] }), "fallback"), "fallback");
    }

    function test_the_icon_says_what_the_note_holds() {
        compare(Doc.iconFor(Doc.normalizeDocument({ blocks: [{ type: "ink", asset: "a" }] })), "draw");
        compare(Doc.iconFor(Doc.normalizeDocument({ blocks: [{ type: "image", asset: "a" }] })), "image");
        compare(Doc.iconFor(Doc.normalizeDocument({ blocks: [{ type: "code", text: "a" }] })), "code");
        compare(Doc.iconFor(Doc.normalizeDocument({ blocks: [{ type: "text", text: "a" }] })), "article");
    }

    // ── The index ─────────────────────────────────────────────────────────

    function test_the_index_normalises_out_of_anything() {
        const index = Doc.normalizeIndex(null);
        compare(index.schema, Doc.INDEX_SCHEMA);
        compare(index.notes.length, 0);
        compare(index.notebooks.length, 0);
    }

    function test_a_note_filed_under_a_notebook_that_is_gone_is_kept_anyway() {
        // The note is the thing worth keeping. An orphan filed under nothing still opens.
        const index = Doc.normalizeIndex({
            notebooks: [{ id: "nb_1", title: "Real", sections: [{ id: "sc_1", title: "S" }] }],
            notes: [
                { id: "nt_1", title: "Orphan", notebookId: "nb_gone", sectionId: "sc_gone" },
                { id: "nt_2", title: "Half", notebookId: "nb_1", sectionId: "sc_gone" }
            ]
        });
        compare(index.notes.length, 2);
        compare(index.notes[0].notebookId, "");
        compare(index.notes[1].notebookId, "nb_1");
        compare(index.notes[1].sectionId, "");
    }

    function test_duplicate_notes_are_dropped_not_merged() {
        const index = Doc.normalizeIndex({ notes: [{ id: "nt_1", title: "A" }, { id: "nt_1", title: "B" }] });
        compare(index.notes.length, 1);
        compare(index.notes[0].title, "A");
    }

    function test_tags_are_a_set_of_single_lines() {
        const note = Doc.normalizeNote({ tags: ["work", "work", "", "  spaced  ", "two\nlines"] });
        compare(json(note.tags), json(["work", "spaced", "two lines"]));
    }

    function test_the_trash_is_one_fact_not_two() {
        // A boolean plus a date can disagree, and the one being read is always the one
        // that disagrees.
        compare(Doc.normalizeNote({}).trashedAt, 0);
        compare(Doc.normalizeNote({ trashedAt: 1700000000000 }).trashedAt, 1700000000000);
        compare(Doc.normalizeNote({ trashedAt: -5 }).trashedAt, 0);
    }

    function test_the_index_record_is_refreshed_from_the_document() {
        const document = Doc.normalizeDocument({
            blocks: [{ type: "heading", text: "Meeting" }, { type: "ink", asset: "a.png" }]
        });
        const note = Doc.noteFromDocument(Doc.newNote({ title: "" }), document, 1700000000000);
        compare(note.title, "Meeting");
        compare(note.blockCount, 2);
        verify(note.hasInk);
        compare(note.modified, 1700000000000);
        verify(note.cloud.dirty, "a changed note has something to upload");
    }
}
