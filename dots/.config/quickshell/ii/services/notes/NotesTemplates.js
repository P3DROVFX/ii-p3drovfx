.pragma library

.import "NotesDocument.js" as Doc

/**
 * The notes you start from instead of from nothing.
 *
 * Three things went wrong in the first version of this file and all three were invisible
 * from the outside:
 *
 *  - Every template was written in Portuguese, in an app whose every other string is
 *    English and translated from it. A shell in Japanese offered "Receita Culinária".
 *  - The block fields were guesses. `style: "numbered"` is not a list style the model has
 *    (it is `number`), and `calloutType` is not a field at all (it is `tone`), so
 *    `normalizeBlock` quietly dropped both: every numbered list came out as bullets and
 *    every callout as the default tone.
 *  - `new Date()` was evaluated once, when this library was first loaded. A shell left
 *    running for a week stamped last week's date on today's journal.
 *
 * So: English, only fields the schema in `NotesDocument.js` declares, and `%date%` filled
 * in when the template is used rather than when the file is read.
 */

var DATE_TOKEN = "%date%";

var BUILTIN_TEMPLATES = [
    {
        id: "meeting",
        name: "Meeting",
        description: "Who came, what was said, what was decided, and who does what next.",
        icon: "groups",
        tags: ["meeting"],
        blocks: [
            { type: "heading", level: 1, text: "Meeting: " },
            { type: "callout", tone: "info", text: DATE_TOKEN + " · chaired by " },
            { type: "heading", level: 2, text: "Who is here" },
            { type: "list", style: "bullet", text: "" },
            { type: "heading", level: 2, text: "What we are here for" },
            { type: "list", style: "number", text: "" },
            { type: "list", style: "number", text: "" },
            { type: "heading", level: 2, text: "Notes" },
            { type: "text", text: "" },
            { type: "heading", level: 2, text: "Decided" },
            { type: "list", style: "checkbox", checked: false, text: "" },
            { type: "heading", level: 2, text: "Next" },
            { type: "list", style: "checkbox", checked: false, text: "Who · what · by when" }
        ]
    },
    {
        id: "journal",
        name: "Journal",
        description: "One day: what matters, what you are grateful for, and how it went.",
        icon: "auto_stories",
        tags: ["journal"],
        blocks: [
            { type: "heading", level: 1, text: DATE_TOKEN },
            { type: "heading", level: 2, text: "The one thing today" },
            { type: "list", style: "checkbox", checked: false, text: "" },
            { type: "heading", level: 2, text: "Grateful for" },
            { type: "list", style: "bullet", text: "" },
            { type: "list", style: "bullet", text: "" },
            { type: "list", style: "bullet", text: "" },
            { type: "heading", level: 2, text: "What happened" },
            { type: "text", text: "" },
            { type: "heading", level: 2, text: "Tonight" },
            { type: "quote", text: "What went well? What would you do differently tomorrow?" }
        ]
    },
    {
        id: "tasks",
        name: "Tasks",
        description: "Four boxes: now, in progress, next, and someday.",
        icon: "checklist",
        tags: ["tasks"],
        blocks: [
            { type: "heading", level: 1, text: "Tasks" },
            { type: "heading", level: 2, text: "Now" },
            { type: "list", style: "checkbox", checked: false, text: "" },
            { type: "heading", level: 2, text: "In progress" },
            { type: "list", style: "checkbox", checked: false, text: "" },
            { type: "heading", level: 2, text: "Next" },
            { type: "list", style: "checkbox", checked: false, text: "" },
            { type: "heading", level: 2, text: "Someday" },
            { type: "list", style: "bullet", text: "" }
        ]
    },
    {
        id: "code",
        name: "Code",
        description: "A snippet, what it is for, and how to run it.",
        icon: "code",
        tags: ["code"],
        blocks: [
            { type: "heading", level: 1, text: "Snippet: " },
            { type: "callout", tone: "info", text: "Language · project · file" },
            { type: "heading", level: 2, text: "The code" },
            { type: "code", language: "python", text: "" },
            { type: "heading", level: 2, text: "How it works" },
            { type: "text", text: "" },
            { type: "heading", level: 2, text: "Running it" },
            { type: "code", language: "bash", text: "" }
        ]
    },
    {
        id: "recipe",
        name: "Recipe",
        description: "Ingredients you can tick off, and the steps in order.",
        icon: "restaurant",
        tags: ["recipe"],
        blocks: [
            { type: "heading", level: 1, text: "Recipe: " },
            { type: "callout", tone: "success", text: "Takes · serves · difficulty" },
            { type: "heading", level: 2, text: "Ingredients" },
            { type: "list", style: "checkbox", checked: false, text: "" },
            { type: "list", style: "checkbox", checked: false, text: "" },
            { type: "list", style: "checkbox", checked: false, text: "" },
            { type: "heading", level: 2, text: "Method" },
            { type: "list", style: "number", text: "" },
            { type: "list", style: "number", text: "" },
            { type: "list", style: "number", text: "" },
            { type: "heading", level: 2, text: "Notes for next time" },
            { type: "quote", text: "" }
        ]
    },
    {
        id: "review",
        name: "Review",
        description: "What happened, what worked, what did not, and what changes.",
        icon: "rate_review",
        tags: ["review"],
        blocks: [
            { type: "heading", level: 1, text: "Review: " },
            { type: "callout", tone: "info", text: DATE_TOKEN },
            { type: "heading", level: 2, text: "In short" },
            { type: "text", text: "" },
            { type: "heading", level: 2, text: "What worked" },
            { type: "list", style: "bullet", text: "" },
            { type: "list", style: "bullet", text: "" },
            { type: "heading", level: 2, text: "What did not" },
            { type: "list", style: "bullet", text: "" },
            { type: "heading", level: 2, text: "What changes" },
            { type: "list", style: "checkbox", checked: false, text: "" }
        ]
    }
];

function getBuiltinTemplates() {
    return BUILTIN_TEMPLATES.slice();
}

/// Today, written the way this machine writes dates.
function todayLabel() {
    return new Date().toLocaleDateString();
}

/**
 * A template into blocks, with fresh ids and today's date.
 */
function instantiateBlocks(templateDef) {
    if (!templateDef || !Array.isArray(templateDef.blocks))
        return [Doc.normalizeBlock({ type: "text", text: "" })];

    var today = todayLabel();
    var blocks = [];
    for (var i = 0; i < templateDef.blocks.length; i++) {
        var raw = templateDef.blocks[i];
        var copy = {};
        for (var key in raw) {
            if (!raw.hasOwnProperty(key))
                continue;
            var value = raw[key];
            if (key === "text" && typeof value === "string")
                value = value.split(DATE_TOKEN).join(today);
            copy[key] = value;
        }
        copy.id = Doc.newBlockId();
        blocks.push(Doc.normalizeBlock(copy));
    }
    return blocks.length > 0 ? blocks : [Doc.normalizeBlock({ type: "text", text: "" })];
}
