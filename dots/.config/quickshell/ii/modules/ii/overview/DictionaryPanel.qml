pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Dictionary panel of the overview Search.
 *
 * Words come from FreeDictionaryAPI.com (English Wiktionary, CC BY-SA 4.0, no key,
 * 1000 requests an hour per IP), which covers definitions, pronunciations, forms,
 * examples, synonyms and antonyms for every language Wiktionary describes. English
 * lookups with no thesaurus data are topped up from Datamuse, which also suggests
 * spellings when a word is not found.
 *
 * Layout: a primary hero on the left (language, the headword set wide, its
 * pronunciation and forms, over a clipped ornament that morphs with the part of
 * speech) and the entry's page on the right (part-of-speech tabs with a sliding
 * indicator, numbered senses, then the thesaurus). Typing looks a word up after a
 * short pause; nothing is fetched for an unchanged word.
 */
Item {
    id: root

    property string searchQuery: ""
    // A word reached from a synonym/suggestion, shown instead of the query
    // until the query changes again.
    property string overrideWord: ""
    readonly property string word: root.overrideWord.length > 0 ? root.overrideWord : root.searchQuery.trim()

    // "idle" | "loading" | "found" | "missing" | "error"
    property string phase: "idle"
    property string errorText: ""
    property var entries: []
    property string sourceUrl: ""
    property string resultLanguage: ""
    property string resultWord: ""
    property var suggestions: []
    // Languages where a word missing from the chosen dictionary does exist.
    property var elsewhere: []
    property bool elsewhereChecked: false
    property bool searchedAllLanguages: false
    property int entryIndex: 0
    property int senseIndex: 0
    property bool languagesOpen: false
    property int languageCursor: 0
    property var languages: root.fallbackLanguages
    property string noticeText: ""

    property int requestSerial: 0
    property var cache: ({})

    readonly property var fallbackLanguages: [
        { code: "en", name: "English", words: 0 }, { code: "pt", name: "Portuguese", words: 0 },
        { code: "es", name: "Spanish", words: 0 }, { code: "fr", name: "French", words: 0 },
        { code: "de", name: "German", words: 0 }, { code: "it", name: "Italian", words: 0 },
        { code: "la", name: "Latin", words: 0 }, { code: "ru", name: "Russian", words: 0 },
        { code: "ja", name: "Japanese", words: 0 }, { code: "zh", name: "Chinese", words: 0 }
    ]
    readonly property string configuredLanguage: String(Config.options.search.modules.dictionary?.language ?? "auto")
    readonly property string language: {
        if (root.configuredLanguage !== "auto" && root.configuredLanguage.length > 0)
            return root.configuredLanguage;
        const ui = String(Translation.languageCode ?? "en").slice(0, 2).toLowerCase();
        return root.languages.some(item => item.code === ui) ? ui : "en";
    }
    readonly property var languageInfo: root.languages.find(item => item.code === root.language) ?? ({ code: root.language, name: root.language.toUpperCase(), words: 0 })
    readonly property var pickerLanguages: root.languages.slice(0, 48)

    readonly property var entry: root.entryIndex >= 0 && root.entryIndex < root.entries.length ? root.entries[root.entryIndex] : null
    readonly property var senses: root.entry?.senses ?? []
    readonly property var sense: root.senseIndex >= 0 && root.senseIndex < root.senses.length ? root.senses[root.senseIndex] : null
    readonly property var history: Array.from(Persistent.states.search.dictionaryHistory ?? [])

    readonly property var posShapes: ({
        "noun": "Cookie12Sided", "verb": "Sunny", "adjective": "Flower", "adverb": "Clover4Leaf",
        "pronoun": "Cookie6Sided", "preposition": "Pentagon", "conjunction": "Gem",
        "interjection": "SoftBurst", "phrase": "Arch", "proper noun": "Cookie9Sided"
    })

    readonly property string statusText: root.noticeText

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    // ── Data ───────────────────────────────────────────────────────────────

    function unique(list, limit) {
        const seen = new Set();
        const out = [];
        for (const item of list) {
            const text = String(item ?? "").trim();
            const key = text.toLocaleLowerCase();
            if (text.length === 0 || seen.has(key))
                continue;
            seen.add(key);
            out.push(text);
            if (out.length >= limit)
                break;
        }
        return out;
    }

    // Wiktionary repeats a sense's labels as a leading "(transitive, informal)";
    // they are drawn as captions, so the copy in the text goes.
    function stripLabels(definition, tags) {
        const match = /^\(([^)]{1,80})\)\s*/.exec(definition);
        if (!match || tags.length === 0)
            return definition;
        const inner = match[1].toLocaleLowerCase();
        return tags.some(tag => inner.includes(String(tag).toLocaleLowerCase())) ? definition.slice(match[0].length) : definition;
    }

    function normalizeSense(raw, depth) {
        const tags = Array.from(raw?.tags ?? []).map(String).filter(t => t.length > 0);
        const quotes = Array.from(raw?.quotes ?? []).map(q => String(q?.text ?? "")).filter(t => t.length > 0 && t.length < 260);
        const subs = depth > 0 ? [] : Array.from(raw?.subsenses ?? []).map(sub => root.normalizeSense(sub, depth + 1)).filter(sub => sub.definition.length > 0);
        return {
            definition: root.stripLabels(String(raw?.definition ?? "").trim(), tags),
            tags: tags.slice(0, 4),
            examples: root.unique(Array.from(raw?.examples ?? []).concat(quotes), 3),
            synonyms: root.unique(raw?.synonyms ?? [], 12),
            antonyms: root.unique(raw?.antonyms ?? [], 12),
            subsenses: subs.slice(0, 6)
        };
    }

    function normalizeEntry(raw, headword) {
        const senses = Array.from(raw?.senses ?? []).map(sense => root.normalizeSense(sense, 0))
            .filter(sense => sense.definition.length > 0 || sense.subsenses.length > 0);
        const ipa = Array.from(raw?.pronunciations ?? []).find(p => p?.type === "ipa") ?? null;
        const forms = Array.from(raw?.forms ?? [])
            .filter(form => {
                const tags = Array.from(form?.tags ?? []);
                return String(form?.word ?? "").length > 0 && tags.length > 0
                    && !tags.some(tag => tag === "table-tags" || tag === "inflection-template" || tag === "class" || tag === "obsolete");
            })
            .map(form => ({ word: String(form.word), tags: Array.from(form.tags).slice(0, 2).join(" ") }))
            .filter(form => form.word !== String(headword ?? ""))
            .filter((form, index, list) => list.findIndex(other => other.tags === form.tags || other.word === form.word) === index)
            .slice(0, 3);
        let synonyms = Array.from(raw?.synonyms ?? []);
        let antonyms = Array.from(raw?.antonyms ?? []);
        for (const sense of senses) {
            synonyms = synonyms.concat(sense.synonyms);
            antonyms = antonyms.concat(sense.antonyms);
        }
        return {
            language: { code: String(raw?.language?.code ?? ""), name: String(raw?.language?.name ?? "") },
            partOfSpeech: String(raw?.partOfSpeech ?? "").toLocaleLowerCase(),
            ipa: ipa ? String(ipa.text) : "",
            ipaTags: ipa ? Array.from(ipa.tags ?? []).join(", ") : "",
            forms: forms,
            senses: senses,
            synonyms: root.unique(synonyms, 24),
            antonyms: root.unique(antonyms, 16)
        };
    }

    // Several etymologies give several entries with the same part of speech;
    // their tabs read "noun¹", "noun²".
    function numberEntries(list) {
        const superscripts = ["¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"];
        const totals = {};
        const seen = {};
        for (const e of list) {
            const key = e.partOfSpeech + "|" + e.language.code;
            totals[key] = (totals[key] ?? 0) + 1;
        }
        return list.map(e => {
            const key = e.partOfSpeech + "|" + e.language.code;
            seen[key] = (seen[key] ?? 0) + 1;
            const mark = totals[key] > 1 ? (superscripts[seen[key] - 1] ?? "") : "";
            return Object.assign({}, e, { label: e.partOfSpeech + mark });
        });
    }

    function editDistance(a, b) {
        const x = a.toLocaleLowerCase();
        const y = b.toLocaleLowerCase();
        let previous = Array.from({ length: y.length + 1 }, (_, i) => i);
        for (let i = 1; i <= x.length; i++) {
            const current = [i];
            for (let j = 1; j <= y.length; j++)
                current.push(Math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] === y[j - 1] ? 0 : 1)));
            previous = current;
        }
        return previous[y.length];
    }

    function fetchJson(url, callback) {
        const request = new XMLHttpRequest();
        request.onreadystatechange = () => {
            if (request.readyState !== XMLHttpRequest.DONE)
                return;
            let body = null;
            try {
                body = JSON.parse(request.responseText);
            } catch (e) {
                body = null;
            }
            callback(request.status, body);
        };
        request.open("GET", url);
        request.send();
    }

    // Wiktionary titles are case-sensitive: "Haus" is German, "haus" is nothing.
    function spellings(text) {
        const lower = text.toLocaleLowerCase();
        const capital = lower.charAt(0).toLocaleUpperCase() + lower.slice(1);
        return root.unique([text, lower, capital], 3);
    }

    function lookUp(allLanguages) {
        const text = root.word;
        const serial = ++root.requestSerial;
        root.languagesOpen = false;
        if (text.length === 0) {
            root.phase = "idle";
            root.entries = [];
            return;
        }
        const lang = allLanguages ? "all" : root.language;
        const key = lang + "|" + text;
        if (root.cache[key]) {
            root.apply(root.cache[key], allLanguages);
            return;
        }
        root.phase = "loading";
        const candidates = root.spellings(text);
        const attempt = index => {
            const url = "https://freedictionaryapi.com/api/v1/entries/" + lang + "/" + encodeURIComponent(candidates[index]);
            root.fetchJson(url, (status, body) => {
                if (serial !== root.requestSerial)
                    return;
                if (status === 429) {
                    root.fail(Translation.tr("The dictionary is rate limited for this hour. Try again later."));
                    return;
                }
                if (status === 0) {
                    root.fail(Translation.tr("No connection to the dictionary."));
                    return;
                }
                const found = status >= 200 && status < 300 && Array.from(body?.entries ?? []).length > 0;
                if (!found && index + 1 < candidates.length) {
                    attempt(index + 1);
                    return;
                }
                if (!found && status >= 500) {
                    root.fail(Translation.tr("The dictionary answered with an error (%1).").arg(String(status)));
                    return;
                }
                const result = {
                    word: found ? String(body.word ?? candidates[index]) : text,
                    language: lang,
                    url: String(body?.source?.url ?? ""),
                    entries: found ? root.numberEntries(Array.from(body.entries).map(e => root.normalizeEntry(e, body.word)).filter(e => e.senses.length > 0)) : []
                };
                root.cache[key] = result;
                root.apply(result, allLanguages);
                if (lang === "en" && result.entries.length > 0)
                    root.topUpThesaurus(result, serial);
            });
        };
        attempt(0);
    }

    function apply(result, allLanguages) {
        root.resultWord = result.word;
        root.resultLanguage = result.language;
        root.sourceUrl = result.url;
        root.searchedAllLanguages = allLanguages === true;
        root.entries = result.entries;
        root.entryIndex = 0;
        root.senseIndex = 0;
        senseFlick.contentY = 0;
        if (result.entries.length > 0) {
            root.phase = "found";
            historyTimer.restart();
        } else {
            root.phase = "missing";
            root.suggestions = [];
            root.elsewhere = [];
            root.elsewhereChecked = allLanguages === true;
            root.fetchSuggestions(result.word, root.requestSerial);
            if (!allLanguages)
                root.fetchElsewhere(result.word, root.requestSerial);
        }
    }

    function fail(message) {
        root.phase = "error";
        root.errorText = message;
        root.entries = [];
    }

    // Wiktionary keeps thesaurus data on separate pages that the API does not
    // follow, so common English words often arrive without any. Datamuse fills
    // the gap; entries that already carry their own lists are left alone.
    function topUpThesaurus(result, serial) {
        const needsSyn = result.entries.every(e => e.synonyms.length === 0);
        const needsAnt = result.entries.every(e => e.antonyms.length === 0);
        const fill = (relation, field) => {
            root.fetchJson("https://api.datamuse.com/words?max=16&rel_" + relation + "=" + encodeURIComponent(result.word), (status, body) => {
                if (serial !== root.requestSerial || !Array.isArray(body) || body.length === 0)
                    return;
                const words = root.unique(body.map(item => item?.word), 16);
                result.entries = result.entries.map((e, i) => i === 0 ? Object.assign({}, e, { [field]: words }) : e);
                root.entries = result.entries;
            });
        };
        if (needsSyn)
            fill("syn", "synonyms");
        if (needsAnt)
            fill("ant", "antonyms");
    }

    // Spelling suggestions: Wiktionary's fuzzy title search covers every
    // language; Datamuse adds English/Spanish ones. Closest spellings first.
    function fetchSuggestions(text, serial) {
        const lower = text.toLocaleLowerCase();
        let pool = [];
        const merge = words => {
            if (serial !== root.requestSerial)
                return;
            pool = root.unique(pool.concat(words), 24);
            root.suggestions = pool
                .filter(w => w.toLocaleLowerCase() !== lower && (/\s/.test(text) || !/[\s:]/.test(w)))
                .map(w => ({ w: w, d: root.editDistance(w, text) }))
                .filter(item => item.d <= Math.max(2, Math.round(text.length / 3)))
                .sort((a, b) => a.d - b.d)
                .slice(0, 6)
                .map(item => item.w);
        };
        root.fetchJson("https://en.wiktionary.org/w/api.php?action=opensearch&format=json&namespace=0&limit=12&profile=fuzzy&search=" + encodeURIComponent(text), (status, body) => {
            if (Array.isArray(body) && Array.isArray(body[1]))
                merge(body[1].map(String));
        });
        if (root.language === "en" || root.language === "es") {
            const vocabulary = root.language === "es" ? "&v=es" : "";
            root.fetchJson("https://api.datamuse.com/sug?max=8&s=" + encodeURIComponent(text) + vocabulary, (status, body) => {
                if (Array.isArray(body))
                    merge(body.map(item => String(item?.word ?? "")));
            });
        }
    }

    function fetchElsewhere(text, serial) {
        root.fetchJson("https://freedictionaryapi.com/api/v1/entries/all/" + encodeURIComponent(text), (status, body) => {
            if (serial !== root.requestSerial)
                return;
            const entries = Array.from(body?.entries ?? []);
            root.elsewhereChecked = status >= 200 && status < 300;
            if (entries.length === 0)
                return;
            const names = root.unique(entries.map(e => String(e?.language?.name ?? "")), 3);
            root.elsewhere = names;
            root.cache["all|" + text] = {
                word: String(body.word ?? text),
                language: "all",
                url: String(body?.source?.url ?? ""),
                entries: root.numberEntries(entries.map(e => root.normalizeEntry(e, body.word)).filter(e => e.senses.length > 0))
            };
        });
    }

    function loadLanguages() {
        if (root.languages !== root.fallbackLanguages)
            return;
        root.fetchJson("https://freedictionaryapi.com/api/v1/languages", (status, body) => {
            if (!Array.isArray(body) || body.length === 0)
                return;
            root.languages = body.map(item => ({ code: String(item.code), name: String(item.name), words: Number(item.words ?? 0) }))
                .filter(item => item.code.length > 0);
        });
    }

    function recordHistory() {
        if (root.phase !== "found")
            return;
        const code = root.resultLanguage === "all" ? String(root.entry?.language.code ?? "") : root.resultLanguage;
        if (code.length === 0)
            return;
        const item = code + "|" + root.resultWord;
        const list = root.history.filter(entry => entry !== item);
        list.unshift(item);
        Persistent.states.search.dictionaryHistory = list.slice(0, 12);
    }

    function lookUpWord(text) {
        root.overrideWord = String(text ?? "").trim();
        root.lookUp(false);
    }

    function setLanguage(code) {
        Config.options.search.modules.dictionary.language = code;
        root.languagesOpen = false;
        // The binding settles on the next turn; look up with the new code then.
        Qt.callLater(() => root.lookUp(false));
    }

    // ── Search contract ────────────────────────────────────────────────────

    function focusInput(): bool { return false; }

    function navigateUp(): bool {
        if (root.languagesOpen)
            return root.moveLanguageCursor(-languageGrid.columns);
        if (root.phase !== "found" || root.senseIndex <= 0)
            return false;
        root.senseIndex--;
        return true;
    }

    function navigateDown(): bool {
        if (root.languagesOpen)
            return root.moveLanguageCursor(languageGrid.columns);
        if (root.phase !== "found" || root.senseIndex >= root.senses.length - 1)
            return false;
        root.senseIndex++;
        return true;
    }

    function navigateLeft(): bool { return root.languagesOpen ? root.moveLanguageCursor(-1) : false; }
    function navigateRight(): bool { return root.languagesOpen ? root.moveLanguageCursor(1) : false; }

    function moveLanguageCursor(step) {
        const next = Math.max(0, Math.min(root.pickerLanguages.length - 1, root.languageCursor + step));
        root.languageCursor = next;
        return true;
    }

    function selectEntry(index) {
        if (root.entries.length === 0)
            return false;
        root.entryIndex = (index + root.entries.length) % root.entries.length;
        root.senseIndex = 0;
        senseFlick.contentY = 0;
        return true;
    }

    function toggleSection(): bool { return root.entries.length > 1 && root.selectEntry(root.entryIndex + 1); }
    function sectionNext(): bool { return root.entries.length > 1 && root.selectEntry(root.entryIndex + 1); }
    function sectionPrevious(): bool { return root.entries.length > 1 && root.selectEntry(root.entryIndex - 1); }

    function editSelected(): bool {
        root.languagesOpen = !root.languagesOpen;
        if (root.languagesOpen) {
            root.loadLanguages();
            root.languageCursor = Math.max(0, root.pickerLanguages.findIndex(item => item.code === root.language));
        }
        return true;
    }

    function activateSelected(): bool {
        if (root.languagesOpen) {
            const item = root.pickerLanguages[root.languageCursor];
            if (item)
                root.setLanguage(item.code);
            return true;
        }
        if (root.phase === "missing" && root.elsewhere.length > 0 && !root.searchedAllLanguages) {
            root.lookUp(true);
            return true;
        }
        if (root.phase === "missing" && root.suggestions.length > 0) {
            root.lookUpWord(root.suggestions[0]);
            return true;
        }
        if (!root.sense)
            return false;
        const text = root.sense.definition.length > 0 ? root.sense.definition : root.sense.subsenses.map(s => s.definition).join("; ");
        Quickshell.clipboardText = root.resultWord + " — " + text;
        root.showNotice(Translation.tr("Definition copied"));
        root.recordHistory();
        return true;
    }

    function copySelected(): bool {
        if (root.phase !== "found")
            return false;
        Quickshell.clipboardText = root.resultWord;
        root.showNotice(Translation.tr("Copied “%1”").arg(root.resultWord));
        return true;
    }

    function secondaryActivateSelected(): bool {
        if (root.sourceUrl.length === 0)
            return false;
        Qt.openUrlExternally(root.sourceUrl);
        return true;
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    function escapeHtml(text) {
        return String(text ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // The headword inside an example is set in the accent colour.
    function highlight(text, headword, color) {
        const safe = root.escapeHtml(text);
        const stem = String(headword ?? "").trim();
        if (stem.length < 2)
            return safe;
        const pattern = new RegExp("(" + stem.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "\\w*)", "gi");
        const hex = "#" + [color.r, color.g, color.b].map(v => Math.round(v * 255).toString(16).padStart(2, "0")).join("");
        return safe.replace(pattern, "<b><font color=\"" + hex + "\">$1</font></b>");
    }

    function formatCount(value) {
        return Number(value ?? 0).toLocaleString(Qt.locale(), "f", 0);
    }

    onSearchQueryChanged: {
        root.overrideWord = "";
        debounce.restart();
    }
    onSenseIndexChanged: Qt.callLater(root.revealSense)

    function revealSense() {
        const item = senseRepeater.itemAt(root.senseIndex);
        if (!item)
            return;
        const top = item.y - ClockStyle.gapSmall;
        const bottom = item.y + item.height + ClockStyle.gapSmall - senseFlick.height;
        const target = root.senseIndex === 0 ? 0 : Math.max(Math.min(senseFlick.contentY, top), bottom);
        scrollGlide.to = Math.max(0, Math.min(target, senseFlick.contentHeight - senseFlick.height));
        scrollGlide.restart();
    }

    Timer {
        id: debounce
        interval: 420
        onTriggered: root.lookUp(false)
    }

    Timer {
        id: historyTimer
        interval: 2200
        onTriggered: root.recordHistory()
    }

    Timer {
        id: noticeTimer
        interval: 1800
        onTriggered: root.noticeText = ""
    }

    Component.onCompleted: {
        root.loadLanguages();
        if (root.word.length > 0)
            root.lookUp(false);
    }

    // ── Inline components ──────────────────────────────────────────────────

    // A word in a list: the word in the title face, a caption after it.
    component WordRow: RippleButton {
        id: wordRow
        property string word: ""
        property string caption: ""
        property string symbol: "north_west"
        property bool emphasized: false

        Layout.fillWidth: true
        implicitHeight: 48
        buttonRadius: ClockStyle.radiusLarge
        buttonRadiusPressed: ClockStyle.radiusNormal
        colBackground: wordRow.emphasized ? ClockStyle.colSecondaryContainer : ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0)
        colBackgroundHover: wordRow.emphasized ? ClockStyle.colSecondaryContainerHover : ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.06)
        colRipple: ColorUtils.applyAlpha(ClockStyle.colOnSurface, 0.12)

        contentItem: Item {
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gapLarge
                anchors.rightMargin: ClockStyle.gap
                spacing: ClockStyle.gap

                StyledText {
                    Layout.fillWidth: false
                    Layout.maximumWidth: wordRow.width * 0.6
                    text: wordRow.word
                    elide: Text.ElideRight
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: wordRow.emphasized ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: wordRow.caption
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.8
                    color: ClockStyle.colSubtext
                }
                MaterialSymbol {
                    text: wordRow.symbol
                    iconSize: ClockStyle.iconSmall
                    color: wordRow.emphasized ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    opacity: wordRow.hovered || wordRow.emphasized ? 1 : 0.4
                    Behavior on opacity {
                        enabled: !ClockStyle.reducedMotion
                        NumberAnimation { duration: ClockStyle.motionFast.duration; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }

    // Thesaurus word: synonyms are soft pills, antonyms squared-off tiles, so
    // the two groups read as opposites before their captions are read.
    component ThesaurusChip: RippleButton {
        id: chip
        property string word: ""
        property bool opposite: false

        implicitHeight: 34
        implicitWidth: chipLabel.implicitWidth + ClockStyle.gapLarge * 2
        buttonRadius: chip.opposite ? ClockStyle.radiusSmall * 0.6 : height / 2
        buttonRadiusPressed: chip.opposite ? height / 2 : ClockStyle.radiusSmall * 0.6
        colBackground: chip.opposite ? ClockStyle.colTertiaryContainer : ClockStyle.colSecondaryContainer
        colBackgroundHover: chip.opposite ? ClockStyle.colTertiaryContainerHover : ClockStyle.colSecondaryContainerHover
        colRipple: chip.opposite ? ClockStyle.colTertiaryContainerActive : ClockStyle.colSecondaryContainerActive

        contentItem: Item {
            StyledText {
                id: chipLabel
                anchors.centerIn: parent
                text: chip.word
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
                font.italic: chip.opposite
                color: chip.opposite ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnSecondaryContainer
            }
        }
    }

    component Caption: StyledText {
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1.2
        color: ClockStyle.colOnSurfaceVariant
    }

    // ── Layout ─────────────────────────────────────────────────────────────

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Dictionary")
        icon: "dictionary"
        accent: true
        statusText: root.statusText
        primaryHint: root.languagesOpen
            ? ({ label: Translation.tr("Choose"), actionId: "activate", keys: ["↵"] })
            : (root.phase === "found" ? ({ label: Translation.tr("Copy definition"), actionId: "activate", keys: ["↵"] }) : ({}))
        hints: [
            { label: Translation.tr("Copy word"), actionId: "copy", keys: ["Ctrl", "C"] },
            { label: Translation.tr("Part of speech"), actionId: "section", keys: ["Tab"] },
            { label: Translation.tr("Language"), actionId: "edit", keys: ["Ctrl", "E"] },
            { label: Translation.tr("Wiktionary"), actionId: "secondary", keys: ["Ctrl", "↵"] }
        ]

        RowLayout {
            anchors.fill: parent
            spacing: ClockStyle.paneGap

            // ── Hero ───────────────────────────────────────────────────────
            Rectangle {
                id: hero
                readonly property color colContent: ClockStyle.colOnPrimaryContainer
                readonly property bool showsWord: root.phase !== "idle"
                readonly property string shapeName: root.phase === "found"
                    ? (root.posShapes[root.entry?.partOfSpeech ?? ""] ?? "Cookie7Sided")
                    : (root.phase === "missing" || root.phase === "error" ? "Ghostish" : "Clover8Leaf")

                Layout.preferredWidth: Math.round(Math.min(330, Math.max(260, root.width * 0.36)))
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPrimaryContainer

                // The pane's one ornament: a shape far larger than the pane,
                // parked past its bottom-right corner and cut by the pane's own
                // rounded mask. It morphs with the part of speech.
                Item {
                    id: heroOrnament
                    anchors.fill: parent
                    visible: false

                    MaterialShape {
                        width: Math.round(hero.height * 1.05)
                        height: width
                        x: hero.width - width * 0.52
                        y: hero.height - height * 0.6
                        shapeString: hero.shapeName
                        color: hero.colContent
                    }
                }
                Rectangle {
                    id: heroMask
                    anchors.fill: parent
                    radius: hero.radius
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: heroOrnament
                    maskEnabled: true
                    maskSource: heroMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                    opacity: 0.09
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: ClockStyle.cardPadding
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        // Language: a tinted pill on the hero; opens the picker.
                        RippleButton {
                            id: languageButton
                            implicitHeight: 36
                            implicitWidth: languageRow.implicitWidth + ClockStyle.gap * 2
                            buttonRadius: height / 2
                            buttonRadiusPressed: ClockStyle.radiusSmall
                            toggled: root.languagesOpen
                            colBackground: ColorUtils.applyAlpha(hero.colContent, 0.08)
                            colBackgroundHover: ColorUtils.applyAlpha(hero.colContent, 0.16)
                            colBackgroundToggled: ClockStyle.colPrimary
                            colBackgroundToggledHover: ClockStyle.colPrimaryHover
                            colRipple: ColorUtils.applyAlpha(hero.colContent, 0.24)
                            colRippleToggled: ClockStyle.colPrimaryActive
                            onClicked: root.editSelected()

                            contentItem: Item {
                                RowLayout {
                                    id: languageRow
                                    anchors.centerIn: parent
                                    spacing: ClockStyle.gapSmall
                                    StyledText {
                                        text: (root.searchedAllLanguages && root.phase === "found" ? (root.entry?.language.code ?? root.language) : root.language).toUpperCase()
                                        font.family: ClockStyle.fontMain
                                        font.variableAxes: ClockStyle.axesDigitsBold
                                        font.pixelSize: ClockStyle.textLarge
                                        color: languageButton.toggled ? ClockStyle.colOnPrimary : hero.colContent
                                    }
                                    StyledText {
                                        Layout.maximumWidth: 120
                                        text: root.searchedAllLanguages && root.phase === "found" ? (root.entry?.language.name ?? "") : root.languageInfo.name
                                        elide: Text.ElideRight
                                        font.pixelSize: ClockStyle.textNormal
                                        font.weight: Font.DemiBold
                                        color: languageButton.toggled ? ClockStyle.colOnPrimary : hero.colContent
                                    }
                                    MaterialSymbol {
                                        text: "expand_more"
                                        iconSize: ClockStyle.iconSmall
                                        rotation: root.languagesOpen ? 180 : 0
                                        color: languageButton.toggled ? ClockStyle.colOnPrimary : hero.colContent
                                        Behavior on rotation {
                                            enabled: !ClockStyle.reducedMotion
                                            NumberAnimation { duration: ClockStyle.motionDefault.duration; easing.type: Easing.OutBack }
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ClockCardAction {
                            visible: root.overrideWord.length > 0
                            symbol: "undo"
                            tip: Translation.tr("Back to “%1”").arg(root.searchQuery.trim())
                            colContent: hero.colContent
                            onClicked: {
                                root.overrideWord = "";
                                root.lookUp(false);
                            }
                        }
                    }

                    Item { Layout.fillHeight: true; Layout.minimumHeight: ClockStyle.gapSmall }

                    // Idle: the language itself is the hero, with its size.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: !hero.showsWord
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.languageInfo.words > 0 ? root.formatCount(root.languageInfo.words) : "Aa"
                            font.family: ClockStyle.fontMain
                            font.variableAxes: ClockStyle.axesDigitsBold
                            font.pixelSize: 64
                            elide: Text.ElideRight
                            color: hero.colContent
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.languageInfo.words > 0
                                ? Translation.tr("%1 words to look up").arg(root.languageInfo.name)
                                : Translation.tr("Type a word to look it up")
                            wrapMode: Text.WordWrap
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            color: hero.colContent
                            opacity: 0.8
                        }
                    }

                    // The headword, set wide and heavy, fitted to the pane.
                    StyledText {
                        id: headword
                        Layout.fillWidth: true
                        Layout.preferredHeight: 128
                        visible: hero.showsWord
                        text: root.phase === "found" ? root.resultWord : root.word
                        verticalAlignment: Text.AlignBottom
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        fontSizeMode: Text.Fit
                        minimumPixelSize: 22
                        font.pixelSize: 60
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ({ "wght": 720, "wdth": 120, "ROND": 100 })
                        lineHeight: 0.92
                        color: hero.colContent
                        opacity: root.phase === "missing" || root.phase === "error" ? 0.55 : 1
                        Behavior on opacity {
                            enabled: !ClockStyle.reducedMotion
                            NumberAnimation { duration: ClockStyle.motionFast.duration }
                        }
                    }

                    // Pronunciation in a lighter, narrow cut, so the two lines contrast.
                    StyledText {
                        Layout.fillWidth: true
                        visible: hero.showsWord && text.length > 0
                        text: root.phase === "found" && (root.entry?.ipa ?? "").length > 0
                            ? root.entry.ipa + ((root.entry.ipaTags ?? "").length > 0 ? "  ·  " + root.entry.ipaTags : "")
                            : (root.phase === "loading" ? Translation.tr("Looking up…") : "")
                        elide: Text.ElideRight
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ({ "wght": 380, "wdth": 80, "ROND": 0 })
                        font.pixelSize: ClockStyle.textLarge
                        color: hero.colContent
                        opacity: 0.85
                    }

                    // Forms: "plural casas · comparative happier".
                    Flow {
                        Layout.fillWidth: true
                        visible: hero.showsWord && root.phase === "found" && (root.entry?.forms ?? []).length > 0
                        spacing: ClockStyle.gap
                        Repeater {
                            model: root.phase === "found" ? (root.entry?.forms ?? []) : []
                            delegate: Row {
                                id: formItem
                                required property var modelData
                                spacing: 4
                                StyledText {
                                    anchors.baseline: formWord.baseline
                                    text: formItem.modelData.tags
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    color: hero.colContent
                                    opacity: 0.65
                                }
                                StyledText {
                                    id: formWord
                                    text: formItem.modelData.word
                                    font.pixelSize: ClockStyle.textNormal
                                    font.weight: Font.DemiBold
                                    color: hero.colContent
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true; Layout.minimumHeight: ClockStyle.gapSmall }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapTiny

                        StyledText {
                            Layout.fillWidth: true
                            text: root.phase === "found"
                                ? (root.senses.length === 1 ? Translation.tr("1 sense") : Translation.tr("%1 senses").arg(String(root.senses.length)))
                                : (root.phase === "idle" ? Translation.tr("Wiktionary, CC BY-SA") : "")
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Bold
                            color: hero.colContent
                            opacity: 0.75
                        }

                        MaterialLoadingIndicator {
                            visible: root.phase === "loading"
                            loading: visible
                            implicitSize: 40
                            color: ClockStyle.colPrimary
                            shapeColor: ClockStyle.colOnPrimary
                        }

                        ClockCardAction {
                            visible: root.phase === "found"
                            symbol: "content_copy"
                            tip: Translation.tr("Copy word")
                            colContent: hero.colContent
                            onClicked: root.copySelected()
                        }
                        ClockCardAction {
                            visible: root.phase === "found" && root.sourceUrl.length > 0
                            symbol: "open_in_new"
                            tip: Translation.tr("Open in Wiktionary")
                            colContent: hero.colContent
                            onClicked: root.secondaryActivateSelected()
                        }
                    }
                }
            }

            // ── Page ───────────────────────────────────────────────────────
            Rectangle {
                id: page
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: ClockStyle.radiusCard
                color: ClockStyle.colSurface
                clip: true

                readonly property string view: root.languagesOpen ? "languages" : root.phase

                // Entry page ------------------------------------------------
                ColumnLayout {
                    id: entryPage
                    anchors.fill: parent
                    anchors.margins: ClockStyle.panePadding
                    spacing: ClockStyle.gapSmall
                    opacity: page.view === "found" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { y: (1 - entryPage.opacity) * ClockStyle.enterOffset }
                    Behavior on opacity {
                        enabled: !ClockStyle.reducedMotion
                        NumberAnimation { duration: ClockStyle.motionEnter.duration; easing.type: Easing.OutCubic }
                    }

                    // Part-of-speech tabs: one filled indicator slides between them.
                    Item {
                        id: tabStrip
                        Layout.fillWidth: true
                        implicitHeight: 40
                        visible: root.entries.length > 0

                        readonly property Item current: tabRepeater.count > 0 ? tabRepeater.itemAt(Math.min(root.entryIndex, tabRepeater.count - 1)) : null

                        Rectangle {
                            id: tabIndicator
                            x: (tabStrip.current?.x ?? 0) + tabFlick.x - tabFlick.contentX
                            width: tabStrip.current?.width ?? 0
                            height: tabStrip.height
                            radius: height / 2
                            color: ClockStyle.colPrimary
                            Behavior on x {
                                enabled: !ClockStyle.reducedMotion
                                NumberAnimation { duration: ClockStyle.motionSpatial.duration; easing.type: ClockStyle.motionSpatial.type; easing.bezierCurve: ClockStyle.motionSpatial.bezierCurve }
                            }
                            Behavior on width {
                                enabled: !ClockStyle.reducedMotion
                                NumberAnimation { duration: ClockStyle.motionSpatial.duration; easing.type: ClockStyle.motionSpatial.type; easing.bezierCurve: ClockStyle.motionSpatial.bezierCurve }
                            }
                        }

                        Flickable {
                            id: tabFlick
                            anchors.fill: parent
                            contentWidth: tabRow.implicitWidth
                            flickableDirection: Flickable.HorizontalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentWidth > width
                            clip: true

                            Row {
                                id: tabRow
                                height: parent.height
                                Repeater {
                                    id: tabRepeater
                                    model: root.entries
                                    delegate: MouseArea {
                                        id: tab
                                        required property var modelData
                                        required property int index
                                        readonly property bool current: index === root.entryIndex
                                        width: tabLabel.implicitWidth + ClockStyle.gapLarge * 2
                                        height: tabRow.height
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: root.selectEntry(tab.index)

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: ColorUtils.applyAlpha(ClockStyle.colOnSurface, tab.containsMouse && !tab.current ? 0.06 : 0)
                                        }
                                        StyledText {
                                            id: tabLabel
                                            anchors.centerIn: parent
                                            text: root.searchedAllLanguages
                                                ? tab.modelData.label + " · " + tab.modelData.language.name
                                                : tab.modelData.label
                                            font.pixelSize: ClockStyle.textNormal
                                            font.weight: Font.Bold
                                            color: tab.current ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant
                                            Behavior on color {
                                                enabled: !ClockStyle.reducedMotion
                                                ColorAnimation { duration: ClockStyle.motionFast.duration }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledFlickable {
                        id: senseFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: senseColumn.implicitHeight
                        clip: true

                        NumberAnimation {
                            id: scrollGlide
                            target: senseFlick
                            property: "contentY"
                            duration: ClockStyle.reducedMotion ? 0 : ClockStyle.motionDefault.duration
                            easing.type: Easing.OutCubic
                        }

                        ColumnLayout {
                            id: senseColumn
                            width: senseFlick.width
                            spacing: 2

                            Repeater {
                                id: senseRepeater
                                model: root.senses
                                delegate: Rectangle {
                                    id: senseItem
                                    required property var modelData
                                    required property int index
                                    readonly property bool selected: index === root.senseIndex
                                    property real boldness: selected ? 1 : 0

                                    Layout.fillWidth: true
                                    implicitHeight: senseLayout.implicitHeight + ClockStyle.gap * 2
                                    radius: ClockStyle.radiusLarge
                                    color: senseItem.selected ? ClockStyle.colSurfaceHigh : ColorUtils.applyAlpha(ClockStyle.colSurfaceHigh, 0)
                                    Behavior on color {
                                        enabled: !ClockStyle.reducedMotion
                                        ColorAnimation { duration: ClockStyle.motionFast.duration }
                                    }
                                    Behavior on boldness {
                                        enabled: !ClockStyle.reducedMotion
                                        NumberAnimation { duration: ClockStyle.motionDefault.duration; easing.type: Easing.OutCubic }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (senseItem.selected)
                                                root.activateSelected();
                                            else
                                                root.senseIndex = senseItem.index;
                                        }
                                    }

                                    RowLayout {
                                        id: senseLayout
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            top: parent.top
                                            margins: ClockStyle.gap
                                        }
                                        spacing: ClockStyle.gap

                                        // The sense number: tall condensed digits whose weight
                                        // rises when the sense is selected (quantised steps).
                                        StyledText {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.preferredWidth: 34
                                            horizontalAlignment: Text.AlignRight
                                            text: String(senseItem.index + 1).padStart(2, "0")
                                            font.family: ClockStyle.fontMain
                                            font.variableAxes: ({
                                                "wght": 400 + Math.round(senseItem.boldness * 4) * 100,
                                                "wdth": 30,
                                                "ROND": 100
                                            })
                                            font.pixelSize: 30
                                            lineHeight: 0.8
                                            color: senseItem.selected ? ClockStyle.colPrimary : ClockStyle.colOnSurfaceVariant
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: ClockStyle.gapTiny + 2

                                            StyledText {
                                                Layout.fillWidth: true
                                                visible: senseItem.modelData.tags.length > 0
                                                text: senseItem.modelData.tags.join(" · ")
                                                elide: Text.ElideRight
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.Bold
                                                font.capitalization: Font.AllUppercase
                                                font.letterSpacing: 1
                                                color: ClockStyle.colTertiary
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                visible: senseItem.modelData.definition.length > 0
                                                text: senseItem.modelData.definition
                                                wrapMode: Text.Wrap
                                                maximumLineCount: senseItem.selected ? 8 : 3
                                                elide: Text.ElideRight
                                                font.pixelSize: ClockStyle.textLarge - 1
                                                color: ClockStyle.colOnSurface
                                            }

                                            Repeater {
                                                model: senseItem.modelData.subsenses
                                                delegate: RowLayout {
                                                    id: subItem
                                                    required property var modelData
                                                    required property int index
                                                    Layout.fillWidth: true
                                                    spacing: ClockStyle.gapSmall
                                                    StyledText {
                                                        Layout.alignment: Qt.AlignTop
                                                        text: String.fromCharCode(97 + subItem.index)
                                                        font.family: ClockStyle.fontMain
                                                        font.variableAxes: ClockStyle.axesDigitsBold
                                                        font.pixelSize: ClockStyle.textNormal
                                                        color: ClockStyle.colPrimary
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: subItem.modelData.definition
                                                        wrapMode: Text.Wrap
                                                        maximumLineCount: senseItem.selected ? 4 : 2
                                                        elide: Text.ElideRight
                                                        font.pixelSize: ClockStyle.textNormal
                                                        color: ClockStyle.colOnSurfaceVariant
                                                    }
                                                }
                                            }

                                            // Examples: italic, quote mark in the primary voice,
                                            // the headword picked out. One when idle, all when selected.
                                            Repeater {
                                                model: senseItem.selected ? senseItem.modelData.examples : senseItem.modelData.examples.slice(0, 1)
                                                delegate: RowLayout {
                                                    id: exampleItem
                                                    required property string modelData
                                                    Layout.fillWidth: true
                                                    Layout.topMargin: 2
                                                    spacing: ClockStyle.gapSmall
                                                    MaterialSymbol {
                                                        Layout.alignment: Qt.AlignTop
                                                        text: "format_quote"
                                                        fill: 1
                                                        iconSize: ClockStyle.iconSmall
                                                        color: ClockStyle.colPrimary
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        textFormat: Text.StyledText
                                                        text: root.highlight(exampleItem.modelData, root.resultWord, ClockStyle.colPrimary)
                                                        wrapMode: Text.Wrap
                                                        maximumLineCount: senseItem.selected ? 4 : 2
                                                        elide: Text.ElideRight
                                                        font.pixelSize: ClockStyle.textNormal
                                                        font.italic: true
                                                        color: ClockStyle.colOnSurfaceVariant
                                                    }
                                                }
                                            }

                                            // The selected sense's own synonyms, inline.
                                            Flow {
                                                Layout.fillWidth: true
                                                Layout.topMargin: ClockStyle.gapTiny
                                                visible: senseItem.selected && root.senses.length > 1 && senseItem.modelData.synonyms.length > 0
                                                spacing: ClockStyle.gapTiny + 2
                                                Repeater {
                                                    model: senseItem.selected ? senseItem.modelData.synonyms.slice(0, 6) : []
                                                    delegate: ThesaurusChip {
                                                        required property string modelData
                                                        word: modelData
                                                        onClicked: root.lookUpWord(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Thesaurus for the whole entry.
                            Repeater {
                                model: root.entry ? [
                                    { title: Translation.tr("Synonyms"), words: root.entry.synonyms, opposite: false },
                                    { title: Translation.tr("Antonyms"), words: root.entry.antonyms, opposite: true }
                                ].filter(group => group.words.length > 0) : []
                                delegate: ColumnLayout {
                                    id: group
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.topMargin: ClockStyle.gapLarge
                                    Layout.leftMargin: ClockStyle.gap
                                    Layout.rightMargin: ClockStyle.gap
                                    spacing: ClockStyle.gapSmall

                                    Caption {
                                        text: group.modelData.title + "  " + group.modelData.words.length
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: ClockStyle.gapTiny + 2
                                        Repeater {
                                            model: group.modelData.words
                                            delegate: ThesaurusChip {
                                                required property string modelData
                                                word: modelData
                                                opposite: group.modelData.opposite
                                                onClicked: root.lookUpWord(modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            // Attribution (CC BY-SA requires it).
                            StyledText {
                                Layout.fillWidth: true
                                Layout.topMargin: ClockStyle.gapLarge
                                Layout.bottomMargin: ClockStyle.gapSmall
                                Layout.leftMargin: ClockStyle.gap
                                text: Translation.tr("From Wiktionary (CC BY-SA 4.0) via FreeDictionaryAPI.com")
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: ClockStyle.colSubtext
                            }
                        }
                    }
                }

                // Idle / missing / error page ----------------------------------
                ColumnLayout {
                    id: wordsPage
                    anchors.fill: parent
                    anchors.margins: ClockStyle.pagePadding
                    spacing: ClockStyle.gapSmall
                    readonly property bool shown: page.view === "idle" || page.view === "missing" || page.view === "error"
                    opacity: shown ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { y: (1 - wordsPage.opacity) * ClockStyle.enterOffset }
                    Behavior on opacity {
                        enabled: !ClockStyle.reducedMotion
                        NumberAnimation { duration: ClockStyle.motionEnter.duration; easing.type: Easing.OutCubic }
                    }

                    readonly property var recentRows: root.history.map(item => {
                        const split = String(item).indexOf("|");
                        const code = String(item).slice(0, split);
                        const known = root.languages.find(language => language.code === code);
                        return { word: String(item).slice(split + 1), caption: known ? known.name : code, lang: code };
                    })
                    // A miss with nothing close shows the way back instead of a blank page.
                    readonly property bool missFallsBack: page.view === "missing" && root.elsewhere.length === 0 && root.suggestions.length === 0
                    readonly property var rows: {
                        if (wordsPage.missFallsBack)
                            return wordsPage.recentRows.slice(0, 4);
                        if (page.view === "missing")
                            return (root.elsewhere.length > 0 ? [{ word: root.resultWord, caption: root.elsewhere.join(" · "), lang: "", all: true }] : [])
                                .concat(root.suggestions.map(w => ({ word: w, caption: "", lang: "" })));
                        if (page.view === "idle") {
                            const recent = wordsPage.recentRows;
                            return recent.length > 0 ? recent : [
                                { word: "serendipity", caption: "English", lang: "en" },
                                { word: "saudade", caption: "Português", lang: "pt" },
                                { word: "Fernweh", caption: "Deutsch", lang: "de" },
                                { word: "sobremesa", caption: "Español", lang: "es" }
                            ];
                        }
                        return [];
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: ClockStyle.gapSmall
                        text: page.view === "missing"
                            ? Translation.tr("No entry for “%1”").arg(root.resultWord)
                            : (page.view === "error" ? Translation.tr("Couldn’t reach the dictionary") : (root.history.length > 0 ? Translation.tr("Recent words") : Translation.tr("Try a word")))
                        elide: Text.ElideRight
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textTitle
                        color: ClockStyle.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: ClockStyle.gapSmall
                        Layout.bottomMargin: ClockStyle.gapSmall
                        text: page.view === "missing"
                            ? (root.searchedAllLanguages || (root.elsewhereChecked && root.elsewhere.length === 0)
                                ? Translation.tr("Wiktionary has no entry for this spelling in any language.")
                                : Translation.tr("Not in the %1 dictionary. Check the spelling or search every language.").arg(root.languageInfo.name))
                            : (page.view === "error" ? root.errorText : Translation.tr("Synonyms, examples and forms from Wiktionary, in %1.").arg(root.languageInfo.name))
                        wrapMode: Text.Wrap
                        font.pixelSize: ClockStyle.textNormal
                        color: ClockStyle.colSubtext
                    }

                    Caption {
                        Layout.leftMargin: ClockStyle.gapSmall
                        visible: page.view === "missing" && wordsPage.rows.length > 0
                        text: wordsPage.missFallsBack ? Translation.tr("Recent words")
                            : (root.elsewhere.length > 0 ? Translation.tr("Found in other languages") : Translation.tr("Did you mean"))
                    }

                    Repeater {
                        model: wordsPage.rows.slice(0, page.view === "missing" ? 4 : 6)
                        delegate: WordRow {
                            required property var modelData
                            required property int index
                            word: modelData.word
                            caption: modelData.caption
                            emphasized: page.view === "missing" && !wordsPage.missFallsBack && index === 0
                            symbol: modelData.all === true ? "translate" : (page.view === "missing" && !wordsPage.missFallsBack ? "spellcheck" : "north_west")
                            onClicked: {
                                if (modelData.all === true) {
                                    root.lookUp(true);
                                    return;
                                }
                                if (modelData.lang.length > 0 && modelData.lang !== "all" && modelData.lang !== root.language)
                                    Config.options.search.modules.dictionary.language = modelData.lang;
                                Qt.callLater(() => root.lookUpWord(modelData.word));
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall
                        visible: page.view !== "idle"

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            visible: page.view === "missing" && !root.searchedAllLanguages && !root.elsewhereChecked
                            implicitHeight: 44
                            implicitWidth: allRow.implicitWidth + ClockStyle.gapHuge * 2
                            buttonRadius: height / 2
                            buttonRadiusPressed: ClockStyle.radiusSmall
                            colBackground: ClockStyle.colPrimary
                            colBackgroundHover: ClockStyle.colPrimaryHover
                            colRipple: ClockStyle.colPrimaryActive
                            onClicked: root.lookUp(true)
                            contentItem: Item {
                                RowLayout {
                                    id: allRow
                                    anchors.centerIn: parent
                                    spacing: ClockStyle.gapSmall
                                    MaterialSymbol { text: "language"; iconSize: ClockStyle.iconSmall; color: ClockStyle.colOnPrimary }
                                    StyledText {
                                        text: Translation.tr("Search every language")
                                        font.pixelSize: ClockStyle.textNormal
                                        font.weight: Font.Bold
                                        color: ClockStyle.colOnPrimary
                                    }
                                }
                            }
                        }

                        RippleButton {
                            visible: page.view === "error"
                            implicitHeight: 44
                            implicitWidth: retryRow.implicitWidth + ClockStyle.gapHuge * 2
                            buttonRadius: height / 2
                            buttonRadiusPressed: ClockStyle.radiusSmall
                            colBackground: ClockStyle.colErrorContainer
                            colBackgroundHover: ClockStyle.colErrorContainerHover
                            colRipple: ColorUtils.applyAlpha(ClockStyle.colOnErrorContainer, 0.2)
                            onClicked: {
                                root.cache = ({});
                                root.lookUp(root.searchedAllLanguages);
                            }
                            contentItem: Item {
                                RowLayout {
                                    id: retryRow
                                    anchors.centerIn: parent
                                    spacing: ClockStyle.gapSmall
                                    MaterialSymbol { text: "refresh"; iconSize: ClockStyle.iconSmall; color: ClockStyle.colOnErrorContainer }
                                    StyledText {
                                        text: Translation.tr("Try again")
                                        font.pixelSize: ClockStyle.textNormal
                                        font.weight: Font.Bold
                                        color: ClockStyle.colOnErrorContainer
                                    }
                                }
                            }
                        }
                    }
                }

                // Loading page: the senses' rhythm as placeholders ----------------
                ColumnLayout {
                    id: loadingPage
                    anchors.fill: parent
                    anchors.margins: ClockStyle.pagePadding
                    spacing: ClockStyle.gap
                    opacity: page.view === "loading" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity {
                        enabled: !ClockStyle.reducedMotion
                        NumberAnimation { duration: ClockStyle.motionFast.duration }
                    }
                    Repeater {
                        model: [0.42, 0.92, 0.74, 0.88, 0.6]
                        delegate: Rectangle {
                            required property real modelData
                            required property int index
                            Layout.preferredWidth: Math.round(loadingPage.width * modelData)
                            implicitHeight: index === 0 ? 36 : 18
                            radius: height / 2
                            color: index === 0 ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // Language picker -------------------------------------------
                ColumnLayout {
                    id: languagePage
                    anchors.fill: parent
                    anchors.margins: ClockStyle.panePadding
                    spacing: ClockStyle.gapSmall
                    opacity: page.view === "languages" ? 1 : 0
                    visible: opacity > 0
                    transform: Translate { y: (1 - languagePage.opacity) * ClockStyle.enterOffset }
                    Behavior on opacity {
                        enabled: !ClockStyle.reducedMotion
                        NumberAnimation { duration: ClockStyle.motionEnter.duration; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: ClockStyle.gapSmall
                        Layout.topMargin: ClockStyle.gapTiny
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Dictionary language")
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            font.pixelSize: ClockStyle.textTitle
                            color: ClockStyle.colOnSurface
                        }
                        RippleButton {
                            implicitHeight: 34
                            implicitWidth: autoLabel.implicitWidth + ClockStyle.gapLarge * 2
                            buttonRadius: height / 2
                            toggled: root.configuredLanguage === "auto"
                            colBackground: ClockStyle.colSurfaceHigh
                            colBackgroundHover: ClockStyle.colSurfaceHover
                            colBackgroundToggled: ClockStyle.colSecondaryContainer
                            colBackgroundToggledHover: ClockStyle.colSecondaryContainerHover
                            onClicked: root.setLanguage("auto")
                            contentItem: Item {
                                StyledText {
                                    id: autoLabel
                                    anchors.centerIn: parent
                                    text: Translation.tr("Match the shell")
                                    font.pixelSize: ClockStyle.textSmall
                                    font.weight: Font.Bold
                                    color: root.configuredLanguage === "auto" ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                                }
                            }
                        }
                    }

                    StyledFlickable {
                        id: languageFlick
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentHeight: languageGrid.implicitHeight
                        clip: true

                        Grid {
                            id: languageGrid
                            readonly property real tileWidth: Math.floor((languageFlick.width - (columns - 1) * spacing) / columns)
                            width: languageFlick.width
                            columns: Math.max(2, Math.floor((languageFlick.width + spacing) / (128 + spacing)))
                            spacing: ClockStyle.gapTiny + 2

                            Repeater {
                                model: root.pickerLanguages
                                delegate: RippleButton {
                                    id: languageTile
                                    required property var modelData
                                    required property int index
                                    readonly property bool chosen: modelData.code === root.language
                                    readonly property bool cursor: index === root.languageCursor
                                    width: languageGrid.tileWidth
                                    implicitHeight: 64
                                    // Chosen language: the tile closes into a squarer shape.
                                    buttonRadius: chosen ? ClockStyle.radiusSmall : ClockStyle.radiusLarge
                                    toggled: chosen
                                    colBackground: languageTile.cursor ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh
                                    colBackgroundHover: ClockStyle.colSurfaceHover
                                    colBackgroundToggled: ClockStyle.colPrimary
                                    colBackgroundToggledHover: ClockStyle.colPrimaryHover
                                    onClicked: root.setLanguage(modelData.code)
                                    onCursorChanged: if (cursor) {
                                        const top = languageTile.y;
                                        const bottom = languageTile.y + languageTile.height - languageFlick.height;
                                        languageFlick.contentY = Math.max(0, Math.max(Math.min(languageFlick.contentY, top), bottom));
                                    }

                                    contentItem: Item {
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: ClockStyle.gap
                                            anchors.rightMargin: ClockStyle.gapSmall
                                            spacing: -2
                                            Item { Layout.fillHeight: true }
                                            StyledText {
                                                text: languageTile.modelData.code.toUpperCase()
                                                font.family: ClockStyle.fontMain
                                                font.variableAxes: ClockStyle.axesDigitsBold
                                                font.pixelSize: 26
                                                color: languageTile.chosen ? ClockStyle.colOnPrimary : ClockStyle.colPrimary
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: languageTile.modelData.name
                                                elide: Text.ElideRight
                                                font.pixelSize: ClockStyle.textSmall
                                                font.weight: Font.DemiBold
                                                color: languageTile.chosen ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant
                                            }
                                            Item { Layout.fillHeight: true }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
