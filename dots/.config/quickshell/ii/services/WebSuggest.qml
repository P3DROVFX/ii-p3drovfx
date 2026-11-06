pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell

/**
 * Live autocomplete for the Search's "search the web" continuation.
 *
 * The engine is whichever one `search.engineBaseUrl` points at, so the typed
 * text only ever goes to the engine the user already searches with. An engine
 * with no known endpoint stays silent unless `customUrl` supplies one.
 *
 * One request is in flight at a time, debounced, and the answers are cached by
 * query. Between a keystroke and its answer the previous list keeps showing,
 * narrowed to what still starts with the typed text, so the rows do not blink.
 */
Singleton {
    id: root

    readonly property var options: Config.options?.search?.webSuggestions ?? null
    readonly property bool enabled: root.options?.enable !== false && root.endpoint.length > 0
    readonly property int maxResults: Math.max(1, Math.min(10, Number(root.options?.maxResults ?? 5)))
    readonly property int minChars: Math.max(1, Number(root.options?.minChars ?? 2))
    readonly property int debounceMs: Math.max(60, Number(root.options?.debounceMs ?? 220))
    readonly property bool onlyWithoutLocalMatch: root.options?.onlyWithoutLocalMatch !== false

    // Bumped when a fresh answer lands; LauncherSearch recomputes on it.
    property int revision: 0
    property string lastQuery: ""
    property var lastSuggestions: []
    property string pendingQuery: ""
    property var cache: ({})
    property var cacheOrder: []
    readonly property int maxCacheEntries: 48
    property var activeRequest: null

    // Hosts whose public autocomplete answers the OpenSearch JSON shape
    // ["query", ["a", "b", ...]]. The query is appended URL-encoded.
    readonly property var knownEndpoints: [
        { match: /(^|\.)google\.[a-z.]+$/, url: "https://suggestqueries.google.com/complete/search?client=firefox&q=" },
        { match: /(^|\.)duckduckgo\.com$/, url: "https://duckduckgo.com/ac/?type=list&q=" },
        { match: /(^|\.)bing\.com$/, url: "https://api.bing.com/osjson.aspx?query=" },
        { match: /(^|\.)search\.brave\.com$/, url: "https://search.brave.com/api/suggest?q=" }
    ]

    readonly property string endpoint: {
        const custom = String(root.options?.customUrl ?? "").trim();
        if (custom.length > 0)
            return custom;
        const base = String(Config.options?.search?.engineBaseUrl ?? "");
        const host = (/^https?:\/\/([^\/?#:]+)/i.exec(base)?.[1] ?? "").toLowerCase();
        for (let i = 0; i < root.knownEndpoints.length; i++) {
            if (root.knownEndpoints[i].match.test(host))
                return root.knownEndpoints[i].url;
        }
        return "";
    }

    onEndpointChanged: root.reset()

    function reset() {
        root._abort();
        debounce.stop();
        root.pendingQuery = "";
        root.lastQuery = "";
        root.lastSuggestions = [];
        root.cache = ({});
        root.cacheOrder = [];
    }

    function _abort() {
        if (root.activeRequest) {
            const request = root.activeRequest;
            root.activeRequest = null;
            request.abort();
        }
    }

    function _normalized(text): string {
        return String(text ?? "").trim().toLowerCase();
    }

    /** Asks for suggestions for `text`; a falsy argument cancels. */
    function request(text) {
        const query = String(text ?? "").trim();
        if (!root.enabled || query.length < root.minChars) {
            root._abort();
            debounce.stop();
            root.pendingQuery = "";
            return;
        }
        const key = root._normalized(query);
        if (root.cache[key] !== undefined) {
            root._abort();
            debounce.stop();
            root.pendingQuery = "";
            root._publish(query, root.cache[key]);
            return;
        }
        root.pendingQuery = query;
        debounce.restart();
    }

    function _publish(query, list) {
        root.lastQuery = query;
        root.lastSuggestions = list;
        root.revision++;
    }

    function _remember(key, list) {
        const next = Object.assign({}, root.cache);
        next[key] = list;
        const order = root.cacheOrder.filter(k => k !== key);
        order.push(key);
        while (order.length > root.maxCacheEntries)
            delete next[order.shift()];
        root.cache = next;
        root.cacheOrder = order;
    }

    /** Both OpenSearch lists and DuckDuckGo's default [{phrase}] shape. */
    function _parse(text): var {
        const parsed = JSON.parse(text);
        let raw = [];
        if (Array.isArray(parsed) && Array.isArray(parsed[1]))
            raw = parsed[1];
        else if (Array.isArray(parsed))
            raw = parsed;
        const out = [];
        for (let i = 0; i < raw.length; i++) {
            const item = raw[i];
            const phrase = typeof item === "string" ? item : String(item?.phrase ?? "");
            if (phrase.trim().length > 0)
                out.push(phrase.trim());
        }
        return out;
    }

    function _fetch() {
        const query = root.pendingQuery;
        if (query.length === 0 || !root.enabled)
            return;
        root._abort();
        const xhr = new XMLHttpRequest();
        root.activeRequest = xhr;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (root.activeRequest !== xhr)
                return;
            root.activeRequest = null;
            if (xhr.status !== 200)
                return;
            try {
                const list = root._parse(xhr.responseText);
                root._remember(root._normalized(query), list);
                if (root.pendingQuery === query)
                    root.pendingQuery = "";
                root._publish(query, list);
            } catch (e) {
                console.warn("[WebSuggest] Unreadable answer: " + e);
            }
        };
        xhr.open("GET", root.endpoint + encodeURIComponent(query));
        xhr.timeout = 4000;
        xhr.send();
    }

    /**
     * What to list for `text` right now: its own answer when cached, otherwise
     * the previous answer narrowed to entries that still extend the typed text.
     */
    function suggestionsFor(text): var {
        const key = root._normalized(text);
        if (!root.enabled || key.length < root.minChars)
            return [];
        const source = root.cache[key] !== undefined
            ? root.cache[key]
            : (root.lastSuggestions ?? []).filter(s => root._normalized(s).startsWith(key));
        return source.filter(s => root._normalized(s) !== key).slice(0, root.maxResults);
    }

    Timer {
        id: debounce
        interval: root.debounceMs
        repeat: false
        onTriggered: root._fetch()
    }
}
