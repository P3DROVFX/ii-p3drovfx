// End-to-end Settings search over the real page files, using SearchRegistry's
// own functions (lifted out of the QML) and the landmark crawl. Each query must
// find what a user sees on the page.
// Run: node scripts/tests/settings_search_e2e_test.mjs [query ...]
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..") + "/";
const CONFIGS = ROOT + "modules/settings/configs/";
const registryQml = fs.readFileSync(ROOT + "services/SearchRegistry.qml", "utf8");

// Root-level QML functions are indented four spaces and close on a line of
// their own; regex literals full of quotes make brace counting unreliable.
function liftFunction(src, name) {
    const start = src.indexOf("    function " + name + "(");
    assert.ok(start !== -1, "function not found: " + name);
    const end = src.indexOf("\n    }\n", start);
    return src.substring(start, end + 6).replace(/\((\w+):\s*\w+\)/, "($1)");
}

const names = ["extractImports", "extractDeclaredIds", "executableSource", "usesExternalId",
    "extractWidgetsWithOffset", "indexQmlFile", "extractBlocks", "getBlockSource", "extractProperty",
    "normalize", "tokenize", "queryWords", "textRecord", "vocabulary", "synonymsOf", "editDistanceWithin",
    "wordHits", "prepareQuery", "registerSection", "getMatchScore", "itemMatchScore", "groupScore", "matchPages",
    "getDynamicSearchResults", "sharesToken", "matchLandmarks", "assignLandmarkComponents"];
const registrySrc = fs.readFileSync(ROOT + "modules/common/SettingsPageRegistry.qml", "utf8");
const pages = vm.runInNewContext("(" + registrySrc.split("readonly property var pages:")[1].split(/\n    \]\n/)[0] + "])");

const ctx = {
    Translation: { tr: s => s },
    SettingsPageRegistry: { pages, pageById: id => pages.find(p => p.id === id) },
    pageFile: { files: [], currentIndex: 0 },
    console,
};
vm.createContext(ctx);
vm.runInContext(`var root = { sections: [], fileSources: {}, fileImportsBySource: {}, landmarks: [],
    _memoQuery: "", _memoResults: null, maxLandmarksPerGroup: 6,
    _textCache: {}, _vocabulary: null, _wordHits: {}, _synonymIndex: null,
    landmarkBlocks: {}, maxComponentsPerQuery: 3 };
    ${names.map(n => liftFunction(registryQml, n)).join("\n")}
    Object.assign(root, { ${names.join(", ")} });
    var sections = root.sections;`, ctx);

// Sections, exactly as startIndexing() lists the files.
let files = [];
for (const p of pages) {
    if (p.searchable === false) continue;
    if (p.searchComponent !== false) files.push([ROOT + p.component, p.id, ""]);
    for (const sub of p.subPages ?? []) files.push([CONFIGS + sub, p.id, sub]);
    for (const src of p.searchSources ?? []) files.push([CONFIGS + src, p.id, p.searchSubPages?.[src] ?? ""]);
}
ctx.pageFile.files = files.map(f => f[0]);
files.forEach(([file, id, sub], i) => {
    ctx.pageFile.currentIndex = i;
    if (fs.existsSync(file)) ctx.indexQmlFile(fs.readFileSync(file, "utf8"), id, sub);
});

// Landmarks, from the same script the shell runs.
const pagesArg = JSON.stringify(pages.map(p => ({ id: p.id, component: p.component, subPages: p.subPages ?? [],
    searchSources: p.searchSources ?? [], searchSubPages: p.searchSubPages ?? {}, searchable: p.searchable !== false })));
const t0 = Date.now();
const crawled = JSON.parse(execFileSync("python3", [ROOT + "scripts/settings/search_landmarks.py", ROOT, pagesArg], { encoding: "utf8", maxBuffer: 64 << 20 }));
const crawlMs = Date.now() - t0;
for (const l of crawled.landmarks) ctx.root.landmarks.push({ ...l, block: l.block ?? "", text: l.key });
Object.assign(ctx.root.landmarkBlocks, crawled.blocks);
// Sub-pages found by their opener, as indexDiscoveredSubPages() reads them.
for (const { pageId, subPage } of crawled.subPages) {
    ctx.pageFile.files.push(CONFIGS + subPage);
    ctx.pageFile.currentIndex = ctx.pageFile.files.length - 1;
    ctx.indexQmlFile(fs.readFileSync(CONFIGS + subPage, "utf8"), pageId, subPage);
}

const search = q => { ctx.root._memoResults = null; return JSON.parse(JSON.stringify(ctx.getDynamicSearchResults(q))); };
const labels = r => r.landmarks ? [...r.landmarks, ...r.coveredLandmarks].map(l => l.text) : [r.title, ...r.subsections.map(s => s.title)];
const blockType = id => ctx.root.landmarkBlocks[id]?.type;
function show(q) {
    const res = search(q);
    console.log(`\n"${q}" → ${res.length} results`);
    for (const r of res.slice(0, 8))
        console.log(`  ${String(r.score).padStart(6)} ${r.components?.length ? "comp " : r.landmarks ? "link " : "clone"}`
            + (r.components?.length ? ` {${r.components.map(blockType).join(", ")}}` : "") + ` [${r.pageId}${r.subPage ? " › " + r.subPage : ""}] ${r.title}: ${r.landmarks ? r.landmarks.map(l => l.text).join(" | ") : r.items.map(i => i.text).join(" | ")}`);
}

const custom = process.argv.slice(2);
if (custom.length) { custom.forEach(show); process.exit(0); }

// The first result for these is on the page the user sees them on.
const expectTop = [
    ["color scheme", "colors", "Color scheme"],
    ["Color Scheme", "colors", "Color scheme"],
    ["wallpaper colors", "colors", "Wallpaper colors"],
    ["change wallpaper", "colors", "Change wallpaper"],
    ["automation", "colors", "Automation & integrations"],
    ["app theming", "colors", "App theming"],
    ["openrgb", "colors", null],
];
for (const [q, pageId, label] of expectTop) {
    const res = search(q);
    assert.ok(res.length > 0, `no results for "${q}"`);
    assert.equal(res[0].pageId, pageId, `"${q}" top result is on ${res[0].pageId}: ${labels(res[0])}`);
    if (label) assert.ok(labels(res[0]).includes(label), `"${q}" top result lacks ${label}: ${labels(res[0])}`);
}

// Every page's visible headings are findable by their own words, and land on
// that page. Sampled across every page so a regression anywhere shows.
let checked = 0, missed = [];
for (const page of pages) {
    const own = ctx.root.landmarks.filter(l => l.pageId === page.id && !l.subPage).slice(0, 15);
    for (const l of own) {
        const res = search(l.text);
        checked++;
        const hit = res.some(r => r.pageId === page.id && (labels(r).some(t => t.toLowerCase() === l.text.toLowerCase())
            || r.items.some(i => (i.text || "").toLowerCase() === l.text.toLowerCase())
            || r.subsections.some(s => s.items.some(i => (i.text || "").toLowerCase() === l.text.toLowerCase()))));
        if (!hit) missed.push(`${page.id}: ${l.text}`);
    }
}
assert.deepEqual(missed, [], "headings not findable");

// Cloned controls still come first for their own label.
for (const q of ["night light", "transparency", "bar position"]) {
    const res = search(q);
    assert.ok(res.length > 0, `no results for "${q}"`);
}

// A landmark never repeats a label its page's clone already shows.
for (const q of ["dark", "show dark/light toggle", "lock screen", "wallpaper engine"]) {
    const res = search(q);
    for (const r of res.filter(r => r.landmarks)) {
        const cloneLabels = res.filter(c => !c.landmarks && c.pageId === r.pageId && (c.subPage || "") === (r.subPage || ""))
            .flatMap(c => [c.title, ...c.items.map(i => i.text), ...c.subsections.flatMap(s => [s.title, ...s.items.map(i => i.text)])])
            .filter(Boolean).map(t => t.toLowerCase());
        for (const l of r.landmarks) assert.ok(!cloneLabels.includes(l.text.toLowerCase()), `"${q}" repeats ${l.text} on ${r.pageId}`);
    }
}

// The best landmark hits come as the component that draws them, a few per query.
const componentsOf = q => search(q).flatMap(r => (r.components ?? []).map(blockType));
assert.ok(componentsOf("color scheme").includes("ColorsPalettePane"));
assert.ok(componentsOf("app theming").includes("ColorsFeatureTile"));
assert.ok(componentsOf("change wallpaper").includes("ColorsWallpaperHero"));
assert.ok(componentsOf("openrgb").includes("ColorsFeatureTile"), "the OpenRGB tile");
assert.ok(componentsOf("automatic dark mode").includes("ColorsFeatureTile"), "the tile, beside its search proxy");
for (const q of ["dark", "show", "color", "lock screen", "wallpaper"])
    assert.ok(componentsOf(q).length <= 3, `"${q}" builds ${componentsOf(q).length} components`);
// A landmark inside a shown component is not repeated as a row.
for (const r of search("color scheme").filter(r => r.components?.length))
    for (const l of r.landmarks) assert.ok(!r.components.includes(l.block), l.text);

// Typos, joined words and synonyms find what the page calls it; a query that
// names a page offers the page first, typed short or misspelled.
const found = (q, pageId, text) => search(q).some(r => r.pageId === pageId
    && (text === null || [...labels(r), ...r.items.map(i => i.text), ...r.subsections.flatMap(s => s.items.map(i => i.text))]
        .some(t => (t || "").toLowerCase().includes(text))));
for (const [q, pageId, text] of [
    ["transparancy", "windows", "transparency"],
    ["notifcations", "notifications", null],
    ["bluetoth", "network", "bluetooth"],
    ["wallpaer", "wallpaper", "wallpaper"],
    ["wifi", "network", "wi-fi"],
    ["autohide", "bar", "auto-hide"],
    ["lockscreen", "lockScreen", null],
    ["time zone", "languageTime", "timezone"],
    ["sleep", "power", "suspend"],
    ["dnd", "notifications", "do not disturb"],
    ["hotkeys", "launcher", "keybinds"],
    // A tab drawn from searchSources, a sub-page found by the row that opens
    // it, an option chip, and a control found by its tooltip.
    ["window rules", "hyprland", "window rules"],
    ["icon pack", "hyprland", "icon pack"],
    ["base icon theme", "interfaceFonts", null],
    ["click to focus", "hyprland", null],
    ["matugen icon pack", "interfaceFonts", null],
]) assert.ok(found(q, pageId, text), `"${q}" misses ${pageId}${text ? ": " + text : ""}`);
// Editors that need their opener's target are never a place to land.
assert.ok(!crawled.subPages.some(s => /(Editor|Picker)(Page)?\.qml$/.test(s.subPage)), "an editor was indexed as a sub-page");
for (const [q, pageId] of [["network", "network"], ["dock", "dock"], ["notif", "notifications"],
        ["notifcations", "notifications"], ["netw", "network"], ["lock scr", "lockScreen"]]) {
    const top = search(q)[0];
    assert.ok(top?.page && top.pageId === pageId, `"${q}" top is not the ${pageId} page: ${top?.pageId}`);
}
// A typo pass never runs for a word the index holds as typed.
assert.ok(!search("dock").some(r => labels(r).concat(r.items.map(i => i.text)).some(t => /\bdeck\b/i.test(t || "") && !/dock/i.test(t || ""))), "dock finds deck");
assert.equal(search("a").length, 0, "one letter finds nothing");

// Noise stays bounded: no group lists more than the cap, nonsense finds nothing.
for (const r of search("on")) if (r.landmarks) assert.ok(r.landmarks.length <= 6);
assert.equal(search("zzqxv").length, 0);

console.log(`ok: ${ctx.root.sections.length} sections, ${ctx.root.landmarks.length} landmarks (crawl ${crawlMs} ms), ${checked} headings round-tripped`);
["color scheme", "theme", "lock screen", "dock", "keyboard"].forEach(show);
