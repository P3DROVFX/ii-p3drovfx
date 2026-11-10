pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.services
import qs.modules.common

/**
 * Word-synced lyrics from a free, keyless source, for songs BetterLyrics has no
 * word timing for. Only word-level results are kept: a line-synced answer would
 * just repeat LRCLib.
 *
 * source "lrcmux":  api.lrcmux.dev aggregates KuGou, LRCLib and YouTube Music and
 *                  returns JSON lines with word start/end in ms.
 * source "netease": NetEase Cloud Music, a search (matched by duration) followed by
 *                  the `yrc` lyric: `[lineStart,lineDur](wordStart,wordDur,0)word…`.
 *
 * Lines come out in the BetterLyrics shape ({ time, endTime, text, words[] }) so
 * every lyrics view, the kinetic one included, reads them unchanged.
 */
Item {
    id: root
    visible: false

    property string source: "lrcmux"
    property bool enabled: false
    // Already normalised by the caller (BetterLyrics' query fields).
    property string title: ""
    property string artist: ""
    property real duration: 0
    property real position: 0

    property bool loading: false
    property string error: ""
    property var lines: []
    property string plainLyricsText: ""
    readonly property bool hasSyncedLines: root.lines && root.lines.length > 0
    // Done with the current track, found or not (or not asked to look).
    readonly property bool settled: !root.enabled || root.loadedKey === root.fetchKey

    readonly property int queryDuration: Math.round(duration ?? 0)
    readonly property string fetchKey: `${title}||${artist}||${queryDuration}`
    property string loadedKey: ""
    property string requestKey: ""
    property var _cache: ({})
    property var _negativeCache: ({})
    property bool _cacheLoaded: false

    // A recording of the same song with a different length has different timings.
    readonly property real durationTolerance: 4

    readonly property int currentIndex: indexForPosition(position)
    readonly property string displayText: {
        if (!root.enabled)
            return "";
        if (root.loading)
            return Translation.tr("Fetching lyrics…");
        const line = root.currentIndex >= 0 ? (root.lines[root.currentIndex]?.text ?? "") : "";
        return line.length > 0 ? line : "♪";
    }

    function indexForPosition(seconds) {
        if (!root.lines || root.lines.length === 0)
            return -1;
        if (isNaN(seconds) || seconds < 0)
            seconds = 0;
        let lo = 0, hi = root.lines.length - 1, idx = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (root.lines[mid].time <= seconds) {
                idx = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return idx;
    }

    // Credits some sources put at the top as if they were sung.
    readonly property var creditPattern: /^\s*(作词|作曲|编曲|制作人|制作|混音|母带|和声|吉他|贝斯|鼓|录音|监制|出品|词|曲|lyrics?|lyricist|composer|producer|written by|arranger)\s*[:：]/i

    // Word texts carry their own trailing space; split it off as the views expect.
    function makeWord(rawText, begin, end) {
        const m = /^([\s\S]*?)(\s*)$/.exec(rawText);
        const text = m ? m[1] : rawText;
        if (!text.trim())
            return null;
        return {
            text: text,
            trailingSpace: m ? m[2] : "",
            begin: begin,
            end: end,
            startTime: begin,
            endTime: end
        };
    }

    function makeLine(time, endTime, words) {
        const clean = words.filter(w => w);
        if (clean.length === 0)
            return null;
        // The last word's space would leak into the line text.
        clean[clean.length - 1].trailingSpace = "";
        for (let i = 0; i < clean.length; i++) {
            if (clean[i].end <= clean[i].begin)
                clean[i].end = clean[i].endTime = i + 1 < clean.length ? clean[i + 1].begin : clean[i].begin + 0.35;
        }
        const text = clean.map(w => w.text + w.trailingSpace).join("").replace(/\s+/g, " ").trim();
        if (!text || root.creditPattern.test(text))
            return null;
        return {
            time: time,
            endTime: Math.max(endTime, clean[clean.length - 1].end),
            text: text,
            words: clean
        };
    }

    function parseLrcmux(json) {
        if (json?.meta?.level !== "word" || !Array.isArray(json.lines))
            return [];
        const trackDuration = json.track?.duration ?? 0;
        if (root.queryDuration > 0 && trackDuration > 0
                && Math.abs(trackDuration - root.queryDuration) > root.durationTolerance)
            return [];
        const out = [];
        for (const l of json.lines) {
            const words = (l.words ?? []).map(w => root.makeWord(String(w.text ?? ""), w.start / 1000, w.end / 1000));
            const line = root.makeLine(l.start / 1000, (l.end ?? 0) / 1000, words);
            if (line)
                out.push(line);
        }
        return out;
    }

    function parseYrc(yrc) {
        const out = [];
        for (const raw of String(yrc ?? "").split("\n")) {
            const head = /^\[(\d+),(\d+)\]/.exec(raw);
            if (!head)
                continue; // JSON credit rows and blanks
            const start = parseInt(head[1], 10) / 1000;
            const end = start + parseInt(head[2], 10) / 1000;
            const words = [];
            const wordRegex = /\((\d+),(\d+),\d+\)([^(]*)/g;
            let m;
            while ((m = wordRegex.exec(raw.slice(head[0].length))) !== null) {
                const b = parseInt(m[1], 10) / 1000;
                words.push(root.makeWord(m[3], b, b + parseInt(m[2], 10) / 1000));
            }
            const line = root.makeLine(start, end, words);
            if (line)
                out.push(line);
        }
        out.sort((a, b) => a.time - b.time);
        return out;
    }

    // Closest-length NetEase hit whose title matches; a wrong song is worse than none.
    function pickNeteaseSong(json) {
        const songs = json?.result?.songs ?? [];
        const want = root.title.toLowerCase();
        let best = null, bestDiff = Infinity;
        for (const s of songs) {
            const name = String(s.name ?? "").toLowerCase();
            if (!(name.indexOf(want) >= 0 || want.indexOf(name) >= 0))
                continue;
            const diff = root.queryDuration > 0 ? Math.abs((s.duration ?? 0) / 1000 - root.queryDuration) : 0;
            if (diff <= root.durationTolerance && diff < bestDiff) {
                best = s;
                bestDiff = diff;
            }
        }
        return best;
    }

    function resetState() {
        root.loading = false;
        root.error = "";
        root.lines = [];
        root.plainLyricsText = "";
        root.loadedKey = "";
        root.requestKey = "";
    }

    function retryFetch() {
        const key = root.fetchKey;
        if (root._cache[key]) {
            const next = Object.assign({}, root._cache);
            delete next[key];
            root._cache = next;
            root.saveCache();
        }
        delete root._negativeCache[key];
        root.resetState();
        if (root.enabled)
            fetchDebounce.restart();
    }

    function finish(key, lines) {
        if (key !== root.fetchKey)
            return;
        root.loading = false;
        root.loadedKey = key;
        if (lines.length > 0) {
            root.lines = lines;
            root.plainLyricsText = lines.map(l => l.text).join("\n");
            root._cache[key] = { lines: lines };
            root.saveCache();
        } else {
            root._negativeCache[key] = true;
        }
    }

    function applyCached() {
        const cached = root._cache[root.fetchKey];
        if (!cached)
            return false;
        root.lines = cached.lines ?? [];
        root.plainLyricsText = root.lines.map(l => l.text).join("\n");
        root.loadedKey = root.fetchKey;
        return true;
    }

    function ensureFetched() {
        if (!root.enabled || !root._cacheLoaded || !root.title || !root.artist)
            return;
        if (root.loadedKey === root.fetchKey || (fetcher.running && fetcher.requestKey === root.fetchKey))
            return;
        if (root.applyCached())
            return;
        if (root._negativeCache[root.fetchKey]) {
            root.loadedKey = root.fetchKey;
            return;
        }
        root.requestKey = root.fetchKey;
        root.loading = true;
        // Still answering for the previous track; its exit starts this one.
        if (fetcher.running)
            return;
        if (root.source === "netease") {
            fetcher.run("search", ["curl", "-sL", "-m", "15", "-A", "Mozilla/5.0", "-G",
                "https://music.163.com/api/search/get",
                "--data-urlencode", `s=${root.title} ${root.artist}`,
                "--data-urlencode", "type=1", "--data-urlencode", "limit=10"]);
        } else {
            const args = ["curl", "-sL", "-m", "25", "-G", "https://api.lrcmux.dev/get",
                "--data-urlencode", `title=${root.title}`, "--data-urlencode", `artist=${root.artist}`,
                "--data-urlencode", "level=word", "--data-urlencode", "strict=true"];
            if (root.queryDuration > 0)
                args.push("--data-urlencode", `duration=${root.queryDuration}`);
            fetcher.run("get", args);
        }
    }

    Timer {
        id: fetchDebounce
        interval: 250
        onTriggered: root.ensureFetched()
    }

    onFetchKeyChanged: {
        root.resetState();
        if (root.enabled)
            fetchDebounce.restart();
    }
    onEnabledChanged: {
        if (root.enabled)
            fetchDebounce.restart();
        else
            root.loading = false;
    }

    function saveCache() {
        cacheFile.setText(JSON.stringify(root._cache));
    }

    FileView {
        id: cacheFile
        path: `${Directories.lyricsCacheDir}/${root.source}.json`
        printErrors: false // missing until the first word-synced hit
        onLoaded: {
            if (root._cacheLoaded)
                return;
            try {
                root._cache = JSON.parse(cacheFile.text() || "{}");
            } catch (e) {
                root._cache = {};
            }
            root._cacheLoaded = true;
            if (root.enabled)
                root.ensureFetched();
        }
        onLoadFailed: {
            root._cacheLoaded = true;
            if (root.enabled)
                root.ensureFetched();
        }
    }

    Process {
        id: fetcher
        property string stage: ""
        property string requestKey: ""
        // The lyric request NetEase needs after its search, started once the
        // search process has exited.
        property var followUp: null

        function run(stage, command) {
            fetcher.stage = stage;
            fetcher.requestKey = root.requestKey;
            fetcher.command = command;
            fetcher.running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const key = fetcher.requestKey;
                if (key !== root.fetchKey)
                    return;
                let json = null;
                try {
                    json = JSON.parse(this.text || "null");
                } catch (e) {
                    json = null;
                }
                // No answer at all (offline, timeout): settle for now but do not
                // remember the track as missing.
                if (!json) {
                    root.loading = false;
                    root.loadedKey = key;
                    return;
                }
                if (fetcher.stage === "search") {
                    const song = root.pickNeteaseSong(json);
                    if (!song) {
                        root.finish(key, []);
                        return;
                    }
                    fetcher.followUp = ["curl", "-sL", "-m", "15", "-A", "Mozilla/5.0",
                        `https://music.163.com/api/song/lyric/v1?id=${song.id}&lv=1&yv=1`];
                    return;
                }
                if (fetcher.stage === "lyric") {
                    root.finish(key, root.parseYrc(json?.yrc?.lyric));
                    return;
                }
                root.finish(key, root.parseLrcmux(json));
            }
        }
        onExited: {
            const next = fetcher.followUp;
            fetcher.followUp = null;
            if (next && fetcher.requestKey === root.fetchKey)
                fetcher.run("lyric", next);
            else if (root.enabled && root.loadedKey !== root.fetchKey)
                Qt.callLater(root.ensureFetched);
        }
    }
}
