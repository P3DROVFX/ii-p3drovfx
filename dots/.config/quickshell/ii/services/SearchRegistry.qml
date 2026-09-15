pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property list<var> sections: []
    property var fileSources: ({})
    property var fileImportsBySource: ({})
    property bool settingsActive: false
    property bool indexing: false
    property bool indexed: false

    signal indexReady

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
        root.indexed = false;
        root.indexing = true;
        let configRoot = FileUtils.trimFileProtocol(Directories.config) + "/quickshell/ii/";
        let basePath = configRoot + "modules/settings/configs/";

        let files = [];
        let ids = [];
        let subPages = [];
        for (let p of SettingsPageRegistry.pages) {
            if (p.searchable === false)
                continue;
            files.push(configRoot + p.component);
            ids.push(p.id);
            subPages.push("");
            for (let sub of (p.subPages ?? [])) {
                files.push(basePath + sub);
                ids.push(p.id);
                subPages.push(sub);
            }
            // Progressive settings sections live outside the page file, but
            // are not sub-pages. Index them with an empty subPage so a search
            // result navigates to the parent page and waits for the section's
            // own lazy loader instead of trying to open the source as a page.
            for (let source of (p.searchSources ?? [])) {
                files.push(basePath + source);
                ids.push(p.id);
                subPages.push("");
            }
        }

        pageFile.start(files, ids, subPages);
        listPresetsSearchProc.running = false;
        listPresetsSearchProc.running = true;

        if (files.length === 0) {
            root.indexing = false;
            root.indexed = true;
            root.indexReady();
        }
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
        root.currentSearch = "";
        pageFile.cancel();
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
            root.indexing = false;
            root.indexed = true;
            path = "";
            files = [];
            pageIds = [];
            subPages = [];
            currentIndex = 0;
            root.indexReady();
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

    Process {
        id: listPresetsSearchProc
        command: ["bash", "-c", Directories.scriptPath + "/presets.sh list"]
        stdout: SplitParser {
            onRead: data => {
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
                items.push({
                    type: t,
                    text: textProp,
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

                if (!inString && (ch === '"' || ch === "'")) {
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

    function tokenize(text) {
        if (!text || typeof text !== "string") return [];
        return text.toLowerCase().replace(/[^a-z0-9\sğüşöçıİ_\-\.]/g, " ").split(/[\s_\-\.]+/).filter(function (t) {
            return t.length > 1;
        });
    }

    function fuzzyMatch(word, query) {
        let wi = 0; let qi = 0; let score = 0;
        word = word.toLowerCase(); query = query.toLowerCase();
        while (wi < word.length && qi < query.length) {
            if (word[wi] === query[qi]) { score += 10; qi++; }
            wi++;
        }
        if (qi === query.length) return score;
        return 0;
    }

    function registerSection(data) {
        const titleKey = data.title;
        const searchStringsKeys = [...data.searchStrings];

        data.title = Translation.tr(titleKey);
        data.searchStrings = searchStringsKeys.map(s => Translation.tr(s));

        let combined = (titleKey + " " + searchStringsKeys.join(" ") + " " + data.title + " " + data.searchStrings.join(" ")).toLowerCase();
        sections.push(data);
    }

    function getMatchScore(text, query, queryTokens) {
        if (!text) return 0;
        let score = 0;
        let lower = text.toLowerCase();
        let tokens = tokenize(lower);

        // Multi-word queries are conjunctive. Previously any one token was
        // enough, so "bar popups" returned every setting containing "bar".
        // Exact/prefix matching remains accent-agnostic and predictable.
        for (let qToken of queryTokens) {
            let tokenScore = 0;
            for (let sToken of tokens) {
                if (sToken === qToken) {
                    tokenScore = Math.max(tokenScore, 500);
                } else if (sToken.startsWith(qToken)) {
                    tokenScore = Math.max(tokenScore, 200);
                }
            }
            if (tokenScore === 0)
                return 0;
            score += tokenScore;
        }
        if (lower.indexOf(query) !== -1)
            score += 1000;
        return score;
    }

    function getDynamicSearchResults(query) {
        if (!query || query.trim() === "") return [];
        query = query.toLowerCase().trim();
        let queryTokens = tokenize(query);
        let results = [];

        for (let section of sections) {
            let sectionScore = 0;

            let matchedItems = [];
            let matchedSubsections = [];

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

            for (let item of section.items) {
                let itemScore = getMatchScore(item.text, query, queryTokens);
                let contextualItemScore = getMatchScore(
                    section.title + " " + item.text, query, queryTokens);
                if (itemScore > 0 || contextualItemScore > 0 || sectionTitleMatched) {
                    matchedItems.push(item);
                    sectionScore += Math.max(itemScore, contextualItemScore);
                }
            }

            for (let sub of section.subsections) {
                let subTitleScore = getMatchScore(sub.title, query, queryTokens);
                let subMatchedItems = [];
                let subMatches = false;

                if (subTitleScore > 0) {
                    sectionScore += subTitleScore;
                }

                for (let item of sub.items) {
                    let itemScore = getMatchScore(item.text, query, queryTokens);
                    let contextualItemScore = getMatchScore(
                        section.title + " " + sub.title + " " + item.text,
                        query, queryTokens);
                    if (itemScore > 0 || contextualItemScore > 0
                            || subTitleScore > 0 || sectionTitleMatched) {
                        subMatchedItems.push(item);
                        sectionScore += Math.max(itemScore, contextualItemScore);
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
        
        results.sort((a, b) => b.score - a.score);
        return results;
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
