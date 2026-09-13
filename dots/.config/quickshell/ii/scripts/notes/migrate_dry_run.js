#!/usr/bin/env node
// What migrating `notes.json` into the notes store would do — without doing any of it.
//
// The migration itself belongs to the shell, which runs it once on first launch. This
// tool exists so the result can be inspected against a real notes.json before that ever
// happens, and so the promise "the original is not touched" is verifiable rather than
// asserted: this process opens exactly one file, for reading.
//
// Usage:
//   node scripts/notes/migrate_dry_run.js [--input PATH] [--json] [--keep-empty]

const fs = require("fs");
const os = require("os");
const path = require("path");
const { loadQmlJs } = require("./qml_js.js");

const Migration = loadQmlJs(path.resolve(__dirname, "../../services/notes/NotesMigration.js"));

function parseArgs(argv) {
    const state = process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local/state");
    const options = {
        input: path.join(state, "quickshell/user/notes.json"),
        json: false,
        dropEmptyDefaults: true
    };
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === "--input" || argv[i] === "-i")
            options.input = argv[++i];
        else if (argv[i] === "--json")
            options.json = true;
        else if (argv[i] === "--keep-empty")
            options.dropEmptyDefaults = false;
        else if (argv[i] === "--help" || argv[i] === "-h")
            options.help = true;
    }
    return options;
}

function main() {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) {
        console.log("usage: migrate_dry_run.js [--input PATH] [--json] [--keep-empty]");
        return 0;
    }

    if (!fs.existsSync(options.input)) {
        console.error(`no legacy notes at ${options.input}`);
        return 1;
    }

    let legacy;
    try {
        legacy = JSON.parse(fs.readFileSync(options.input, "utf8"));
    } catch (error) {
        console.error(`could not parse ${options.input}: ${error.message}`);
        return 1;
    }

    const plan = Migration.migrateLegacy(legacy, {
        now: Date.now(),
        notebookTitle: "Notes",
        sectionTitle: "General",
        untitled: "Untitled note",
        dropEmptyDefaults: options.dropEmptyDefaults
    });
    const files = Migration.filesFor(plan);

    if (options.json) {
        console.log(JSON.stringify({ plan: plan, files: files.map(f => f.path) }, null, 2));
        return 0;
    }

    const missing = plan.assets.filter(asset => !fs.existsSync(asset.from));

    console.log(`legacy file   ${options.input}  (read only, never written)`);
    console.log(`tabs          ${plan.stats.tabs}`);
    console.log(`notes         ${plan.stats.notes}   (${plan.stats.withInk} with ink, ${plan.stats.withText} with text)`);
    console.log(`skipped       ${plan.stats.skipped}${plan.skipped.length ? "   " + plan.skipped.map(s => `"${s.title}"`).join(", ") : ""}`);
    console.log("");
    console.log("would write:");
    for (const file of files)
        console.log(`  notes/${file.path}`);
    console.log("");
    console.log("would copy:");
    for (const asset of plan.assets)
        console.log(`  ${asset.from}\n    -> notes/assets/${asset.noteId}/${asset.to}${fs.existsSync(asset.from) ? "" : "   [SOURCE MISSING]"}`);
    if (plan.assets.length === 0)
        console.log("  (nothing)");
    console.log("");
    console.log("resulting index:");
    for (const note of plan.index.notes) {
        const when = new Date(note.created).toISOString().slice(0, 16).replace("T", " ");
        const marks = [note.hasInk ? "ink" : null, note.hasImages ? "img" : null]
            .filter(Boolean).join(",");
        console.log(`  ${when}  ${note.blockCount} blocks  ${marks.padEnd(7)} ${note.title}`);
        if (note.preview.length > 0)
            console.log(`               ${note.preview.slice(0, 70)}`);
    }

    if (missing.length > 0) {
        console.log("");
        console.log(`WARNING: ${missing.length} sketch file(s) referenced by notes.json are not on disk.`);
        console.log("Those notes migrate with an ink block pointing at a file that is not there.");
    }
    return 0;
}

process.exit(main());
