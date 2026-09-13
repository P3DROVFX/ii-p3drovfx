.pragma library

/**
 * Pure JavaScript inverted search index for the notes store.
 *
 * Features:
 * - Accents / diacritics normalization (e.g. "reuniao" matches "reunião").
 * - Inverted index with field weighting (title: 10x, tags: 5x, headings: 4x, body: 1x).
 * - Advanced search operators (tag:, caderno:, tem:imagem, tem:tinta, criada:>...).
 * - Snippet extraction and match highlighting.
 * - Wikilink extraction and backlink discovery.
 *
 * Compatible with QML V4 engine and Node test runner.
 * No lookbehinds, all exports declared with `var` or `function`.
 */

// ── Normalization & Tokenization ────────────────────────────────────────────

function removeDiacritics(str) {
    if (!str)
        return "";
    return String(str)
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "");
}

function normalizeText(str) {
    return removeDiacritics(str).toLowerCase();
}

function tokenize(str) {
    if (!str)
        return [];
    var normalized = normalizeText(str);
    // Split on any character that is not alphanumeric (unicode friendly)
    var tokens = normalized.split(/[^a-z0-9]+/);
    var result = [];
    for (var i = 0; i < tokens.length; i++) {
        var token = tokens[i].trim();
        if (token.length > 0)
            result.push(token);
    }
    return result;
}

// ── Wikilinks & Backlinks ───────────────────────────────────────────────────

/**
 * Extracts target titles/names from wikilinks in text: `[[Title]]` or `[[Title|Label]]`.
 */
function extractWikilinks(text) {
    if (!text)
        return [];
    var str = String(text);
    var regex = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g;
    var matches = [];
    var match;
    while ((match = regex.exec(str)) !== null) {
        var target = match[1].trim();
        if (target.length > 0 && matches.indexOf(target) === -1)
            matches.push(target);
    }
    return matches;
}

/**
 * Finds all notes in `allNotes` whose documents contain a wikilink to `targetTitle` or `targetId`.
 */
function findBacklinks(targetId, targetTitle, allNotes, allDocuments) {
    if (!targetTitle && !targetId)
        return [];
    var results = [];
    var normTitle = normalizeText(targetTitle);
    var notesList = allNotes || [];

    for (var i = 0; i < notesList.length; i++) {
        var note = notesList[i];
        if (!note || note.id === targetId || note.trashedAt > 0)
            continue;

        var doc = allDocuments ? (allDocuments[note.id] || (typeof allDocuments.get === "function" ? allDocuments.get(note.id) : null)) : null;
        var hasRef = false;

        // Check document text blocks if doc is provided
        if (doc && Array.isArray(doc.blocks)) {
            for (var b = 0; b < doc.blocks.length; b++) {
                var block = doc.blocks[b];
                if (block && typeof block.text === "string" && block.text.indexOf("[[") !== -1) {
                    var links = extractWikilinks(block.text);
                    for (var l = 0; l < links.length; l++) {
                        if (normalizeText(links[l]) === normTitle || links[l] === targetId) {
                            hasRef = true;
                            break;
                        }
                    }
                }
                if (hasRef)
                    break;
            }
        } else if (typeof note.preview === "string" && note.preview.indexOf("[[") !== -1) {
            var pLinks = extractWikilinks(note.preview);
            for (var pl = 0; pl < pLinks.length; pl++) {
                if (normalizeText(pLinks[pl]) === normTitle || pLinks[pl] === targetId) {
                    hasRef = true;
                    break;
                }
            }
        }

        if (hasRef)
            results.push(note);
    }
    return results;
}

// ── Query Parser ────────────────────────────────────────────────────────────

function parseDateValue(str) {
    if (!str)
        return null;
    var trimmed = str.trim();
    // Support YYYY-MM-DD
    var parts = trimmed.split("-");
    if (parts.length === 3) {
        var y = parseInt(parts[0], 10);
        var m = parseInt(parts[1], 10) - 1;
        var d = parseInt(parts[2], 10);
        return new Date(y, m, d).getTime();
    }
    var num = Number(trimmed);
    if (!isNaN(num) && num > 0)
        return num;
    var parsed = Date.parse(trimmed);
    return isNaN(parsed) ? null : parsed;
}

/**
 * Parses query into terms and filter operators.
 */
function parseQuery(queryString) {
    var raw = String(queryString || "").trim();
    var terms = [];
    var filters = {
        tags: [],
        notebooks: [],
        sections: [],
        has: [],
        is: [],
        dates: []
    };

    if (raw.length === 0)
        return { terms: [], filters: filters };

    var tokens = raw.split(/\s+/);
    for (var i = 0; i < tokens.length; i++) {
        var token = tokens[i].trim();
        if (token.length === 0)
            continue;

        var colonIdx = token.indexOf(":");
        if (colonIdx > 0) {
            var prefix = token.slice(0, colonIdx).toLowerCase();
            var val = token.slice(colonIdx + 1).trim();

            if (prefix === "tag" || prefix === "etiqueta") {
                if (val.length > 0)
                    filters.tags.push(normalizeText(val));
                continue;
            }
            if (prefix === "caderno" || prefix === "notebook") {
                if (val.length > 0)
                    filters.notebooks.push(normalizeText(val));
                continue;
            }
            if (prefix === "secao" || prefix === "seção" || prefix === "section") {
                if (val.length > 0)
                    filters.sections.push(normalizeText(val));
                continue;
            }
            if (prefix === "tem" || prefix === "has") {
                var normVal = normalizeText(val);
                if (normVal === "imagem" || normVal === "image" || normVal === "img")
                    filters.has.push("image");
                else if (normVal === "tinta" || normVal === "ink" || normVal === "desenho" || normVal === "draw")
                    filters.has.push("ink");
                else if (normVal === "link" || normVal === "url")
                    filters.has.push("link");
                else if (normVal === "arquivo" || normVal === "file")
                    filters.has.push("file");
                else if (normVal === "codigo" || normVal === "código" || normVal === "code")
                    filters.has.push("code");
                else if (normVal === "tabela" || normVal === "table")
                    filters.has.push("table");
                else if (normVal === "tarefa" || normVal === "todo" || normVal === "checklist")
                    filters.has.push("todo");
                continue;
            }
            if (prefix === "is" || prefix === "e" || prefix === "é") {
                var isVal = normalizeText(val);
                if (isVal === "favorite" || isVal === "favourite" || isVal === "fav" || isVal === "favorita")
                    filters.is.push("favorite");
                else if (isVal === "pinned" || isVal === "fixada" || isVal === "fixado")
                    filters.is.push("pinned");
                else if (isVal === "trash" || isVal === "lixeira")
                    filters.is.push("trash");
                else if (isVal === "todo")
                    filters.is.push("todo");
                else if (isVal === "done")
                    filters.is.push("done");
                continue;
            }
            if (prefix === "favorita" || prefix === "favorito") {
                if (val === "sim" || val === "true" || val === "1")
                    filters.is.push("favorite");
                continue;
            }
            if (prefix === "fixada" || prefix === "fixado") {
                if (val === "sim" || val === "true" || val === "1")
                    filters.is.push("pinned");
                continue;
            }
            if (prefix === "lixeira") {
                if (val === "sim" || val === "true" || val === "1")
                    filters.is.push("trash");
                continue;
            }
            if (prefix === "criada" || prefix === "created" || prefix === "modificada" || prefix === "modified") {
                var field = (prefix === "criada" || prefix === "created") ? "created" : "modified";
                var op = "=";
                var dateStr = val;
                if (val.slice(0, 2) === ">=" || val.slice(0, 2) === "<=") {
                    op = val.slice(0, 2);
                    dateStr = val.slice(2);
                } else if (val[0] === ">" || val[0] === "<") {
                    op = val[0];
                    dateStr = val.slice(1);
                }
                var parsedDate = parseDateValue(dateStr);
                if (parsedDate !== null)
                    filters.dates.push({ field: field, op: op, value: parsedDate });
                continue;
            }
        }

        // Regular search term
        var subTokens = tokenize(token);
        for (var t = 0; t < subTokens.length; t++)
            terms.push(subTokens[t]);
    }

    return { terms: terms, filters: filters };
}

// ── Inverted Index Implementation ───────────────────────────────────────────

function createIndex() {
    var index = {
        // token -> { noteId -> count }
        tokens: {},
        // noteId -> { titleTokens, tagTokens, headingTokens, bodyTokens, flags }
        notes: {}
    };

    function addToken(token, noteId, weight) {
        if (!index.tokens[token])
            index.tokens[token] = {};
        index.tokens[token][noteId] = (index.tokens[token][noteId] || 0) + weight;
    }

    function indexNote(note, document) {
        if (!note || !note.id)
            return;
        removeNote(note.id);

        var noteId = note.id;
        var title = note.title || "";
        var tags = Array.isArray(note.tags) ? note.tags : [];
        var preview = note.preview || "";

        var titleTokens = tokenize(title);
        var tagTokens = [];
        for (var i = 0; i < tags.length; i++) {
            var tks = tokenize(tags[i]);
            for (var k = 0; k < tks.length; k++)
                tagTokens.push(tks[k]);
        }

        var headingTokens = [];
        var bodyTokens = [];
        var flags = {
            hasImage: note.hasImages === true,
            hasInk: note.hasInk === true,
            hasLink: false,
            hasFile: false,
            hasCode: false,
            hasTable: false,
            hasTodo: false,
            allDone: false,
            hasUnchecked: false
        };

        if (document && Array.isArray(document.blocks)) {
            var totalTasks = 0;
            var completedTasks = 0;

            for (var b = 0; b < document.blocks.length; b++) {
                var block = document.blocks[b];
                if (!block)
                    continue;

                if (block.type === "image")
                    flags.hasImage = true;
                if (block.type === "ink")
                    flags.hasInk = true;
                if (block.type === "linkPreview")
                    flags.hasLink = true;
                if (block.type === "fileLink")
                    flags.hasFile = true;
                if (block.type === "code") {
                    flags.hasCode = true;
                    if (block.text) {
                        var cTokens = tokenize(block.text);
                        for (var c = 0; c < cTokens.length; c++)
                            bodyTokens.push(cTokens[c]);
                    }
                }
                if (block.type === "table")
                    flags.hasTable = true;

                if (block.type === "heading" && block.text) {
                    var hTokens = tokenize(block.text);
                    for (var h = 0; h < hTokens.length; h++)
                        headingTokens.push(hTokens[h]);
                } else if (block.text) {
                    if (block.text.indexOf("http://") !== -1 || block.text.indexOf("https://") !== -1)
                        flags.hasLink = true;
                    var bTokens = tokenize(block.text);
                    for (var bt = 0; bt < bTokens.length; bt++)
                        bodyTokens.push(bTokens[bt]);
                }

                if (block.type === "list" && block.style === "checkbox") {
                    flags.hasTodo = true;
                    totalTasks++;
                    if (block.checked === true)
                        completedTasks++;
                }
            }

            if (totalTasks > 0) {
                flags.allDone = completedTasks === totalTasks;
                flags.hasUnchecked = completedTasks < totalTasks;
            }
        } else {
            var pTokens = tokenize(preview);
            for (var pt = 0; pt < pTokens.length; pt++)
                bodyTokens.push(pTokens[pt]);
        }

        // Add tokens to inverted index with weights
        for (var tt = 0; tt < titleTokens.length; tt++)
            addToken(titleTokens[tt], noteId, 10);
        for (var tg = 0; tg < tagTokens.length; tg++)
            addToken(tagTokens[tg], noteId, 5);
        for (var ht = 0; ht < headingTokens.length; ht++)
            addToken(headingTokens[ht], noteId, 4);
        for (var by = 0; by < bodyTokens.length; by++)
            addToken(bodyTokens[by], noteId, 1);

        index.notes[noteId] = {
            title: title,
            preview: preview,
            tags: tags,
            flags: flags,
            created: note.created || 0,
            modified: note.modified || 0
        };
    }

    function removeNote(noteId) {
        if (!index.notes[noteId])
            return;
        for (var token in index.tokens) {
            if (index.tokens[token][noteId])
                delete index.tokens[token][noteId];
        }
        delete index.notes[noteId];
    }

    function build(notes, documents) {
        index.tokens = {};
        index.notes = {};
        var list = notes || [];
        for (var i = 0; i < list.length; i++) {
            var n = list[i];
            var doc = documents ? (documents[n.id] || (typeof documents.get === "function" ? documents.get(n.id) : null)) : null;
            indexNote(n, doc);
        }
    }

    function matchesFilters(note, filters, notebooks) {
        // Trash status
        var wantsTrash = filters.is.indexOf("trash") !== -1;
        if (wantsTrash && note.trashedAt <= 0)
            return false;
        if (!wantsTrash && note.trashedAt > 0)
            return false;

        // Tags filter
        if (filters.tags.length > 0) {
            var noteTags = Array.isArray(note.tags) ? note.tags.map(normalizeText) : [];
            for (var i = 0; i < filters.tags.length; i++) {
                if (noteTags.indexOf(filters.tags[i]) === -1)
                    return false;
            }
        }

        // Notebooks filter
        if (filters.notebooks.length > 0 && notebooks) {
            var nb = null;
            for (var n = 0; n < notebooks.length; n++) {
                if (notebooks[n].id === note.notebookId) {
                    nb = notebooks[n];
                    break;
                }
            }
            if (!nb)
                return false;
            var nbTitle = normalizeText(nb.title);
            var nbMatch = false;
            for (var fn = 0; fn < filters.notebooks.length; fn++) {
                if (nbTitle.indexOf(filters.notebooks[fn]) !== -1) {
                    nbMatch = true;
                    break;
                }
            }
            if (!nbMatch)
                return false;
        }

        var meta = index.notes[note.id] || { flags: {} };
        var flags = meta.flags || {};

        // Has filter
        for (var h = 0; h < filters.has.length; h++) {
            var item = filters.has[h];
            if (item === "image" && !flags.hasImage && !note.hasImages)
                return false;
            if (item === "ink" && !flags.hasInk && !note.hasInk)
                return false;
            if (item === "link" && !flags.hasLink)
                return false;
            if (item === "file" && !flags.hasFile)
                return false;
            if (item === "code" && !flags.hasCode)
                return false;
            if (item === "table" && !flags.hasTable)
                return false;
            if (item === "todo" && !flags.hasTodo)
                return false;
        }

        // Is filter
        for (var s = 0; s < filters.is.length; s++) {
            var isItem = filters.is[s];
            if (isItem === "favorite" && !note.favorite)
                return false;
            if (isItem === "pinned" && !note.pinned)
                return false;
            if (isItem === "done" && (!flags.hasTodo || !flags.allDone))
                return false;
            if (isItem === "todo" && (!flags.hasTodo || !flags.hasUnchecked))
                return false;
        }

        // Date filters
        for (var d = 0; d < filters.dates.length; d++) {
            var dateFilter = filters.dates[d];
            var timestamp = dateFilter.field === "created" ? note.created : note.modified;
            if (!timestamp)
                return false;

            if (dateFilter.op === ">" && !(timestamp > dateFilter.value))
                return false;
            if (dateFilter.op === "<" && !(timestamp < dateFilter.value))
                return false;
            if (dateFilter.op === ">=" && !(timestamp >= dateFilter.value))
                return false;
            if (dateFilter.op === "<=" && !(timestamp <= dateFilter.value))
                return false;
            if (dateFilter.op === "=") {
                // Same day comparison (within 24 hours window)
                var dayDiff = Math.abs(timestamp - dateFilter.value);
                if (dayDiff > 86400000)
                    return false;
            }
        }

        return true;
    }

    function search(queryStr, notes, documents, notebooks) {
        var parsed = parseQuery(queryStr);
        var terms = parsed.terms;
        var filters = parsed.filters;
        var allNotes = notes || [];

        // If index is empty, build it
        if (Object.keys(index.notes).length === 0 && allNotes.length > 0)
            build(allNotes, documents);

        // If no terms and no operators, return all notes sorted by pinned then modified
        if (terms.length === 0 &&
            filters.tags.length === 0 &&
            filters.notebooks.length === 0 &&
            filters.sections.length === 0 &&
            filters.has.length === 0 &&
            filters.is.length === 0 &&
            filters.dates.length === 0) {
            return allNotes.slice().sort(function (a, b) {
                if (a.pinned !== b.pinned)
                    return a.pinned ? -1 : 1;
                return (b.modified || 0) - (a.modified || 0);
            });
        }

        var results = [];
        for (var i = 0; i < allNotes.length; i++) {
            var note = allNotes[i];
            if (!note)
                continue;

            if (!matchesFilters(note, filters, notebooks))
                continue;

            // If terms are specified, calculate score
            var score = 0;
            var matchedAllTerms = true;

            if (terms.length > 0) {
                for (var t = 0; t < terms.length; t++) {
                    var term = terms[t];
                    var termMap = index.tokens[term];
                    var termScore = termMap ? (termMap[note.id] || 0) : 0;

                    // Prefix match fallback if exact token did not match
                    if (termScore === 0) {
                        for (var indexedToken in index.tokens) {
                            if (indexedToken.indexOf(term) === 0) {
                                var subMap = index.tokens[indexedToken];
                                if (subMap[note.id])
                                    termScore += Math.floor(subMap[note.id] * 0.7);
                            }
                        }
                    }

                    if (termScore > 0) {
                        score += termScore;
                    } else {
                        matchedAllTerms = false;
                        break;
                    }
                }

                if (!matchedAllTerms)
                    continue;

                // Bonus for match in note title
                var normTitle = normalizeText(note.title);
                for (var st = 0; st < terms.length; st++) {
                    if (normTitle.indexOf(terms[st]) !== -1)
                        score += 50;
                }
            } else {
                // Matched filters alone
                score = 1;
            }

            if (note.pinned)
                score += 10;

            results.push({
                note: note,
                score: score,
                terms: terms
            });
        }

        // Sort descending by score, then recency
        results.sort(function (a, b) {
            if (b.score !== a.score)
                return b.score - a.score;
            return (b.note.modified || 0) - (a.note.modified || 0);
        });

        var out = [];
        for (var r = 0; r < results.length; r++)
            out.push(results[r].note);
        return out;
    }

    return {
        indexNote: indexNote,
        removeNote: removeNote,
        build: build,
        search: search,
        parseQuery: parseQuery,
        extractWikilinks: extractWikilinks,
        findBacklinks: findBacklinks
    };
}

// ── Snippet Highlighting Helper ─────────────────────────────────────────────

/**
 * Extracts a snippet centered around the first occurrence of any search term.
 * Formats matching words with <b>...</b> for QML StyledText.
 */
function highlightSnippet(text, terms, maxLength) {
    if (!text)
        return "";
    var limit = maxLength || 120;
    var str = String(text).replace(/\s+/g, " ").trim();
    if (!terms || terms.length === 0)
        return str.length > limit ? str.slice(0, limit) + "…" : str;

    var norm = normalizeText(str);
    var firstPos = -1;
    var matchedTermLen = 0;

    for (var i = 0; i < terms.length; i++) {
        var t = normalizeText(terms[i]);
        var pos = norm.indexOf(t);
        if (pos !== -1 && (firstPos === -1 || pos < firstPos)) {
            firstPos = pos;
            matchedTermLen = t.length;
        }
    }

    if (firstPos === -1)
        return str.length > limit ? str.slice(0, limit) + "…" : str;

    // Window around match
    var half = Math.floor((limit - matchedTermLen) / 2);
    var start = Math.max(0, firstPos - half);
    var end = Math.min(str.length, start + limit);
    if (end - start < limit && start > 0)
        start = Math.max(0, end - limit);

    var snippet = str.slice(start, end);
    if (start > 0)
        snippet = "…" + snippet;
    if (end < str.length)
        snippet = snippet + "…";

    return snippet;
}

// Top-level singleton instance for convenient calls:
var defaultIndex = createIndex();

function searchNotes(query, notes, documents, notebooks) {
    return defaultIndex.search(query, notes, documents, notebooks);
}
