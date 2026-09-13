import QtQuick
import QtTest
import "../../services/notes/NotesDocument.js" as Doc
import "../../services/notes/NotesShortcuts.js" as Shortcuts

TestCase {
    name: "NotesShortcuts"

    function paragraph(text, indent) {
        return Doc.block("text", { text: text ?? "", indent: indent ?? 0 });
    }

    // ── Typing structure ──────────────────────────────────────────────────

    function test_a_prefix_changes_the_block_and_then_disappears() {
        // Typing "- " makes a bullet, not a paragraph that starts with a hyphen. The
        // prefix was an instruction, not content.
        const bullet = Shortcuts.conversionFor(paragraph(""), "- milk");
        compare(bullet.type, "list");
        compare(bullet.props.style, "bullet");
        compare(bullet.text, "milk");
    }

    function test_every_heading_level_is_reachable_and_clamped() {
        compare(Shortcuts.conversionFor(paragraph(""), "# One").props.level, 1);
        compare(Shortcuts.conversionFor(paragraph(""), "## Two").props.level, 2);
        compare(Shortcuts.conversionFor(paragraph(""), "### Three").props.level, 3);
        // Markdown allows six; this document model draws three. Deeper input lands on the
        // deepest heading rather than on nothing at all.
        compare(Shortcuts.conversionFor(paragraph(""), "###### Six").props.level, 3);
    }

    function test_the_longer_prefix_wins() {
        // "###" has to be tested before "##", or the shorter pattern matches first and the
        // heading comes out a level too shallow.
        compare(Shortcuts.conversionFor(paragraph(""), "### Deep").props.level, 3);
        compare(Shortcuts.conversionFor(paragraph(""), "- [ ] task").props.style, "checkbox");
    }

    function test_a_ticked_checkbox_starts_ticked() {
        // Somebody typing "- [x] " is recording something they already did.
        verify(Shortcuts.conversionFor(paragraph(""), "- [x] shipped").props.checked);
        verify(!Shortcuts.conversionFor(paragraph(""), "- [ ] pending").props.checked);
        compare(Shortcuts.conversionFor(paragraph(""), "[x] short form").props.style, "checkbox");
    }

    function test_numbered_and_quoted_and_fenced() {
        compare(Shortcuts.conversionFor(paragraph(""), "1. first").props.style, "number");
        compare(Shortcuts.conversionFor(paragraph(""), "3) third").props.style, "number");
        compare(Shortcuts.conversionFor(paragraph(""), "> quoted").type, "quote");
        compare(Shortcuts.conversionFor(paragraph(""), "```js").type, "code");
    }

    function test_a_rule_on_its_own_line_is_a_divider() {
        compare(Shortcuts.conversionFor(paragraph(""), "---").type, "divider");
        compare(Shortcuts.conversionFor(paragraph(""), "***").type, "divider");
        // Three hyphens inside a sentence are three hyphens.
        compare(Shortcuts.conversionFor(paragraph(""), "a --- b"), null);
        compare(Shortcuts.conversionFor(paragraph(""), "--"), null);
    }

    function test_nothing_happens_without_a_prefix() {
        compare(Shortcuts.conversionFor(paragraph(""), "just typing"), null);
        compare(Shortcuts.conversionFor(paragraph(""), ""), null);
        compare(Shortcuts.conversionFor(paragraph(""), "#nospace"), null);
    }

    function test_a_prefix_only_means_anything_in_a_paragraph() {
        // Halfway through a heading, "#" is a character. A bullet that begins with "- " is
        // somebody typing a hyphen inside their bullet.
        compare(Shortcuts.conversionFor(Doc.block("heading", {}), "# not again"), null);
        compare(Shortcuts.conversionFor(Doc.block("list", {}), "- nested?"), null);
        compare(Shortcuts.conversionFor(Doc.block("code", {}), "# a comment"), null);
    }

    // ── The operations they produce ───────────────────────────────────────

    function test_a_conversion_keeps_the_block_and_its_indentation() {
        const block = paragraph("", 2);
        const conversion = Shortcuts.conversionFor(block, "- item");
        const ops = Shortcuts.conversionOperations(block, conversion, 0);
        compare(ops.length, 1);
        compare(ops[0].op, "setType");
        compare(ops[0].id, block.id);
        compare(ops[0].props.indent, 2);
        compare(ops[0].props.text, "item");
    }

    function test_a_divider_brings_a_paragraph_with_it() {
        // A divider has nothing to type in. Without the paragraph after it, typing "---"
        // leaves the cursor nowhere.
        const block = paragraph("");
        const ops = Shortcuts.conversionOperations(block, Shortcuts.conversionFor(block, "---"), 4);
        compare(ops.length, 2);
        compare(ops[1].op, "insert");
        compare(ops[1].index, 5);
        compare(ops[1].block.type, "text");
    }

    function test_the_operations_actually_apply() {
        const document = Doc.normalizeDocument({ blocks: [{ id: "a", type: "text", text: "" }] });
        const block = document.blocks[0];
        const result = Doc.applyOps(document,
            Shortcuts.conversionOperations(block, Shortcuts.conversionFor(block, "## Heading"), 0));
        verify(result.changed);
        compare(result.document.blocks[0].type, "heading");
        compare(result.document.blocks[0].level, 2);
        compare(result.document.blocks[0].text, "Heading");
        compare(result.document.blocks[0].id, "a");
    }

    // ── Getting out again ─────────────────────────────────────────────────

    function test_enter_on_an_empty_item_leaves_the_list() {
        // Without this the only way out of a list is the mouse.
        verify(Shortcuts.shouldExit(Doc.block("list", { text: "" })));
        verify(Shortcuts.shouldExit(Doc.block("quote", { text: "" })));
        verify(!Shortcuts.shouldExit(Doc.block("list", { text: "still writing" })));
        verify(!Shortcuts.shouldExit(Doc.block("text", { text: "" })));
    }

    function test_leaving_a_nested_item_steps_out_one_level_at_a_time() {
        // Three levels deep, the way out is three Enters — not one that drops you back to
        // the margin.
        const nested = Doc.block("list", { text: "", indent: 2 });
        const ops = Shortcuts.exitOperations(nested);
        compare(ops.length, 1);
        compare(ops[0].op, "indent");
        compare(ops[0].delta, -1);

        const flat = Doc.block("list", { text: "", indent: 0 });
        compare(Shortcuts.exitOperations(flat)[0].op, "setType");
        compare(Shortcuts.exitOperations(flat)[0].type, "text");
    }

    function test_nothing_to_exit_produces_nothing() {
        compare(Shortcuts.exitOperations(Doc.block("text", {})).length, 0);
        compare(Shortcuts.exitOperations(null).length, 0);
    }
}
