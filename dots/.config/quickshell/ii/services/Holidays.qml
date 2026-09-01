pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Public holidays for the user's country, from the Nager.Date open API.
 *
 * A calendar grid needs to know which squares are red before it can paint
 * them, and it asks that question once per month the user scrolls past. So
 * everything here is pull-based and cached: a year is fetched at most once,
 * kept on disk under "<COUNTRY>-<YEAR>", and served from memory afterwards.
 * There is no timer refreshing anything — public holidays for a past year do
 * not change, and a year that is already known is only re-fetched when
 * someone asks for it explicitly through refresh().
 *
 * The country is whatever the user typed in the settings, or, when that says
 * "auto", whatever the system locale admits to. When neither yields two
 * letters the service goes quiet rather than guessing: no requests, no
 * errors, an empty map.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.calendar?.holidays?.enable ?? true
    readonly property string configuredCountry: Config.options?.calendar?.holidays?.countryCode ?? "auto"

    /** ISO 3166-1 alpha-2, or "" when it could not be resolved. */
    readonly property string countryCode: {
        const configured = String(root.configuredCountry ?? "").trim();
        if (configured.length > 0 && configured.toLowerCase() !== "auto")
            return root.normalizeCountry(configured);
        const fromQtLocale = root.countryFromLocaleString(Qt.locale().name);
        if (fromQtLocale.length > 0)
            return fromQtLocale;
        return root.countryFromLocaleString(Quickshell.env("LANG"));
    }

    /** Raw API payloads, keyed "<COUNTRY>-<YEAR>". Replaced, never mutated. */
    property var entries: ({})

    /** { "yyyy-MM-dd": [{ name, localName, global }] } for the current country. */
    readonly property var byDayKey: {
        const map = {};
        const country = root.countryCode;
        if (!root.enabled || country.length === 0)
            return map;
        const prefix = `${country}-`;
        const all = root.entries;
        for (const key in all) {
            if (key.indexOf(prefix) !== 0)
                continue;
            const list = all[key];
            if (!Array.isArray(list))
                continue;
            for (let i = 0; i < list.length; i++) {
                const item = list[i];
                if (!item)
                    continue;
                const dayKey = String(item.date ?? "");
                // The API dates are already "YYYY-MM-DD"; anything else is junk.
                if (!/^\d{4}-\d{2}-\d{2}$/.test(dayKey))
                    continue;
                if (map[dayKey] === undefined)
                    map[dayKey] = [];
                map[dayKey].push({
                    name: String(item.name ?? ""),
                    localName: String(item.localName ?? ""),
                    global: item.global === true
                });
            }
        }
        return map;
    }

    function holidaysForDate(date): var {
        const dayKey = root.dayKeyOf(date);
        if (dayKey.length === 0)
            return [];
        const list = root.byDayKey[dayKey];
        return list === undefined ? [] : list;
    }

    function holidayNameForDate(date): string {
        const list = root.holidaysForDate(date);
        if (list.length === 0)
            return "";
        const first = list[0];
        const localName = String(first.localName ?? "");
        return localName.length > 0 ? localName : String(first.name ?? "");
    }

    /**
     * Make sure `year` is available. Cheap and idempotent: the month view
     * calls this on every navigation, so all the interesting work is behind
     * "do I already have it" checks.
     */
    function ensureYear(year) {
        const value = Math.trunc(Number(year));
        if (!root.enabled || root.countryCode.length === 0 || !isFinite(value))
            return;
        const key = `${root.countryCode}-${value}`;
        if (root.entries[key] !== undefined)
            return;
        if (root.inFlight[key] === true)
            return;
        if (!root.ready) {
            root.pending[key] = value;
            return;
        }
        const failedAt = root.failures[key];
        if (failedAt !== undefined && Date.now() - failedAt < root.failureBackoff)
            return;
        root.fetchYear(value);
    }

    /** Drop the current country from the cache and fetch its years again. */
    function refresh() {
        const country = root.countryCode;
        if (country.length === 0)
            return;
        const prefix = `${country}-`;
        const kept = {};
        const years = [];
        for (const key in root.entries) {
            if (key.indexOf(prefix) !== 0) {
                kept[key] = root.entries[key];
                continue;
            }
            const year = parseInt(key.slice(prefix.length), 10);
            if (isFinite(year))
                years.push(year);
        }
        for (const key in root.failures) {
            if (key.indexOf(prefix) === 0)
                delete root.failures[key];
        }
        root.entries = kept;
        root.scheduleSave();
        if (years.length === 0)
            years.push(new Date().getFullYear());
        for (let i = 0; i < years.length; i++)
            root.ensureYear(years[i]);
    }

    // ── Country resolution ────────────────────────────────────────────────

    function normalizeCountry(code): string {
        const value = String(code ?? "").trim().toUpperCase();
        return /^[A-Z]{2}$/.test(value) ? value : "";
    }

    /** "pt_BR" / "en-GB" / "pt_BR.UTF-8" -> "BR" / "GB" / "BR". */
    function countryFromLocaleString(value): string {
        const match = String(value ?? "").match(/[_-]([A-Za-z]{2})\b/);
        return match === null ? "" : root.normalizeCountry(match[1]);
    }

    function dayKeyOf(date): string {
        if (date === undefined || date === null)
            return "";
        if (typeof date === "string")
            return /^\d{4}-\d{2}-\d{2}$/.test(date) ? date : "";
        return Qt.formatDate(date, "yyyy-MM-dd");
    }

    // ── Network ───────────────────────────────────────────────────────────

    /** Years being requested right now, so a slow reply is not asked twice. */
    property var inFlight: ({})
    /** "<COUNTRY>-<YEAR>" -> timestamp of the last failure, for backoff. */
    property var failures: ({})
    /** Years asked for before the disk cache finished loading. */
    property var pending: ({})
    readonly property int failureBackoff: 15 * 60 * 1000
    /** A 404 means the API does not know this country/year at all. */
    readonly property real neverRetry: Number.MAX_VALUE

    function fetchYear(year) {
        const country = root.countryCode;
        const key = `${country}-${year}`;
        root.inFlight[key] = true;

        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            delete root.inFlight[key];

            if (xhr.status !== 200) {
                // Unknown country or unsupported year: stop asking until refresh().
                root.failures[key] = xhr.status === 404 ? root.neverRetry : Date.now();
                console.warn(`[Holidays] Fetch failed for ${key} (HTTP ${String(xhr.status)})`);
                return;
            }

            try {
                const parsed = JSON.parse(xhr.responseText);
                if (!Array.isArray(parsed))
                    throw new Error("expected an array");
                const next = Object.assign({}, root.entries);
                next[key] = parsed;
                root.entries = next;
                delete root.failures[key];
                root.scheduleSave();
            } catch (e) {
                root.failures[key] = Date.now();
                console.warn(`[Holidays] Malformed payload for ${key}: ${e}`);
            }
        };
        xhr.open("GET", `https://date.nager.at/api/v3/PublicHolidays/${year}/${country}`);
        xhr.send();
    }

    function flushPending() {
        const queued = root.pending;
        root.pending = ({});
        for (const key in queued)
            root.ensureYear(queued[key]);
    }

    // Config changes are read, never written back: the service reacts, the
    // settings page owns the value.
    onCountryCodeChanged: root.ensureCurrentYear()
    onEnabledChanged: root.ensureCurrentYear()

    function ensureCurrentYear() {
        root.ensureYear(new Date().getFullYear());
    }

    // ── Disk cache ────────────────────────────────────────────────────────

    property bool ready: false
    readonly property real initTimestamp: Date.now()
    readonly property int gracePeriod: 2000

    function scheduleSave() {
        saveDebounce.restart();
    }

    function save() {
        if (!root.ready) {
            saveDebounce.restart();
            return;
        }
        cacheFile.setText(JSON.stringify({
            schema: 1,
            entries: root.entries
        }));
    }

    // Several years can land within a few frames of each other; one write.
    Timer {
        id: saveDebounce
        interval: 300
        onTriggered: root.save()
    }

    Timer {
        id: retryTimer
        interval: 500
        onTriggered: cacheFile.reload()
    }

    FileView {
        id: cacheFile

        path: Directories.holidaysCachePath
        // Nothing but this service writes the file, so watching it would only
        // reload our own writes.
        watchChanges: false
        atomicWrites: true
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(cacheFile.text());
                const stored = parsed?.schema === 1 ? parsed.entries : undefined;
                root.entries = (stored && typeof stored === "object") ? stored : ({});
            } catch (e) {
                root.entries = ({});
            }
            root.ready = true;
            root.flushPending();
            root.ensureCurrentYear();
        }

        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                return;
            // A missing file right after a hot-reload is usually the watcher
            // lagging behind the inode, not a first run. Give it a moment.
            if (Date.now() - root.initTimestamp <= root.gracePeriod) {
                retryTimer.restart();
                return;
            }
            root.entries = ({});
            root.ready = true;
            root.save();
            root.flushPending();
            root.ensureCurrentYear();
        }
    }
}
