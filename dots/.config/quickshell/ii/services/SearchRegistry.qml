pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    // A plain JS array, not list<var>: every push() onto a list<var> converted
    // the object and rewrote the property (~800 ms across 460 sections), and
    // every read handed back a fresh deep copy, so each search re-copied the
    // whole index and preset names pushed onto a section were lost.
    property var sections: []
    property var fileSources: ({})
    property var fileImportsBySource: ({})
    // Headings, labels and chips the redesigned pages draw outside any cloneable
    // control ({ pageId, subPage, key, text, subPageTitle }); see scripts/settings/search_landmarks.py.
    property var landmarks: []
    // Clone sources of the settings components that draw landmarks, by block id:
    // { type, source, imports, dir, rootId }.
    property var landmarkBlocks: ({})
    // Components are built live; past this many per query the rest stay links.
    readonly property int maxComponentsPerQuery: 3
    readonly property int maxLandmarksPerGroup: 6
    property bool _sectionsDone: false
    property bool _landmarksDone: false
    property bool settingsActive: false
    property bool indexing: false
    property bool indexed: false

    signal indexReady

    // Accepting a search scores the query in SettingsWindow and again in
    // SearchPage; the second pass reuses the first while the index is unchanged.
    property string _memoQuery: ""
    property var _memoResults: null

    // Every indexed text split once, by text: a keystroke only looks words up.
    // Scoring used to re-normalize and re-split ~5000 texts on every query,
    // which is what kept search off the keystroke (cf. the launcher's
    // AiSettingsIntegration.scoreIndex).
    property var _textCache: ({})
    // Every word the index holds. Typo and synonym matching run once per
    // query word over this, not once per indexed text.
    property var _vocabulary: null
    // Query word -> { indexed word: score }, for the index in hand.
    property var _wordHits: ({})
    property var _synonymIndex: null

    // What the results page shows. Separate from currentSearch, which also
    // means "flash this heading" and is cleared by whatever it flashed.
    property string query: ""

    property string currentSearch: ""
    onCurrentSearchChanged: {
        console.log("Current found search result string:", currentSearch);
    }

    function startIndexing() {
        if (!root.settingsActive || root.indexing)
            return;

        sections = [];
        fileSources = ({});
        fileImportsBySource = ({});
        landmarks = [];
        landmarkBlocks = ({});
        root._memoResults = null;
        root._vocabulary = null;
        root._wordHits = ({});
        root.indexed = false;
        root.indexing = true;
        root._sectionsDone = false;
        root._landmarksDone = false;
        let configRoot = FileUtils.trimFileProtocol(Directories.config) + "/quickshell/ii/";
        let basePath = configRoot + "modules/settings/configs/";

        let files = [];
        let ids = [];
        let subPages = [];
        for (let p of SettingsPageRegistry.pages) {
            if (p.searchable === false)
                continue;
            // A page drawn with tiles, cards and live previews can have its options
            // indexed through `searchSources` alone: its own file would add the
            // sections whose controls name page ids, which a clone cannot resolve.
            if (p.searchComponent !== false) {
                files.push(configRoot + p.component);
                ids.push(p.id);
                subPages.push("");
            }
            for (let sub of (p.subPages ?? [])) {
                files.push(basePath + sub);
                ids.push(p.id);
                subPages.push(sub);
            }
            // Progressive settings sections live outside the page file, but
            // are not sub-pages. Index them with an empty subPage so a search
            // result navigates to the parent page and waits for the section's
            // own lazy loader instead of trying to open the source as a page.
            // A source that stands in for a sub-page's options opens that
            // sub-page instead (`searchSubPages`).
            for (let source of (p.searchSources ?? [])) {
                files.push(basePath + source);
                ids.push(p.id);
                subPages.push(p.searchSubPages?.[source] ?? "");
            }
        }

        pageFile.start(files, ids, subPages);
        listPresetsSearchProc.running = false;
        listPresetsSearchProc.running = true;
        landmarkCrawler.start(configRoot);

        if (files.length === 0)
            root.partIndexed("sections");
    }

    // Sections and landmarks are read side by side; the index is ready when both are.
    function partIndexed(part) {
        if (!root.indexing)
            return;
        if (part === "sections")
            root._sectionsDone = true;
        else
            root._landmarksDone = true;
        if (!root._sectionsDone || !root._landmarksDone)
            return;
        root.indexing = false;
        root.indexed = true;
        root._memoResults = null;
        root._vocabulary = null;
        root._wordHits = ({});
        root.indexReady();
    }

    /*
     * Sub-pages the landmark crawl found through the row that opens them, which
     * no page registers (Themed icons, the Hyprland icon pack picker, ...):
     * their controls are indexed like a registered sub-page's, before the
     * index counts as ready.
     */
    function indexDiscoveredSubPages(found) {
        if (!root.indexing || found.length === 0)
            return;
        const basePath = FileUtils.trimFileProtocol(Directories.config) + "/quickshell/ii/modules/settings/configs/";
        const files = found.map(s => basePath + s.subPage);
        const ids = found.map(s => s.pageId);
        const subs = found.map(s => s.subPage);
        if (!root._sectionsDone && pageFile.currentIndex < pageFile.files.length) {
            pageFile.files = pageFile.files.concat(files);
            pageFile.pageIds = pageFile.pageIds.concat(ids);
            pageFile.subPages = pageFile.subPages.concat(subs);
            return;
        }
        root._sectionsDone = false;
        pageFile.start(files, ids, subs);
    }

    function setSettingsActive(active) {
        root.settingsActive = active;
        if (!active) {
            root.clearIndex();
        }
    }

    function ensureIndexing() {
        if (!root.settingsActive || root.indexing || root.indexed)
            return;
        root.startIndexing();
    }

    function clearIndex() {
        root.indexing = false;
        root.indexed = false;
        root.sections = [];
        root.fileSources = ({});
        root.fileImportsBySource = ({});
        root.landmarks = [];
        root.landmarkBlocks = ({});
        root._memoResults = null;
        root._memoQuery = "";
        root._textCache = ({});
        root._vocabulary = null;
        root._wordHits = ({});
        root.query = "";
        root.currentSearch = "";
        pageFile.cancel();
        landmarkCrawler.cancel();
        listPresetsSearchProc.running = false;
    }

    Connections {
        target: Translation
        function onLanguageCodeChanged() {
            if (root.settingsActive && (root.indexed || root.indexing)) {
                root.clearIndex();
                root.startIndexing();
            }
        }
    }

    FileView {
        id: pageFile
        printErrors: false

        property var files: []
        property var pageIds: []
        property var subPages: []
        property int currentIndex: 0

        function start(filesArray, idsArray, subPagesArray) {
            pageFile.cancel();
            files = filesArray;
            pageIds = idsArray;
            subPages = subPagesArray || [];
            currentIndex = 0;
            loadNext();
        }

        function cancel() {
            files = [];
            pageIds = [];
            subPages = [];
            currentIndex = 0;
            path = "";
        }

        function loadNext() {
            if (currentIndex >= files.length)
                return;
            path = files[currentIndex];
        }

        function finishIndexing() {
            path = "";
            files = [];
            pageIds = [];
            subPages = [];
            currentIndex = 0;
            root.partIndexed("sections");
        }

        onLoaded: {
            if (currentIndex >= files.length || !root.indexing)
                return;
            root.indexQmlFile(text(), pageIds[currentIndex], subPages[currentIndex]);
            currentIndex++;
            if (currentIndex >= files.length) {
                finishIndexing();
            } else {
                Qt.callLater(() => loadNext());
            }
        }

        onLoadFailed: {
            if (currentIndex >= files.length || !root.indexing)
                return;
            currentIndex++;
            if (currentIndex >= files.length) {
                finishIndexing();
            } else {
                Qt.callLater(() => loadNext());
            }
        }
    }

    // Landmarks come from scripts/settings/search_landmarks.py, one run per
    // index: crawling the page component trees here held the UI thread for
    // seconds.
    QtObject {
        id: landmarkCrawler

        property bool active: false

        function start(configRoot) {
            cancel();
            active = true;
            const pages = SettingsPageRegistry.pages.map(p => ({
                id: p.id,
                component: p.component,
                subPages: p.subPages ?? [],
                searchSources: p.searchSources ?? [],
                searchSubPages: p.searchSubPages ?? ({}),
                searchable: p.searchable !== false
            }));
            landmarkReader.command = ["python3", Directories.scriptPath + "/settings/search_landmarks.py",
                configRoot, JSON.stringify(pages)];
            landmarkWatchdog.restart();
            landmarkReader.running = true;
        }

        function cancel() {
            active = false;
            landmarkWatchdog.stop();
            landmarkReader.running = false;
        }

        function received(text) {
            if (!active)
                return;
            let payload = null;
            try {
                payload = JSON.parse(text);
            } catch (e) {
                failed();
                return;
            }
            root.landmarkBlocks = payload.blocks ?? ({});
            root.landmarks = (payload.landmarks ?? []).map(l => ({
                pageId: l.pageId,
                subPage: l.subPage,
                key: l.key,
                block: l.block ?? "",
                text: Translation.tr(l.key),
                subPageTitle: l.subPageTitle ? Translation.tr(l.subPageTitle) : ""
            }));
            cancel();
            root.indexDiscoveredSubPages(payload.subPages ?? []);
            root.partIndexed("landmarks");
        }

        function failed() {
            // Landmarks are an addition: without them the index still holds
            // every cloneable control.
            if (!active)
                return;
            console.warn("[SearchRegistry] landmark crawl failed; searching controls only");
            cancel();
            root.partIndexed("landmarks");
        }
    }

    Process {
        id: landmarkReader
        stdout: StdioCollector {
            id: landmarkReaderOut
            onStreamFinished: landmarkCrawler.received(landmarkReaderOut.text)
        }
    }

    // A reader that never starts (no python3) never finishes its stream either.
    Timer {
        id: landmarkWatchdog
        // Generous: right after a reload the shell is busy recompiling and the
        // reader's output waits for it; a run cut short loses every landmark.
        interval: 30000
        onTriggered: landmarkCrawler.failed()
    }

    Process {
        id: listPresetsSearchProc
        command: ["bash", "-c", Directories.scriptPath + "/presets.sh list"]
        stdout: SplitParser {
            onRead: data => {
                if (!root.settingsActive || (!root.indexing && !root.indexed))
                    return;
                let str = data.trim();
                if (!str)
                    return;
                try {
                    let obj = JSON.parse(str);
                    if (obj && obj.name) {
                        root.addDynamicPresetName(obj.name);
                    }
                } catch (e) {
                    // Ignore parse errors
                }
            }
        }
    }

    function addDynamicPresetName(name) {
        root._memoResults = null;
        root._vocabulary = null;
        root._wordHits = ({});
        for (let i = 0; i < sections.length; i++) {
            let section = sections[i];
            if (section.pageId === "presets") {
                if (section.searchStrings.indexOf(name) === -1) {
                    section.searchStrings.push(name);
                }
            }
        }
    }

    function extractImports(text) {
        let imports = "";
        let lines = text.split("\n");
        for (let line of lines) {
            line = line.trim();
            if (line.startsWith("import ")) {
                imports += line + "\n";
            }
        }
        return imports;
    }

    function extractWidgets(text) {
        return extractWidgetsWithOffset(text, 0, "", extractDeclaredIds(text));
    }

    function extractDeclaredIds(text) {
        let ids = [];
        let match;
        const idPattern = /\bid\s*:\s*([A-Za-z_][A-Za-z0-9_]*)/g;
        const code = executableSource(text);
        while ((match = idPattern.exec(code)) !== null) {
            if (ids.indexOf(match[1]) === -1)
                ids.push(match[1]);
        }
        return ids;
    }

    function executableSource(text) {
        // Ignore prose when looking for page-local ids. Template strings stay
        // intact because their ${...} expressions are executable QML/JS.
        return text
            .replace(/"(?:\\.|[^"\\])*"/g, " ")
            .replace(/'(?:\\.|[^'\\])*'/g, " ")
            .replace(/\/\*[\s\S]*?\*\//g, " ")
            .replace(/\/\/[^\n]*/g, " ");
    }

    function usesExternalId(block, fileScopedIds) {
        if (!fileScopedIds || fileScopedIds.length === 0)
            return false;

        const localIds = extractDeclaredIds(block);
        const code = executableSource(block);
        for (let id of fileScopedIds) {
            if (localIds.indexOf(id) !== -1)
                continue;
            if (new RegExp("\\b" + id + "\\b").test(code))
                return true;
        }
        return false;
    }

    function extractWidgetsWithOffset(text, baseOffset, sourceKey, fileScopedIds) {
        let items = [];
        // Search results are live QML clones, so only compact, semantic
        // settings controls belong here. Structural layouts and informational
        // surfaces (NoticeBox, ShortcutBox, Flow, Row/ColumnLayout, service
        // cards, etc.) either duplicate their descendants or depend on page-
        // local ids and produce empty/broken result cards.
        let types = [
            "ConfigSwitch", "ConfigSpinBox", "ConfigSelectionArray", "ConfigTextField",
            "ConfigSlider", "ConfigComboBox", "ConfigLightDarkToggle", "ConfigSubpageRow"
        ];
        for (let t of types) {
            let blocks = extractBlocks(text, t);
            for (let b of blocks) {
                // Rows wired only through an `onClicked` closure usually refer
                // to ids from the original page. A declarative configPage is
                // self-contained and can be re-routed by the search section.
                if (t === "ConfigSubpageRow" && !/\bconfigPage\s*:/.test(b.inner))
                    continue;
                // A cloned control has no access to ids declared by its source
                // page or sibling controls. Skip it instead of rendering a
                // half-working result that throws ReferenceError at runtime.
                if (usesExternalId(b.inner, fileScopedIds))
                    continue;
                let textProp = extractProperty(b.inner, "text")
                            || extractProperty(b.inner, "title")
                            || extractProperty(b.inner, "tooltip")
                            || extractProperty(b.inner, "value")
                            || extractProperty(b.inner, "placeholderText")
                            || extractProperty(b.inner, "description")
                            || extractProperty(b.inner, "summary");
                // Every other word it shows: its tooltip, description and
                // option names ("Islands" on Dock style).
                let extra = [];
                // exec(), not matchAll(): the QML engine has no matchAll.
                const trRe = /Translation\.tr\(\s*"((?:\\.|[^"\\])*)"\s*\)/g;
                let m;
                while ((m = trRe.exec(b.inner)) !== null)
                    if (m[1] !== textProp && extra.indexOf(m[1]) === -1)
                        extra.push(m[1]);
                items.push({
                    type: t,
                    text: textProp,
                    extra: extra.join(" · "),
                    sourceKey: sourceKey,
                    sourceStart: b.start + baseOffset,
                    sourceEnd: b.end + baseOffset
                });
            }
        }
        return items;
    }

    function indexQmlFile(qmlText, pageId, subPage) {
        if (!qmlText) return;

        const sourceKey = pageFile.files[pageFile.currentIndex];
        const fileScopedIds = extractDeclaredIds(qmlText);
        let fileImports = extractImports(qmlText);
        let sectionsExtracted = extractBlocks(qmlText, "ContentSection");

        if (sectionsExtracted.length === 0)
            return;

        root.fileSources[sourceKey] = qmlText;
        root.fileImportsBySource[sourceKey] = fileImports;

        for (let sectionBlock of sectionsExtracted) {
            let sectionText = sectionBlock.inner;
            let title = extractProperty(sectionText, "title");
            let icon = extractProperty(sectionText, "icon");

            let searchStrings = [];
            let sectionItems = [];
            let sectionSubsections = [];

            // 1. extract subsections
            let subsections = extractBlocks(sectionText, "ContentSubsection", sectionBlock.innerStart);
            for (let subBlock of subsections) {
                let subTitle = extractProperty(subBlock.inner, "title");
                let subIcon = extractProperty(subBlock.inner, "icon");
                
                let subItems = extractWidgetsWithOffset(subBlock.inner, subBlock.innerStart, sourceKey, fileScopedIds);

                sectionSubsections.push({
                    title: subTitle,
                    icon: subIcon,
                    items: subItems,
                    sourceStart: subBlock.start,
                    sourceEnd: subBlock.end
                });
            }

            // 2. extract remaining widgets from sectionText
            const allSectionItems = extractWidgetsWithOffset(sectionText, sectionBlock.innerStart, sourceKey, fileScopedIds);
            for (let item of allSectionItems) {
                let belongsToSubsection = false;
                for (let sub of subsections) {
                    if (item.sourceStart >= sub.start && item.sourceEnd <= sub.end) {
                        belongsToSubsection = true;
                        break;
                    }
                }
                if (!belongsToSubsection)
                    sectionItems.push(item);
            }

            // collect all search strings for scoring
            if (title) searchStrings.push(title);
            for (let sub of sectionSubsections) {
                if (sub.title) searchStrings.push(sub.title);
            }

            // A section whose title is computed - one a Repeater builds per group, say - has no
            // title in the source to find. Indexing it as "Unknown" put a heading in the results
            // that exists on no page, under which its widgets could not be recognised either.
            if (!title)
                continue;

            // The registry's page name and aliases describe everything on the
            // page, so they belong to each of its sections. They were indexed
            // nowhere before, which left a page findable only under the words
            // printed on its own sections.
            const page = SettingsPageRegistry.pageById(pageId);
            for (let term of [page?.name ?? "", ...(page?.aliases ?? [])]) {
                if (term.length > 0 && searchStrings.indexOf(term) === -1)
                    searchStrings.push(term);
            }

            registerSection({
                pageId: pageId,
                subPage: subPage || "",
                title: title,
                icon: icon || "",
                searchStrings: searchStrings,
                items: sectionItems,
                subsections: sectionSubsections,
                sourceKey: sourceKey
            });
        }
    }

    function extractBlocks(text, type, baseOffset) {
        baseOffset = baseOffset || 0;
        let results = [];
        let i = 0;

        while (i < text.length) {
            let index = text.indexOf(type, i);
            if (index === -1) break;
            
            let prevChar = index > 0 ? text[index - 1] : ' ';
            if (/[a-zA-Z0-9_]/.test(prevChar)) {
                i = index + type.length;
                continue;
            }

            let braceStart = text.indexOf("{", index);
            if (braceStart === -1) break;
            
            let between = text.substring(index + type.length, braceStart).trim();
            if (between !== "") {
                i = index + type.length;
                continue;
            }

            let depth = 1;
            let j = braceStart + 1;
            let inString = false;
            let stringChar = "";

            while (j < text.length && depth > 0) {
                let ch = text[j];

                // Prose in comments ("the user's …") holds quotes and braces that
                // are not code. Skipping them keeps one apostrophe from turning the
                // rest of the file into a string and swallowing every section after it.
                if (!inString && ch === "/" && (text[j + 1] === "/" || text[j + 1] === "*")) {
                    if (text[j + 1] === "/") {
                        const eol = text.indexOf("\n", j);
                        j = eol === -1 ? text.length : eol;
                    } else {
                        const close = text.indexOf("*/", j + 2);
                        j = close === -1 ? text.length : close + 2;
                    }
                    continue;
                }

                if (!inString && (ch === '"' || ch === "'" || ch === "`")) {
                    inString = true;
                    stringChar = ch;
                } else if (inString && ch === stringChar) {
                    if (text[j-1] !== '\\') {
                        inString = false;
                    }
                } else if (!inString) {
                    if (ch === "{") depth++;
                    else if (ch === "}") depth--;
                }

                j++;
            }

            let block = text.substring(braceStart + 1, j - 1);
            results.push({
                inner: block,
                innerStart: baseOffset + braceStart + 1,
                start: baseOffset + index,
                end: baseOffset + j
            });

            i = j;
        }

        return results;
    }

    function getBlockSource(item) {
        if (!item || !item.sourceKey)
            return "";
        const source = root.fileSources[item.sourceKey];
        if (!source || item.sourceStart === undefined || item.sourceEnd === undefined)
            return "";
        return source.substring(item.sourceStart, item.sourceEnd);
    }

    function extractProperty(block, prop) {
        let m;
        m = block.match(new RegExp(prop + "\\s*:\\s*Translation\\.tr\\(\\s*[\"']([^\"']+)[\"']\\s*\\)"));
        if (m) return m[1];
        m = block.match(new RegExp(prop + "\\s*:\\s*\"([^\"]+)\""));
        if (m) return m[1];
        m = block.match(new RegExp(prop + "\\s*:\\s*'([^']+)'"));
        if (m) return m[1];
        return "";
    }

    // Lower case without accents: "Réseau" used to lose its "é" and split in two.
    function normalize(text) {
        let s = String(text ?? "").toLowerCase();
        if (typeof s.normalize === "function")
            s = s.normalize("NFKD").replace(/[̀-ͯ]/g, "");
        return s;
    }

    /*
     * The words of a text, each joined word also whole: "Wi-Fi" is wi, fi and
     * wifi, so "wifi" finds it. With `adjacent`, neighbouring words are also
     * joined, so "lockscreen" finds "Lock screen".
     */
    function tokenize(text, adjacent) {
        if (!text || typeof text !== "string") return [];
        let tokens = [];
        let previous = "";
        for (const chunk of root.normalize(text).split(/[^a-z0-9ı_\-.\/']+/)) {
            const parts = chunk.split(/[_\-.\/']+/).filter(p => p.length > 0);
            if (parts.length === 0)
                continue;
            const joined = parts.join("");
            for (const p of parts)
                if (p.length > 1)
                    tokens.push(p);
            if (parts.length > 1 && joined.length > 1)
                tokens.push(joined);
            if (adjacent && previous !== "")
                tokens.push(previous + joined);
            previous = joined;
        }
        return tokens;
    }

    // A query keeps joined words whole: "wi-fi" must not need a word "fi".
    function queryWords(query) {
        let words = [];
        for (const chunk of root.normalize(query).split(/[^a-z0-9ı_\-.\/']+/)) {
            const joined = chunk.split(/[_\-.\/']+/).join("");
            if (joined.length > 1)
                words.push(joined);
        }
        return words;
    }

    function textRecord(text) {
        let rec = root._textCache[text];
        if (rec !== undefined)
            return rec;
        const tokens = root.tokenize(text, true);
        let set = {};
        for (const t of tokens)
            set[t] = true;
        rec = { norm: root.normalize(text), tokens: tokens, set: set };
        root._textCache[text] = rec;
        return rec;
    }

    function vocabulary() {
        if (root._vocabulary !== null)
            return root._vocabulary;
        let seen = {};
        const add = text => {
            if (text)
                for (const t of root.textRecord(text).tokens)
                    seen[t] = true;
        };
        for (const section of root.sections) {
            add(section.title);
            section.searchStrings.forEach(add);
            for (const item of section.items) {
                add(item.text);
                add(item.extra);
            }
            for (const sub of section.subsections) {
                add(sub.title);
                for (const item of sub.items) {
                    add(item.text);
                    add(item.extra);
                }
            }
        }
        for (const l of root.landmarks) {
            add(l.text);
            add(l.key);
            add(l.subPageTitle);
        }
        for (const page of SettingsPageRegistry.pages) {
            add(Translation.tr(page.name ?? ""));
            add(page.name);
            (page.aliases ?? []).forEach(add);
        }
        root._vocabulary = Object.keys(seen);
        return root._vocabulary;
    }

    /*
     * What people type for what the pages call something else. A word answers
     * for every other word of its group, a little below the word itself.
     */
    function synonymsOf(word) {
        if (root._synonymIndex === null) {
            const groups = [
                ["sleep", "suspend", "hibernate"],
                ["dnd", "disturb"],
                ["hotkey", "hotkeys", "shortcut", "shortcuts", "keybind", "keybinds", "keybinding", "keybindings", "binds"],
                ["audio", "sound"],
                ["wifi", "wireless", "wlan"],
                ["bt", "bluetooth"],
                ["display", "displays", "monitor", "monitors"],
                ["opacity", "transparency", "transparent", "translucent"],
                ["brightness", "backlight"],
                ["rounding", "radius", "corner", "corners", "roundness"],
                ["theme", "scheme", "pack"],
                ["font", "fonts", "typeface"],
                ["animation", "animations", "motion"],
                ["mouse", "pointer", "cursor"],
                ["touchpad", "trackpad"],
                ["mic", "microphone"],
                ["language", "locale"],
                ["update", "updates", "upgrade"],
                ["osk", "keyboard"],
                ["screenshot", "screengrab", "printscreen"]
            ];
            let index = {};
            for (const group of groups)
                for (const w of group)
                    index[w] = (index[w] ?? []).concat(group.filter(other => other !== w));
            root._synonymIndex = index;
        }
        return root._synonymIndex[word] ?? [];
    }

    // Whether `a` is at most `max` edits from `b`; a swap of two letters is one.
    function editDistanceWithin(a, b, max) {
        const n = a.length;
        const m = b.length;
        if (Math.abs(n - m) > max)
            return false;
        let before = null;
        let prev = [];
        for (let j = 0; j <= m; j++)
            prev.push(j);
        for (let i = 1; i <= n; i++) {
            let cur = [i];
            let rowMin = i;
            for (let j = 1; j <= m; j++) {
                let v = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
                if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
                    v = Math.min(v, before[j - 2] + 1);
                cur.push(v);
                rowMin = Math.min(rowMin, v);
            }
            if (rowMin > max)
                return false;
            before = prev;
            prev = cur;
        }
        return prev[m] <= max;
    }

    /*
     * Every indexed word a query word answers to, with how well: itself 500,
     * a word it starts 200, a synonym 300 (250 for a word the synonym starts),
     * a typo 120 (100 for the start of a longer word still being typed).
     * Typos only count for a word that names nothing as typed, so "dock"
     * never also finds "deck".
     */
    function wordHits(word) {
        const cached = root._wordHits[word];
        if (cached !== undefined)
            return cached;
        const words = root.vocabulary();
        let hits = {};
        let direct = false;
        for (const t of words) {
            if (t === word) {
                hits[t] = 500;
                direct = true;
            } else if (t.startsWith(word)) {
                hits[t] = 200;
                direct = true;
            }
        }
        for (const s of root.synonymsOf(word)) {
            for (const t of words) {
                // Plurals only: "pack" is not "package".
                const score = t === s ? 300 : (s.length >= 4 && t.length <= s.length + 2 && t.startsWith(s) ? 250 : 0);
                if (score > (hits[t] ?? 0))
                    hits[t] = score;
            }
        }
        if (!direct && word.length >= 4) {
            const budget = word.length >= 8 ? 2 : 1;
            for (const t of words) {
                if (hits[t] !== undefined || t[0] !== word[0] || t.length < word.length - budget)
                    continue;
                if (root.editDistanceWithin(word, t, budget))
                    hits[t] = 120;
                else if (t.length > word.length && root.editDistanceWithin(word, t.substring(0, word.length), budget))
                    hits[t] = 100;
            }
        }
        root._wordHits[word] = hits;
        return hits;
    }

    // The query as scoring reads it: its normalized text and, per word, the
    // indexed words that answer it.
    function prepareQuery(query) {
        return root.queryWords(query).map(w => ({ word: w, hits: root.wordHits(w) }));
    }

    function registerSection(data) {
        const titleKey = data.title;
        const searchStringsKeys = [...data.searchStrings];

        data.title = Translation.tr(titleKey);
        data.searchStrings = searchStringsKeys.map(s => Translation.tr(s));

        root._memoResults = null;
        root._vocabulary = null;
        root._wordHits = ({});
        sections.push(data);
    }

    // `query` is normalized, `queryTokens` from prepareQuery().
    function getMatchScore(text, query, queryTokens) {
        if (!text) return 0;
        const rec = root.textRecord(text);
        let score = 0;

        // Multi-word queries are conjunctive. Previously any one token was
        // enough, so "bar popups" returned every setting containing "bar".
        for (let i = 0; i < queryTokens.length; i++) {
            const q = queryTokens[i];
            // "time zone" in a text that writes it "Timezone".
            const next = queryTokens[i + 1];
            if (next !== undefined && rec.set[q.word + next.word] === true) {
                score += 1000;
                i++;
                continue;
            }
            let tokenScore = 0;
            for (const t of rec.tokens) {
                const s = q.hits[t];
                if (s !== undefined && s > tokenScore)
                    tokenScore = s;
            }
            if (tokenScore === 0)
                return 0;
            score += tokenScore;
        }
        if (rec.norm.indexOf(query) !== -1)
            score += 1000;
        return score;
    }

    // A control's own words count for more than the headings it sits under,
    // and its very label most of all; what it shows besides (tooltip, options)
    // counts half. Context alone still finds it.
    function itemMatchScore(item, context, query, queryTokens) {
        const text = item.text;
        const own = getMatchScore(text, query, queryTokens);
        if (own > 0)
            return own + 500 + (root.textRecord(text).norm === query ? 4000 : 0);
        // Not for two-letter words: "on" is in half the tooltips.
        const described = item.extra && queryTokens.every(q => q.word.length >= 3)
            ? Math.round(getMatchScore(text + " " + item.extra, query, queryTokens) / 2) : 0;
        return Math.max(described, getMatchScore(context + " " + text, query, queryTokens));
    }

    // A section ranks by its best control. Summing them let the biggest
    // section win: twenty switches under "Dock" beat the Dock page.
    function groupScore(scores) {
        if (scores.length === 0)
            return 0;
        let best = 0;
        let total = 0;
        for (const s of scores) {
            best = Math.max(best, s);
            total += s;
        }
        return best + Math.round(Math.min((total - best) * 0.1, best * 0.5));
    }

    /*
     * A query that names a page offers the page itself, a few at most:
     * "network" opens Network even where no control on it says the word.
     */
    function matchPages(query, queryTokens) {
        let out = [];
        for (const page of SettingsPageRegistry.pages) {
            if (page.id === "search")
                continue;
            const names = [Translation.tr(page.name ?? ""), page.name ?? ""];
            let nameScore = 0;
            for (const n of names)
                nameScore = Math.max(nameScore, getMatchScore(n, query, queryTokens));
            let aliasScore = 0;
            for (const n of (page.aliases ?? []))
                aliasScore = Math.max(aliasScore, getMatchScore(n, query, queryTokens));
            if (nameScore === 0 && aliasScore === 0)
                continue;
            // Its name tops the list; an alias ("Automation" for Modes) ranks
            // below a heading that shows the word.
            const exact = names.some(n => n !== "" && root.normalize(n) === query);
            // Every word of the name, typed short or misspelled: "notif",
            // "notifcations" still mean the page.
            // A synonym is not the name: "color scheme" is not "Colors & Themes".
            const nameTokens = root.textRecord(names[0]).tokens;
            const whole = nameScore > 0 && root.queryWords(names[0]).length === queryTokens.length
                && queryTokens.every(q => nameTokens.some(t => q.hits[t] !== undefined && q.hits[t] !== 300 && q.hits[t] !== 250));
            const best = Math.max(nameScore * 2 + (whole ? 4000 : 0), Math.round(aliasScore / 2));
            out.push({
                page: true,
                pageId: page.id,
                subPage: "",
                title: Translation.tr(page.name ?? page.id),
                icon: page.icon ?? "",
                items: [],
                subsections: [],
                score: exact ? 100000 : best
            });
        }
        out.sort((a, b) => b.score - a.score);
        return out.slice(0, 3);
    }

    function getDynamicSearchResults(query) {
        if (!query || query.trim() === "") return [];
        query = root.normalize(query.trim());
        if (root._memoResults !== null && root._memoQuery === query)
            return root._memoResults;
        let queryTokens = prepareQuery(query);
        if (queryTokens.length === 0) return [];
        let results = [];

        for (let section of sections) {
            let sectionScore = 0;

            let matchedItems = [];
            let matchedSubsections = [];
            let itemScores = [];
            let subTitleBest = 0;

            let sectionTitleScore = getMatchScore(section.title, query, queryTokens);
            let searchStringScore = 0;
            for (let sStr of section.searchStrings) {
                let sScore = getMatchScore(sStr, query, queryTokens);
                if (sScore > 0) {
                    searchStringScore = Math.max(searchStringScore, sScore);
                }
            }

            // Page names and aliases are context for ranking, not identity for
            // every control on that page. Treating them as a direct match made
            // searches such as "policy" or "bar" dump unrelated widgets.
            let sectionTitleMatched = sectionTitleScore > 0;
            if (sectionTitleMatched) {
                sectionScore += sectionTitleScore;
            }

            // Context string: section.title + " " + item.text
            for (let item of section.items) {
                const itemScore = itemMatchScore(item, section.title, query, queryTokens);
                if (itemScore > 0 || sectionTitleMatched) {
                    matchedItems.push(item);
                    itemScores.push(itemScore);
                }
            }

            for (let sub of section.subsections) {
                let subTitleScore = getMatchScore(sub.title, query, queryTokens);
                let subMatchedItems = [];
                let subMatches = false;

                subTitleBest = Math.max(subTitleBest, subTitleScore);

                for (let item of sub.items) {
                    const itemScore = itemMatchScore(item, section.title + " " + sub.title, query, queryTokens);
                    if (itemScore > 0 || subTitleScore > 0 || sectionTitleMatched) {
                        subMatchedItems.push(item);
                        itemScores.push(itemScore);
                        subMatches = true;
                    }
                }

                if (subMatches) {
                    matchedSubsections.push({
                        title: sub.title,
                        icon: sub.icon,
                        items: subMatchedItems
                    });
                }
            }

            const hasRenderableItems = matchedItems.length > 0
                || matchedSubsections.some(sub => sub.items.length > 0);
            if (hasRenderableItems) {
                sectionScore += subTitleBest + root.groupScore(itemScores);
                // Context can break ties once the control proved its own
                // relevance, but it can never create a result by itself.
                if (!sectionTitleMatched && searchStringScore > 0)
                    sectionScore += Math.round(searchStringScore / 4);
                results.push({
                    pageId: section.pageId,
                    subPage: section.subPage || "",
                    title: section.title,
                    icon: section.icon,
                    fileImports: root.fileImportsBySource[section.sourceKey] || "",
                    sourceKey: section.sourceKey,
                    items: matchedItems,
                    subsections: matchedSubsections,
                    score: sectionScore
                });
            }
        }
        
        results.push(...matchLandmarks(query, queryTokens, results));
        results.push(...matchPages(query, queryTokens));
        // A query that names a page ("lock screen") wants that page first, not
        // the same words drawn on another one.
        for (let r of results) {
            if (r.page)
                continue;
            const page = SettingsPageRegistry.pageById(r.pageId);
            const names = [page?.name ?? "", ...(page?.aliases ?? [])];
            if (names.some(n => n !== "" && (root.normalize(Translation.tr(n)) === query || root.normalize(n) === query)))
                r.score += 5000;
        }
        results.sort((a, b) => b.score - a.score);
        root.assignLandmarkComponents(results);
        root._memoQuery = query;
        root._memoResults = results;
        return results;
    }
    
    function sharesToken(text, queryTokens) {
        const tokens = root.textRecord(text).tokens;
        return queryTokens.some(q => tokens.some(t => q.hits[t] !== undefined));
    }

    /*
     * Landmark hits, one group per page (or sub-page), as results that carry
     * `landmarks` instead of cloneable `items`. A heading a cloned section
     * already shows for that page is left to the clone.
     */
    function matchLandmarks(query, queryTokens, sectionResults) {
        let shown = {};
        // Headings and control labels a clone already shows on that page (or sub-page).
        for (let r of sectionResults) {
            let labels = [r.title, ...r.items.map(i => i.text)];
            for (let sub of r.subsections)
                labels.push(sub.title, ...sub.items.map(i => i.text));
            for (let label of labels)
                if (label)
                    shown[r.pageId + "|" + (r.subPage || "") + "|" + Translation.tr(label).toLowerCase()] = true;
        }

        let groups = {};
        let order = [];
        for (let l of root.landmarks) {
            const lower = l.text.toLowerCase();
            // A component that draws it still shows: it is what is on the page,
            // the clone may come from a search proxy. As a row it is dropped.
            const duplicate = !!shown[l.pageId + "|" + l.subPage + "|" + lower];
            if (duplicate && !l.block)
                continue;
            let score = getMatchScore(l.text, query, queryTokens);
            if (score === 0 && l.key !== l.text)
                score = getMatchScore(l.key, query, queryTokens);
            if (score === 0) {
                // "dock color" may name the page and a heading on it, but the
                // heading must hold one of the words itself.
                if (!sharesToken(l.text, queryTokens))
                    continue;
                const page = SettingsPageRegistry.pageById(l.pageId);
                const context = Translation.tr(page?.name ?? "") + " " + (l.subPageTitle || "");
                const contextScore = getMatchScore(context + " " + l.text, query, queryTokens);
                if (contextScore === 0)
                    continue;
                score = Math.round(contextScore / 2);
            }
            // The very words of a heading: what the user is looking at.
            if (root.textRecord(l.text).norm === query || root.textRecord(l.key).norm === query)
                score += 4000;

            const groupKey = l.pageId + "|" + l.subPage;
            if (!groups[groupKey]) {
                const page = SettingsPageRegistry.pageById(l.pageId);
                groups[groupKey] = {
                    pageId: l.pageId,
                    subPage: l.subPage,
                    title: l.subPageTitle || Translation.tr(page?.name ?? l.pageId),
                    icon: page?.icon ?? "",
                    landmarks: [],
                    items: [],
                    subsections: [],
                    score: 0
                };
                order.push(groupKey);
            }
            if (!groups[groupKey].landmarks.some(other => other.text.toLowerCase() === lower))
                groups[groupKey].landmarks.push({ text: l.text, score: score, block: l.block, duplicate: duplicate });
        }

        let out = [];
        for (let key of order) {
            let g = groups[key];
            g.landmarks.sort((a, b) => b.score - a.score);
            g.landmarks = g.landmarks.slice(0, root.maxLandmarksPerGroup);
            g.score = g.landmarks[0].score;
            out.push(g);
        }
        return out;
    }

    /*
     * The best landmark hits are shown as the component that draws them (the
     * pane, the tile), cloned like a control; a landmark inside a component
     * already shown is covered by it. The rest stay link rows.
     */
    function assignLandmarkComponents(results) {
        let budget = root.maxComponentsPerQuery;
        for (let r of results) {
            if (!r.landmarks)
                continue;
            let components = [];
            let covered = [];
            let rows = [];
            for (let l of r.landmarks) {
                if (l.block && components.indexOf(l.block) !== -1) {
                    covered.push(l);
                    continue;
                }
                if (l.block && budget > 0 && root.landmarkBlocks[l.block]) {
                    components.push(l.block);
                    covered.push(l);
                    budget--;
                    continue;
                }
                if (!l.duplicate)
                    rows.push(l);
            }
            r.components = components;
            r.coveredLandmarks = covered;
            r.landmarks = rows;
        }
        // A group whose only hits were duplicates of clones has nothing left.
        for (let i = results.length - 1; i >= 0; i--) {
            const r = results[i];
            if (r.landmarks && r.landmarks.length === 0 && r.components.length === 0)
                results.splice(i, 1);
        }
    }

    function getResultsRanked(text) {
        return getSearchResult(text);
    }
    
    function getSearchResult(query) {
        if (!query || query.trim() === "") return [];
        let dyn = getDynamicSearchResults(query);
        let flat = [];
        for (let r of dyn) {
            flat.push({ pageIndex: 0, matchedString: r.title, score: r.score });
        }
        return flat;
    }
}
