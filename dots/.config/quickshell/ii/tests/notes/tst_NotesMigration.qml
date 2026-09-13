import QtQuick
import QtTest
import "../../services/notes/NotesDocument.js" as Doc
import "../../services/notes/NotesMigration.js" as Migration

TestCase {
    name: "NotesMigration"

    // A millisecond timestamp does not fit in an int; QML would reject the assignment.
    readonly property real fixedNow: 1757030400000  // 2026-09-05T00:00:00Z

    function json(value) { return JSON.stringify(value); }

    /// The shape `notes.json` actually has on disk, including the default tab the old
    /// service hands out and the absolute sketch paths it writes.
    function legacy() {
        return {
            tabs: [
                { title: "Tab 1", icon: "article", content: "", sketch: "" },
                { title: "Shopping", icon: "article", content: "# List\n\n- [ ] milk\n- [x] bread", sketch: "" },
                {
                    title: "Sketch 4 Sep, 00:18",
                    icon: "draw",
                    content: "",
                    sketch: "/home/x/.local/state/quickshell/user/note_sketches/sketch-2026-09-04T03-18-31-234Z.png"
                }
            ]
        };
    }

    function plan(options) {
        const merged = { now: fixedNow, notebookTitle: "Notes", sectionTitle: "General" };
        for (const key in (options || {}))
            merged[key] = options[key];
        return Migration.migrateLegacy(legacy(), merged);
    }

    // ── What comes across ─────────────────────────────────────────────────

    function test_every_tab_that_holds_something_becomes_a_note() {
        const result = plan();
        compare(result.stats.tabs, 3);
        compare(result.stats.notes, 2);
        compare(result.index.notes[0].title, "Shopping");
        compare(result.index.notes[1].title, "Sketch 4 Sep, 00:18");
    }

    function test_the_content_string_becomes_blocks() {
        // The whole point: a note stops being one string and becomes structure that the
        // editor, search and export can each address.
        const document = plan().documents[0].document;
        compare(document.blocks[0].type, "heading");
        compare(document.blocks[0].text, "List");
        compare(document.blocks[1].type, "list");
        compare(document.blocks[1].style, "checkbox");
        verify(!document.blocks[1].checked);
        verify(document.blocks[2].checked);
    }

    function test_a_drawing_becomes_an_ink_block_and_a_file_to_copy() {
        const result = plan();
        const document = result.documents[1].document;
        const ink = document.blocks[document.blocks.length - 1];
        compare(ink.type, "ink");
        compare(ink.asset, "sketch-2026-09-04T03-18-31-234Z.png");

        compare(result.assets.length, 1);
        compare(result.assets[0].noteId, result.documents[1].noteId);
        compare(result.assets[0].to, "sketch-2026-09-04T03-18-31-234Z.png");
        compare(result.assets[0].from, legacy().tabs[2].sketch);
    }

    function test_an_untouched_default_tab_is_not_carried_over() {
        // "Tab 1" with nothing in it carries no information, and three empty notes on
        // first launch look like the migration invented them.
        const result = plan();
        compare(result.stats.skipped, 1);
        compare(result.skipped[0].title, "Tab 1");
    }

    function test_a_named_empty_note_is_still_the_users_note() {
        const result = Migration.migrateLegacy({
            tabs: [{ title: "Ideas", content: "", sketch: "" }]
        }, { now: fixedNow });
        compare(result.stats.notes, 1);
        compare(result.index.notes[0].title, "Ideas");
    }

    function test_keeping_the_empties_is_available_for_the_paranoid() {
        compare(plan({ dropEmptyDefaults: false }).stats.notes, 3);
    }

    // ── Dates ─────────────────────────────────────────────────────────────

    function test_a_drawings_date_is_recovered_from_its_filename() {
        // The old format stored no dates. Sorting by date would otherwise show a year of
        // drawings all made the morning of the migration.
        const note = plan().index.notes[1];
        compare(note.created, Date.parse("2026-09-04T03:18:31.234Z"));
        compare(note.modified, note.created);
    }

    function test_a_note_without_a_drawing_is_dated_now() {
        compare(plan().index.notes[0].created, fixedNow);
    }

    // ── The resulting store ───────────────────────────────────────────────

    function test_everything_lands_in_one_notebook_and_section() {
        const result = plan();
        compare(result.index.notebooks.length, 1);
        compare(result.index.notebooks[0].title, "Notes");
        compare(result.index.notebooks[0].sections.length, 1);
        const notebookId = result.index.notebooks[0].id;
        const sectionId = result.index.notebooks[0].sections[0].id;
        for (const note of result.index.notes) {
            compare(note.notebookId, notebookId);
            compare(note.sectionId, sectionId);
        }
    }

    function test_index_records_describe_their_documents() {
        const result = plan();
        compare(result.index.notes[0].preview, "List milk bread");
        verify(!result.index.notes[0].hasInk);
        verify(result.index.notes[1].hasInk);
        compare(result.index.notes[1].icon, "draw");
    }

    function test_the_file_list_matches_the_notes() {
        const result = plan();
        const files = Migration.filesFor(result);
        compare(files.length, 3);
        compare(files[0].path, "index.json");
        compare(files[1].path, "docs/" + result.documents[0].noteId + ".json");
        compare(files[2].path, "docs/" + result.documents[1].noteId + ".json");
    }

    function test_every_note_id_is_distinct() {
        const seen = {};
        for (const note of plan({ dropEmptyDefaults: false }).index.notes) {
            verify(!seen[note.id], "two notes shared an id");
            seen[note.id] = true;
        }
    }

    // ── Nothing to migrate ────────────────────────────────────────────────

    function test_a_legacy_file_that_is_not_one_produces_an_empty_store() {
        for (const value of [null, undefined, {}, { tabs: "no" }, 7]) {
            const result = Migration.migrateLegacy(value, { now: fixedNow });
            compare(result.stats.notes, 0);
            compare(result.index.notes.length, 0);
            // No notebook either: an empty shelf nobody asked for.
            compare(result.index.notebooks.length, 0);
        }
    }

    function test_a_default_install_migrates_to_nothing() {
        // The old service seeds three empty tabs. A user who never wrote a note should
        // arrive at an empty app, not at three blank pages.
        const result = Migration.migrateLegacy({
            tabs: [
                { title: "Tab 1", icon: "article", content: "" },
                { title: "Tab 2", icon: "article", content: "" },
                { title: "Tab 3", icon: "article", content: "" }
            ]
        }, { now: fixedNow });
        compare(result.stats.notes, 0);
        compare(result.stats.skipped, 3);
    }

    function test_a_note_with_no_name_at_all_gets_one() {
        const result = Migration.migrateLegacy({
            tabs: [{ title: "", content: "some body text" }]
        }, { now: fixedNow, untitled: "Untitled note" });
        // Taken from the content before falling back to the placeholder.
        compare(result.index.notes[0].title, "some body text");
    }
}
