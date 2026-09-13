.pragma library
.import "NotesDocument.js" as Doc

// Turning what someone typed into what they meant.
//
// Two rules, and they are the whole file:
//
//   1. A markdown prefix at the start of a paragraph changes the *block*, and the prefix
//      itself disappears. Typing "- " makes a bullet, not a paragraph beginning with a
//      hyphen. This is how a person writes structure without leaving the keyboard, and it
//      is the reason the editor needs no toolbar to be usable.
//
//   2. Enter on an empty list item, quote or callout leaves that structure rather than
//      making another empty one. Every editor worth using does this, and its absence is
//      immediately felt: the only way out of a list becomes the mouse.
//
// Pure, so both can be checked without an editor, a shell, or a keyboard.

/// Prefixes that change a paragraph into something else. Order matters: "###" has to be
/// tested before "##", or the shorter one matches first and eats a level.
var PREFIXES = [
    { pattern: /^######\s/, type: "heading", props: { level: 3 } },
    { pattern: /^#####\s/, type: "heading", props: { level: 3 } },
    { pattern: /^####\s/, type: "heading", props: { level: 3 } },
    { pattern: /^###\s/, type: "heading", props: { level: 3 } },
    { pattern: /^##\s/, type: "heading", props: { level: 2 } },
    { pattern: /^#\s/, type: "heading", props: { level: 1 } },
    { pattern: /^[-*+]\s\[[ xX]\]\s/, type: "list", props: { style: "checkbox" } },
    { pattern: /^\[[ xX]\]\s/, type: "list", props: { style: "checkbox" } },
    { pattern: /^[-*+]\s/, type: "list", props: { style: "bullet" } },
    { pattern: /^\d+[.)]\s/, type: "list", props: { style: "number" } },
    { pattern: /^>\s/, type: "quote", props: {} },
    { pattern: /^```/, type: "code", props: {} }
];

/// Typed on its own, these become a divider. Checked against the whole text rather than a
/// prefix: three hyphens inside a sentence are three hyphens.
var DIVIDER = /^\s*(?:-{3,}|_{3,}|\*{3,})\s*$/;

/**
 * What the block should become, given the text that is now in it.
 *
 * Returns `{ type, props, text }` or null. `text` is what remains after the prefix is
 * taken away, which the caller writes back — the prefix was an instruction, not content.
 *
 * Only ever fires on a `text` block. Somewhere in the middle of a heading, "#" is a
 * character like any other, and a list item that starts with "- " is a person typing a
 * hyphen inside their bullet.
 */
function conversionFor(blockValue, typedText) {
    var block = blockValue && typeof blockValue === "object" ? blockValue : {};
    if (block.type !== "text")
        return null;
    var text = String(typedText === null || typedText === undefined ? "" : typedText);

    if (DIVIDER.test(text) && text.trim().length >= 3)
        return { type: "divider", props: {}, text: "" };

    for (var i = 0; i < PREFIXES.length; i++) {
        var rule = PREFIXES[i];
        var match = rule.pattern.exec(text);
        if (!match)
            continue;
        var props = {};
        for (var key in rule.props)
            props[key] = rule.props[key];
        // A checkbox typed with an x in it starts ticked. Somebody writing "- [x] " is
        // recording something they already did.
        if (rule.type === "list" && props.style === "checkbox")
            props.checked = /\[[xX]\]/.test(match[0]);
        return { type: rule.type, props: props, text: text.slice(match[0].length) };
    }
    return null;
}

/**
 * Whether pressing Enter here should leave the structure instead of continuing it.
 *
 * True for an empty list item, quote or callout. An indented one steps out one level
 * first, which is what a nested list needs: the way out of three levels is three Enters,
 * not one that drops you back to the margin.
 */
function shouldExit(blockValue) {
    var block = blockValue && typeof blockValue === "object" ? blockValue : {};
    if (["list", "quote", "callout"].indexOf(block.type) < 0)
        return false;
    return String(block.text ?? "").length === 0;
}

/**
 * The operations for that exit: one step out of the indent, or back to a paragraph.
 */
function exitOperations(blockValue) {
    var block = blockValue && typeof blockValue === "object" ? blockValue : {};
    if (!shouldExit(block))
        return [];
    var indent = Number(block.indent) || 0;
    if (indent > 0)
        return [{ op: "indent", id: block.id, delta: -1 }];
    return [{ op: "setType", id: block.id, type: "text", props: { text: "", indent: 0 } }];
}

/**
 * The operations for a conversion, ready for `Doc.applyOps`.
 *
 * A divider is a block with nothing to type in, so it is followed by a fresh paragraph —
 * otherwise typing "---" leaves the cursor nowhere.
 */
function conversionOperations(blockValue, conversion, index) {
    var block = blockValue && typeof blockValue === "object" ? blockValue : {};
    if (!conversion)
        return [];
    var props = {};
    for (var key in conversion.props)
        props[key] = conversion.props[key];
    props.text = conversion.text;
    if (block.hasOwnProperty("indent"))
        props.indent = Number(block.indent) || 0;

    var ops = [{ op: "setType", id: block.id, type: conversion.type, props: props }];
    if (conversion.type === "divider")
        ops.push({ op: "insert", index: Number(index) + 1, block: { type: "text", text: "" } });
    return ops;
}
