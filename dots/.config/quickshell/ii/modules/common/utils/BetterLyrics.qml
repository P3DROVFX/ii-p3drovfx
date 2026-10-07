pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions

Item {
    id: root
    visible: false

    property bool enabled: false
    property string title: ""
    property string artist: ""
    property string album: ""
    property real duration: 0
    property real position: 0

    property bool loading: false
    property string error: ""
    property var fetchedLines: []
    property var lines: root.fetchedLines
    property string plainLyricsText: ""
    readonly property bool hasSyncedLines: root.lines && root.lines.length > 0
    property var _cache: ({})
    property var _negativeCache: ({})

    property string loadedKey: ""
    property string requestKey: ""
    property int requestId: 0
    property int attempt: 0
    property bool startPending: false

    readonly property string queryTitle: normalizeTitle(title)
    readonly property string queryArtist: normalizeArtist(artist)
    readonly property string queryAlbum: normalizeAlbum(album)
    readonly property int queryDuration: Math.round(duration ?? 0)
    readonly property string queryKey: `${queryTitle}||${queryArtist}||${queryAlbum}||${queryDuration}`
    readonly property string fetchKey: queryKey

    readonly property int currentIndex: syncedLyricIndexForPosition(position)
    readonly property string currentLineText: currentIndex >= 0 ? (root.lines[currentIndex]?.text ?? "") : ""
    readonly property int prevIndex: prevNonEmptyIndex(currentIndex)
    readonly property string prevLineText: prevIndex >= 0 ? (root.lines[prevIndex]?.text ?? "") : ""
    readonly property int nextIndex: nextNonEmptyIndex(currentIndex)
    readonly property string nextLineText: nextIndex >= 0 ? (root.lines[nextIndex]?.text ?? "") : ""
    readonly property string displayText: {
        if (!root.enabled)
            return "";
        if (root.loading)
            return Translation.tr("Fetching lyrics…");
        if (root.error && root.error.length > 0)
            return root.error;
        return root.currentLineText && root.currentLineText.length > 0 ? root.currentLineText : "♪";
    }

    function normalizeTitle(rawTitle) {
        if (!rawTitle)
            return "";

        let cleaned = String(rawTitle).trim();

        // 1. Strip bracketed/parenthesized content, unless it mentions featuring
        cleaned = cleaned.replace(/\s*[\(\[\{]([^\)\]\}]*)[\)\]\}]\s*/g, function(_, inner) {
            if (/(?:feat\.?|ft\.?|featuring)/i.test(inner)) {
                const m = inner.replace(/^(?:feat\.?|ft\.?|featuring)\s*/i, '').trim();
                return m ? ` feat. ${m} ` : ' ';
            }
            return ' ';
        });

        // 2. Check for hyphens separating title from edition/remaster suffixes
        const parts = cleaned.split(" - ");
        const main = parts[0].trim();
        if (parts.length > 1) {
            const suffix = parts.slice(1).join(" - ").trim();
            if (/\b(remaster|remastered|deluxe|bonus|expanded|edition|live|mono|stereo|anniversary|edit|mix|rework)\b/i.test(suffix))
                cleaned = main;
            else if (/\b(remix)\b/i.test(suffix))
                cleaned = `${main} ${suffix}`;
            else
                cleaned = main;
        } else {
            cleaned = main;
        }

        cleaned = cleaned.replace(/\s+/g, " ").trim();
        return cleaned;
    }

    function normalizeArtist(rawArtist) {
        if (!rawArtist)
            return "";

        let cleaned = rawArtist.trim();
        cleaned = cleaned.split(",")[0];
        cleaned = cleaned.split(/ feat\.? /i)[0];
        cleaned = cleaned.split(/ ft\.? /i)[0];
        cleaned = cleaned.split(/ featuring /i)[0];
        cleaned = cleaned.split(/ & /)[0];
        cleaned = cleaned.split(/ x /i)[0];
        return cleaned.trim();
    }

    function normalizeAlbum(rawAlbum) {
        if (!rawAlbum)
            return "";
        let cleaned = String(rawAlbum).trim();
        cleaned = cleaned.replace(/\s*[\(\[\{](?:deluxe|bonus|remaster|remastered|expanded|anniversary|edition)[^\)\]\}]*[\)\]\}]\s*/gi, " ");
        const parts = cleaned.split(" - ");
        if (parts.length > 1 && /\b(deluxe|bonus|remaster|remastered|expanded|anniversary|edition)\b/i.test(parts[1]))
            cleaned = parts[0];
        return cleaned.replace(/\s+/g, " ").trim();
    }

    function parseTime(timeStr) {
        if (!timeStr)
            return 0;
        timeStr = timeStr.trim();
        if (timeStr.endsWith("ms"))
            return parseFloat(timeStr.slice(0, -2)) / 1000;
        if (timeStr.endsWith("s"))
            return parseFloat(timeStr.slice(0, -1));

        const parts = timeStr.split(":");
        if (parts.length === 3) {
            const h = parseFloat(parts[0]) || 0;
            const m = parseFloat(parts[1]) || 0;
            const s = parseFloat(parts[2].replace(",", ".")) || 0;
            return h * 3600 + m * 60 + s;
        } else if (parts.length === 2) {
            const m = parseFloat(parts[0]) || 0;
            const s = parseFloat(parts[1].replace(",", ".")) || 0;
            return m * 60 + s;
        } else if (parts.length === 1) {
            return parseFloat(parts[0].replace(",", ".")) || 0;
        }
        return 0;
    }

    function decodeXmlEntities(text) {
        if (!text)
            return "";
        return text
            .replace(/&quot;/g, '"')
            .replace(/&apos;/g, "'")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&amp;/g, "&")
            .replace(/&#(\d+);/g, (_, dec) => String.fromCharCode(parseInt(dec, 10)))
            .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
    }

    function parseTtmlLyrics(ttmlText) {
        if (!ttmlText)
            return [];

        const parsed = [];
        const pRegex = /<p\b([^>]*)>([\s\S]*?)<\/p>/gi;
        let match;

        while ((match = pRegex.exec(ttmlText)) !== null) {
            const attrs = match[1];
            const content = match[2];

            const beginMatch = /\bbegin=["']([^"']+)["']/i.exec(attrs);
            const endMatch = /\bend=["']([^"']+)["']/i.exec(attrs);
            let time = beginMatch ? parseTime(beginMatch[1]) : 0;
            let endTime = endMatch ? parseTime(endMatch[1]) : 0;

            const words = [];
            const spanRegex = /<span\b([^>]*)>([\s\S]*?)<\/span>(\s*)/gi;
            let spanMatch;

            while ((spanMatch = spanRegex.exec(content)) !== null) {
                const spanAttrs = spanMatch[1];
                const spanContent = spanMatch[2];
                const trailingSpace = spanMatch[3] !== undefined ? spanMatch[3] : " ";
                const spanBegin = /\bbegin=["']([^"']+)["']/i.exec(spanAttrs);
                const spanEnd = /\bend=["']([^"']+)["']/i.exec(spanAttrs);
                const spanText = decodeXmlEntities(spanContent.replace(/<[^>]+>/g, ""));

                if (spanBegin && spanText) {
                    const bTime = parseTime(spanBegin[1]);
                    const eTime = spanEnd ? parseTime(spanEnd[1]) : 0;
                    words.push({
                        text: spanText,
                        trailingSpace: trailingSpace,
                        begin: bTime,
                        end: eTime > 0 ? eTime : 0,
                        startTime: bTime,
                        endTime: eTime > 0 ? eTime : 0
                    });
                }
            }

            // Ensure positive duration for every word/syllable
            for (let w = 0; w < words.length; w++) {
                if (words[w].end <= words[w].begin) {
                    const nextBegin = (w + 1 < words.length)
                        ? words[w + 1].begin
                        : (endTime > words[w].begin ? endTime : words[w].begin + 0.35);
                    words[w].end = Math.max(words[w].begin + 0.1, nextBegin);
                    words[w].endTime = words[w].end;
                }
            }

            if (!beginMatch && words.length > 0)
                time = words[0].begin;
            if (!endMatch && words.length > 0)
                endTime = words[words.length - 1].end;

            const text = decodeXmlEntities(content.replace(/<br\s*\/?>/gi, " ").replace(/<[^>]+>/g, "")).replace(/\s+/g, " ").trim();
            if (text) {
                parsed.push({
                    time,
                    endTime,
                    text,
                    words
                });
            }
        }

        parsed.sort((a, b) => a.time - b.time);
        return parsed;
    }

    function syncedLyricIndexForPosition(positionSeconds) {
        if (!root.lines || root.lines.length === 0)
            return -1;

        if (isNaN(positionSeconds) || positionSeconds < 0)
            positionSeconds = 0;

        let lo = 0;
        let hi = root.lines.length - 1;
        let idx = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (root.lines[mid].time <= positionSeconds) {
                idx = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }

        for (let i = idx; i >= 0; --i) {
            const text = root.lines[i].text;
            if (text && text.length > 0)
                return i;
        }

        return -1;
    }

    function nextNonEmptyIndex(fromIndex) {
        if (!root.lines || root.lines.length === 0)
            return -1;

        let startIndex = fromIndex < -1 ? -1 : fromIndex;
        for (let i = startIndex + 1; i < root.lines.length; ++i) {
            const text = root.lines[i].text;
            if (text && text.length > 0)
                return i;
        }
        return -1;
    }

    function prevNonEmptyIndex(fromIndex) {
        if (!root.lines || root.lines.length === 0 || fromIndex <= 0)
            return -1;

        for (let i = fromIndex - 1; i >= 0; --i) {
            const text = root.lines[i].text;
            if (text && text.length > 0)
                return i;
        }
        return -1;
    }

    function buildLyricsUrl(attempt) {
        const title = root.queryTitle;
        const artist = root.queryArtist;
        const album = root.queryAlbum;
        const duration = root.queryDuration;

        if (!title || !artist)
            return "";

        const base = "https://api.betterlyrics.org/getLyrics";

        // Attempt 0: Song, Artist, Duration (highest cache-hit rate, matches any album edition)
        if (attempt === 0 && duration > 0) {
            return `${base}?s=${encodeURIComponent(title)}&a=${encodeURIComponent(artist)}&d=${duration}`;
        }

        // Attempt 1: With Album and Duration (if album exists)
        if (attempt === 1 && album && duration > 0) {
            return `${base}?s=${encodeURIComponent(title)}&a=${encodeURIComponent(artist)}&al=${encodeURIComponent(album)}&d=${duration}`;
        }

        // Attempt 2: Small duration tolerance (+1s)
        if (attempt === 2 && duration > 0) {
            return `${base}?s=${encodeURIComponent(title)}&a=${encodeURIComponent(artist)}&d=${duration + 1}`;
        }

        // Attempt 3: Small duration tolerance (-1s)
        if (attempt === 3 && duration > 0) {
            return `${base}?s=${encodeURIComponent(title)}&a=${encodeURIComponent(artist)}&d=${duration - 1}`;
        }

        // Attempt 4: Song and Artist only (fallback)
        if (attempt === 4 || (attempt === 0 && duration <= 0)) {
            return `${base}?s=${encodeURIComponent(title)}&a=${encodeURIComponent(artist)}`;
        }

        return "";
    }

    function resetState() {
        root.loading = false;
        root.error = "";
        root.fetchedLines = [];
        root.plainLyricsText = "";
        root.loadedKey = "";
        root.requestKey = "";
        root.attempt = 0;
        root.startPending = false;
    }

    function retryFetch() {
        const key = root.queryKey;
        if (root._cache[key]) {
            const next = Object.assign({}, root._cache);
            delete next[key];
            root._cache = next;
            root.saveCache();
        }
        delete root._negativeCache[key];

        root.resetState();
        if (root.enabled)
            root.ensureFetched();
    }

    function ensureFetched() {
        if (!root.enabled)
            return;

        if (!root.queryTitle || !root.queryArtist) {
            root.error = "No track info";
            return;
        }

        if (root.loadedKey === root.fetchKey)
            return;

        if (root.loading && root.requestKey === root.fetchKey)
            return;

        if (fetcher.running && fetcher.requestKey === root.fetchKey)
            return;

        if (root._negativeCache[root.fetchKey]) {
            root.loading = false;
            root.error = "";
            return;
        }

        root.requestId += 1;
        root.attempt = 0;
        root.requestKey = root.fetchKey;
        root.loading = true;
        root.error = "";
        root.fetchedLines = [];

        if (fetcher.running) {
            root.startPending = true;
            return;
        }

        root.fetchAttempt(root.requestId);
    }

    function fetchAttempt(requestId) {
        if (requestId !== root.requestId)
            return;
        if (root.requestKey !== root.fetchKey)
            return;

        const url = root.buildLyricsUrl(root.attempt);
        if (!url) {
            root.loading = false;
            root._negativeCache[root.fetchKey] = true;
            return;
        }

        fetcher.requestId = requestId;
        fetcher.requestKey = root.requestKey;
        fetcher.attempt = root.attempt;
        fetcher.command = ["curl", "-sL", "-w", "\nHTTP_STATUS:%{http_code}", url];
        fetcher.running = true;
    }

    Timer {
        id: fetchDebounce
        interval: 200
        repeat: false
        onTriggered: root.ensureFetched()
    }

    onFetchKeyChanged: {
        root.resetState();

        if (lyricFileView.isInitialLoad) {
            fetchDebounce.restart();
            return;
        }

        const cached = getCached(root.queryKey);
        if (cached) {
            root.fetchedLines = cached.lines || [];
            root.plainLyricsText = cached.plainLyrics || "";
            root.loading = false;
            root.error = "";
            root.loadedKey = root.fetchKey;
        } else if (root.enabled) {
            fetchDebounce.restart();
        }
    }

    function getCached(key) {
        return root._cache[key] || null;
    }

    function setCache(key, data) {
        root._cache[key] = data;
        saveCache();
    }

    function saveCache() {
        lyricFileView.setText(JSON.stringify(root._cache, null, 2));
    }

    FileView {
        id: lyricFileView
        path: Directories.betterlyricsCachePath
        property bool isInitialLoad: true

        onLoaded: {
            if (isInitialLoad) {
                try {
                    const loaded = JSON.parse(lyricFileView.text() || "{}");
                    root._cache = loaded;
                } catch (e) {
                    root._cache = {};
                }
                isInitialLoad = false;

                if (root.fetchKey) {
                    const cached = getCached(root.queryKey);
                    if (cached) {
                        root.fetchedLines = cached.lines || [];
                        root.plainLyricsText = cached.plainLyrics || "";
                        root.loading = false;
                        root.error = "";
                        root.loadedKey = root.fetchKey;
                    }
                }
            }
        }
    }

    onEnabledChanged: {
        if (root.enabled)
            fetchDebounce.restart();
        else {
            root.loading = false;
            root.startPending = false;
        }
    }

    Process {
        id: fetcher
        property int requestId: 0
        property string requestKey: ""
        property int attempt: 0
        running: false
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const requestId = fetcher.requestId;
                const requestKey = fetcher.requestKey;

                if (requestKey !== root.fetchKey) {
                    if (root.startPending) {
                        root.startPending = false;
                        if (root.enabled)
                            root.fetchAttempt(root.requestId);
                    }
                    return;
                }

                const rawText = this.text || "";
                const marker = "\nHTTP_STATUS:";
                const markerIdx = rawText.lastIndexOf(marker);
                let statusCode = 0;
                let body = rawText;

                if (markerIdx !== -1) {
                    statusCode = parseInt(rawText.substring(markerIdx + marker.length).trim(), 10) || 0;
                    body = rawText.substring(0, markerIdx).trim();
                }

                // If 200 OK, we have a cache hit from BetterLyrics!
                if (statusCode === 200 && body.length > 0) {
                    try {
                        const parsedJson = JSON.parse(body);
                        const ttml = parsedJson.ttml || "";
                        if (ttml && ttml.length > 0) {
                            const parsedLines = root.parseTtmlLyrics(ttml);
                            if (parsedLines && parsedLines.length > 0) {
                                root.fetchedLines = parsedLines;
                                root.plainLyricsText = parsedLines.map(l => l.text).join("\n");
                                root.loading = false;
                                root.error = "";
                                root.loadedKey = requestKey;

                                root.setCache(root.queryKey, {
                                    lines: parsedLines,
                                    plainLyrics: root.plainLyricsText
                                });
                                return;
                            }
                        }
                    } catch (e) {
                        console.log("[BetterLyrics] Error parsing TTML JSON:", e);
                    }
                }

                // If not 200 (or if parsing failed), try next query variant if available
                const nextAttempt = root.attempt + 1;
                const nextUrl = root.buildLyricsUrl(nextAttempt);
                if (nextUrl) {
                    root.attempt = nextAttempt;
                    root.fetchAttempt(requestId);
                    return;
                }

                // All attempts exhausted: this track is not cached on BetterLyrics (Cache Miss or 404)
                root.loading = false;
                root.error = "";
                root.fetchedLines = [];
                root.plainLyricsText = "";
                root.loadedKey = requestKey;
                root._negativeCache[requestKey] = true;
            }
        }
    }
}
