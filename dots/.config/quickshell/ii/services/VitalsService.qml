pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import "vitals/VitalsLogic.js" as Logic

/**
 * ii Vitals: the phone's health data (Samsung Health, Health Connect) kept on the PC.
 *
 * The phone sends days over the ii link (scripts/iiLink/PROTOCOL.md, "Vitals"); this
 * keeps each one as it came in `~/.local/state/quickshell/user/vitals/` (0700/0600,
 * atomic, written by scripts/vitals/vitals_store.py) and a small index of per-day
 * Summaries that every chart reads. Day files load on demand into a bounded cache, so a
 * year of history costs one index in memory. The copy stays while the phone is away.
 *
 * IiLinkService creates this only once a phone with `vitals` connects (or a UI asks), and
 * nothing is read from disk while `iiTools.vitals.enable` is off.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.iiTools?.vitals?.enable ?? false
    readonly property string stepsFrom: Config.options?.vitals?.stepsFrom ?? "auto"
    readonly property int retentionDays: Config.options?.vitals?.retentionDays ?? 0
    readonly property string storeDir: FileUtils.trimFileProtocol(`${Directories.state}/user/vitals`)

    /// The phone is connected and offers `vitals`.
    readonly property bool linked: root.enabled && IiLinkService.vitalsDev !== ""
    /**
     * "off" (switch off) · "syncing" (an answer is coming in; data may already be there) ·
     * "ready" (data kept, linked or not: see `linked`) · without data: "notPaired" ·
     * "offline" (paired, no phone connected) · "noFeature" (the phone does not share, or
     * said why it cannot: `lastError`) · "empty" (linked, the phone has nothing).
     */
    readonly property string state: {
        if (!root.enabled)
            return "off";
        if (root.syncing)
            return "syncing";
        if (root.dates.length > 0)
            return "ready";
        if (!IiLinkService.hasPeers)
            return "notPaired";
        if (!IiLinkService.phoneConnected)
            return "offline";
        if (!root.linked || root.lastError !== "")
            return "noFeature";
        return "empty";
    }
    readonly property var meta: root._meta
    readonly property var index: root._data.index
    readonly property var dates: root._data.dates
    readonly property var present: root._data.present
    readonly property real lastSync: root._lastSync
    readonly property bool syncing: root._syncing
    readonly property real progress: root._progress
    readonly property int dataVersion: root._data.version
    /// The phone's last `error` ("disabled" | "permission" | "unavailable"), "" after data.
    readonly property string lastError: root._lastError
    /// The store's files have been read (index, sync state, meta).
    readonly property bool loaded: root._indexRead && root._syncRead && root._metaRead

    signal dayLoaded(string date)
    signal routeLoaded(string id)

    property var _meta: null
    // One object, so every read here (summary, series, latest…) sees an index, its dates
    // and its present set from the same swap, whichever of them woke the binding.
    property var _data: ({ index: {}, dates: [], present: {}, version: 0 })
    property real _lastSync: 0
    property string _lastPage: ""
    /// Where an answer cut short (phone gone, timeout) would have gone on; "" when the last
    /// one finished. Kept in sync.json, so the next connect asks from there.
    property string _resume: ""
    property bool _syncing: false
    property real _progress: 0
    property string _lastError: ""
    property bool _indexRead: false
    property bool _syncRead: false
    property bool _metaRead: false
    /// Messages that came before the index was read, and a get waiting for it.
    property var _early: []
    property bool _getPending: false
    /// Where the answer in flight started ("" = the phone's oldest day).
    property string _answerSince: ""

    function _today(): string {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }

    // ── Reads ───────────────────────────────────────────────────────────

    function summary(date: string): var {
        return root._data.index[date] ?? null;
    }

    function series(key: string, fromDate, toDate): var {
        return Logic.series(root._data.index, root._data.dates, key, fromDate ?? "", toDate ?? "");
    }

    function latest(key: string): var {
        return Logic.latest(root._data.index, root._data.dates, key);
    }

    /// The Day as stored, or null; a stored one not in memory loads and emits dayLoaded.
    function day(date: string): var {
        const cached = root._dayCache[date];
        if (cached !== undefined) {
            root._touch(date);
            return cached;
        }
        if (root._data.index[date] !== undefined)
            root._read("day", date);
        return null;
    }

    function sleepFor(date: string): var {
        const s = root._data.index[date];
        if (!s?.sleep)
            return null;
        const d = root._dayCache[date];
        if (d === undefined)
            root._read("day", date);
        return Logic.sleepFor(s, d ?? null);
    }

    function age(): int {
        return Logic.age(root._meta?.profile?.birthDate ?? "", root._today());
    }

    function hrZones(): var {
        return Logic.hrZones(root.age());
    }

    // ── Actions ─────────────────────────────────────────────────────────

    function syncNow(): void {
        // A second paging chain would ask for every page again; the running one covers it.
        if (root._syncing)
            return;
        if (root.loaded)
            root._get(Logic.sinceOnConnect(root._data.dates, root._meta?.stepsFrom ?? "", root.stepsFrom, root._resume));
        else
            root._getPending = true;
    }

    function setStepsFrom(v: string): void {
        if (!["auto", "health", "phone"].includes(v) || v === root.stepsFrom)
            return;
        Config.options.vitals.stepsFrom = v;
        // Steps change on every day.
        root._get("", v);
    }

    function setRetention(days: int): void {
        if (![0, 365, 90].includes(days) || days === root.retentionDays)
            return;
        Config.options.vitals.retentionDays = days;
        const req = { write: [] };
        if (root._prune(req, days) > 0) {
            req.write.push(["index.json", JSON.stringify({ v: Logic.INDEX_V, days: root._data.index })]);
            req.write.push(["sync.json", root._syncText()]);
        }
        if (req.pruneBefore)
            root._store(req);
    }

    /// Removes the PC's copy; the phone sends everything again when linked.
    function deleteLocalCopy(): void {
        root._store({ wipe: true });
        root._meta = null;
        root._lastSync = 0;
        root._lastPage = "";
        root._resume = "";
        root._lastError = "";
        root._routes = ({});
        root._routeCache = ({});
        root._routeQueue = [];
        root._routeAsking = "";
        root._dayCache = ({});
        root._dayOrder = [];
        root._setIndex({});
        if (root.linked)
            root._get("");
    }

    /// Points of a stored route, or null: one not on disk is asked from the phone while
    /// linked (and its routes are on); either way routeLoaded(id) follows when it lands.
    function route(id: string): var {
        const cached = root._routeCache[id];
        if (cached !== undefined)
            return cached;
        if (root._routes[id] === 1)
            root._read("route", id);
        else if (root._routes[id] === undefined && /^[0-9a-f]{16}$/.test(id) && root._meta?.routes === true) {
            root._routeQueue = [id].concat(root._routeQueue.filter(x => x !== id));
            root._askRoute();
        }
        return null;
    }

    // ── From IiLinkService ──────────────────────────────────────────────

    /// The phone with `vitals` connected: catch up on what changed.
    function connected(): void {
        root._lastError = "";
        // A chain cut by the disconnect never finishes; this connection starts its own.
        root._endSync();
        root.syncNow();
    }

    /// A `vitals` or `vitalsRoute` message from the linked phone.
    function handleMessage(m: var): void {
        if (!root.enabled)
            return;
        if (!root.loaded) {
            root._early.push(m);
            return;
        }
        if (m?.t === "vitalsRoute")
            root._gotRoute(m);
        else if (m?.t === "vitals")
            root._gotVitals(m);
    }

    onLinkedChanged: {
        if (root.linked)
            return;
        root._endSync();
        root._routeAsking = "";
        root._routeQueue = [];
    }

    onEnabledChanged: {
        if (root.enabled)
            return;
        // Nothing stays in memory with the switch off; the files stay until deleted.
        root._meta = null;
        root._lastSync = 0;
        root._routes = ({});
        root._routeCache = ({});
        root._dayCache = ({});
        root._dayOrder = [];
        root._indexRead = root._syncRead = root._metaRead = false;
        root._early = [];
        root._getPending = false;
        root._endSync();
        root._setIndex({});
    }

    // ── Sync ────────────────────────────────────────────────────────────

    function _get(since: string, stepsFrom): void {
        if (!root.loaded) {
            root._getPending = true;
            return;
        }
        if (!IiLinkService.sendVitals(Logic.getMessage(since, stepsFrom ?? root.stepsFrom)))
            return;
        root._answerSince = since;
        root._syncing = true;
        root._progress = 0;
        answerTimeout.restart();
    }

    function _endSync(): void {
        root._syncing = false;
        root._progress = 0;
        answerTimeout.stop();
    }

    // A phone that stops answering mid-backfill (gone without a disconnect) does not keep
    // the state at "syncing".
    Timer {
        id: answerTimeout
        interval: 120000
        onTriggered: {
            console.warn("[Vitals] the phone did not answer, sync stopped");
            root._endSync();
        }
    }

    function _gotVitals(m: var): void {
        const req = { write: [] };
        if (m.meta !== undefined) {
            const why = Logic.metaError(m.meta);
            if (why !== "") {
                console.warn(`[Vitals] ignored meta: ${why}`);
            } else {
                root._meta = Object.assign({}, m.meta, { receivedAt: Date.now() });
                req.write.push(["meta.json", JSON.stringify(root._meta)]);
            }
        }
        const answer = typeof m.more === "boolean";
        if (typeof m.error === "string") {
            console.info(`[Vitals] the phone cannot share: ${m.error}`);
            root._lastError = m.error;
            root._endSync();
            if (req.write.length > 0)
                root._store(req);
            return;
        }
        root._lastError = "";

        // Days the retention would drop at once are not written at all.
        const cut = Logic.cutoff(root._today(), root.retentionDays);
        const days = (Array.isArray(m.days) ? m.days : []).filter(d => cut === "" || !(d?.date < cut));
        const r = Logic.applyDays(root._data.index, days);
        for (const s of r.skipped)
            console.warn(`[Vitals] skipped day ${s.date}: ${s.why}`);
        root._drop(req, r);
        for (const d of r.write) {
            req.write.push([`days/${d.date}.json`, JSON.stringify(d)]);
            // Kept in memory as well: a read of the file could land before the write.
            root._cache(d.date, d);
        }
        if (days.length > 0 && Logic.isDate(days[days.length - 1]?.date))
            root._lastPage = days[days.length - 1].date;
        if (r.index !== root._data.index)
            root._setIndex(r.index);

        let done = !answer;
        if (answer) {
            answerTimeout.restart();
            root._progress = Logic.progress(root._answerSince || root._meta?.oldest || "", root._lastPage, root._meta?.newest ?? "");
            const next = Logic.nextGet(m, root.stepsFrom);
            root._resume = next?.since ?? "";
            if (next !== null) {
                // An answer this PC did not ask for (a reconnect raced it) is followed too.
                if (IiLinkService.sendVitals(next))
                    root._syncing = true;
                else
                    root._endSync();
            } else {
                if (m.more === true)
                    console.warn("[Vitals] answer page without a valid next date, sync stopped");
                done = true;
                root._endSync();
            }
        }
        if (done) {
            root._lastSync = Date.now();
            root._prune(req, root.retentionDays);
        }
        req.write.push(["index.json", JSON.stringify({ v: Logic.INDEX_V, days: root._data.index })]);
        req.write.push(["sync.json", root._syncText()]);
        root._store(req);
        if (done)
            root._wantRoutes();
    }

    /// Drops the days older than the retention, publishes the smaller index and adds the
    /// file removals to `req`; returns how many days went.
    function _prune(req: var, retention: int): int {
        const cut = Logic.cutoff(root._today(), retention);
        const p = Logic.prune(root._data.index, cut);
        if (cut !== "")
            req.pruneBefore = cut;
        root._drop(req, p);
        if (p.index !== root._data.index)
            root._setIndex(p.index);
        return p.dates.length;
    }

    /// Forgets the day files and routes of days `p` ({dates, routes}) took out of the
    /// index and adds their removals to `req`.
    function _drop(req: var, p: var): void {
        req.delete = (req.delete ?? []).concat(p.dates.map(date => `days/${date}.json`), p.routes.map(id => `routes/${id}.json`));
        for (const date of p.dates)
            delete root._dayCache[date];
        root._dayOrder = root._dayOrder.filter(x => root._dayCache[x] !== undefined);
        if (p.routes.length > 0) {
            const routes = Object.assign({}, root._routes);
            for (const id of p.routes) {
                delete routes[id];
                delete root._routeCache[id];
            }
            root._routes = routes;
        }
    }

    function _setIndex(next: var): void {
        root._data = { index: next, dates: Logic.sortedDates(next), present: Logic.present(next), version: root._data.version + 1 };
    }

    function _syncText(): string {
        return JSON.stringify({ lastSync: root._lastSync, lastPage: root._lastPage, resume: root._resume, routes: root._routes });
    }

    // ── Routes ──────────────────────────────────────────────────────────
    /// id → 1 stored, 0 the phone has none (kept in sync.json, so neither is asked again).
    property var _routes: ({})
    property var _routeCache: ({})
    property var _routeQueue: []
    property string _routeAsking: ""

    function _wantRoutes(): void {
        if (root._meta?.routes !== true)
            return;
        const missing = Logic.missingRoutes(root._data.index, root._data.dates, root._routes);
        root._routeQueue = root._routeQueue.concat(missing.filter(id => !root._routeQueue.includes(id)));
        root._askRoute();
    }

    function _askRoute(): void {
        if (root._routeAsking !== "" || root._routeQueue.length === 0 || !root.linked)
            return;
        const id = root._routeQueue[0];
        root._routeQueue = root._routeQueue.slice(1);
        if (!IiLinkService.sendVitals({ t: "get", what: "vitalsRoute", id: id }))
            return;
        root._routeAsking = id;
        routeTimeout.restart();
    }

    Timer {
        id: routeTimeout
        interval: 30000
        onTriggered: {
            root._routeAsking = "";
            root._askRoute();
        }
    }

    function _gotRoute(m: var): void {
        const id = String(m.id ?? "");
        if (!/^[0-9a-f]{16}$/.test(id))
            return;
        if (id === root._routeAsking) {
            root._routeAsking = "";
            routeTimeout.stop();
        }
        const points = Logic.routePoints(m.points);
        const routes = Object.assign({}, root._routes);
        const req = { write: [] };
        if (points !== null) {
            routes[id] = 1;
            req.write.push([`routes/${id}.json`, JSON.stringify({ id: id, points: points })]);
            root._routeCache[id] = points;
        } else if (m.error === "none") {
            routes[id] = 0;
        } else {
            if (m.error !== "off")
                console.warn(`[Vitals] ignored route ${id}: points`);
            // Routes are off on the phone: stop asking until the next sync.
            root._routeQueue = [];
        }
        root._routes = routes;
        req.write.push(["sync.json", root._syncText()]);
        root._store(req);
        if (points !== null)
            root.routeLoaded(id);
        root._askRoute();
    }

    // ── Store files ─────────────────────────────────────────────────────

    FileView {
        id: indexFile
        path: root.enabled ? `${root.storeDir}/index.json` : ""
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(indexFile.text());
                if (parsed?.v === Logic.INDEX_V && parsed.days && typeof parsed.days === "object") {
                    const p = Logic.purgeEmpty(parsed.days);
                    root._setIndex(p.index);
                    if (p.dates.length > 0) {
                        const req = { write: [["index.json", JSON.stringify({ v: Logic.INDEX_V, days: p.index })]] };
                        root._drop(req, p);
                        root._store(req);
                    }
                } else if (parsed?.v === 1 && parsed.days && typeof parsed.days === "object") {
                    // Shown as it is until the rebuild swaps the new one in whole; the store
                    // counts as read only then, so no message lands on the old one.
                    root._setIndex(parsed.days);
                    rebuilder.old = parsed.days;
                    rebuilder.running = true;
                    return;
                } else
                    console.warn("[Vitals] index.json has an unknown shape, starting empty");
            } catch (e) {
                console.warn("[Vitals] index.json is unreadable, starting empty");
            }
            root._indexRead = true;
            root._filesRead();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[Vitals] could not read index.json:", error);
            root._indexRead = true;
            root._filesRead();
        }
    }

    // An index summarized under an older rule: every day again from its file, which the
    // store already holds, so it needs neither the phone nor a resend. One file per line:
    // JSON.stringify never writes a newline and the files end without one.
    Process {
        id: rebuilder
        property var old: ({})
        command: ["find", `${root.storeDir}/days`, "-maxdepth", "1", "-name", "*.json", "-exec", "awk", "1", "{}", "+"]
        stdout: StdioCollector {
            id: rebuiltText
            onStreamFinished: root._rebuilt(rebuiltText.text)
        }
    }

    function _rebuilt(text: string): void {
        const fresh = {};
        for (const line of text.split("\n")) {
            let d = null;
            try {
                d = JSON.parse(line);
            } catch (e) {
                continue;
            }
            if (Logic.dayError(d) === "" && rebuilder.old[d.date] !== undefined)
                fresh[d.date] = Logic.summarize(d);
        }
        const p = Logic.migrate(rebuilder.old, fresh);
        rebuilder.old = ({});
        // Switched off meanwhile: that cleared everything, and nothing is written.
        if (!root.enabled)
            return;
        console.info(`[Vitals] index re-summarized from ${Object.keys(fresh).length} day files`);
        root._setIndex(p.index);
        const req = { write: [["index.json", JSON.stringify({ v: Logic.INDEX_V, days: p.index })]] };
        root._drop(req, p);
        root._store(req);
        root._indexRead = true;
        root._filesRead();
    }

    // Messages wait for all three files: one landing later would overwrite what they set.
    function _filesRead(): void {
        if (!root.loaded)
            return;
        const early = root._early;
        root._early = [];
        for (const m of early)
            root.handleMessage(m);
        if (root._getPending) {
            root._getPending = false;
            root.syncNow();
        }
    }

    FileView {
        id: syncFile
        path: root.enabled ? `${root.storeDir}/sync.json` : ""
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(syncFile.text());
                root._lastSync = Number(s?.lastSync) || 0;
                root._lastPage = Logic.isDate(s?.lastPage) ? s.lastPage : "";
                root._resume = Logic.isDate(s?.resume) ? s.resume : "";
                if (s?.routes && typeof s.routes === "object")
                    root._routes = s.routes;
            } catch (e) {
                console.warn("[Vitals] sync.json is unreadable");
            }
            root._syncRead = true;
            root._filesRead();
        }
        onLoadFailed: {
            root._syncRead = true;
            root._filesRead();
        }
    }

    FileView {
        id: metaFile
        path: root.enabled ? `${root.storeDir}/meta.json` : ""
        printErrors: false
        onLoaded: {
            try {
                const m = JSON.parse(metaFile.text());
                if (Logic.metaError(m) === "")
                    root._meta = m;
            } catch (e) {
                console.warn("[Vitals] meta.json is unreadable");
            }
            root._metaRead = true;
            root._filesRead();
        }
        onLoadFailed: {
            root._metaRead = true;
            root._filesRead();
        }
    }

    // ── Lazy reads: one FileView, one file at a time ────────────────────
    readonly property int _cacheSize: 14
    property var _dayCache: ({})
    property var _dayOrder: []
    property var _readQueue: []
    property var _reading: null

    function _touch(date: string): void {
        root._dayOrder = root._dayOrder.filter(x => x !== date).concat([date]);
    }

    function _cache(date: string, d: var): void {
        root._dayCache[date] = d;
        root._touch(date);
        while (root._dayOrder.length > root._cacheSize) {
            delete root._dayCache[root._dayOrder[0]];
            root._dayOrder = root._dayOrder.slice(1);
        }
    }

    function _read(kind: string, key: string): void {
        if (root._readQueue.some(j => j.kind === kind && j.key === key)
            || (root._reading?.kind === kind && root._reading?.key === key))
            return;
        root._readQueue = root._readQueue.concat([{ kind: kind, key: key }]);
        root._readNext();
    }

    function _readNext(): void {
        if (root._reading !== null || root._readQueue.length === 0)
            return;
        const job = root._readQueue[0];
        root._readQueue = root._readQueue.slice(1);
        root._reading = job;
        const path = `${root.storeDir}/${job.kind === "day" ? "days" : "routes"}/${job.key}.json`;
        if (reader.path === path)
            reader.reload();
        else
            reader.path = path;
    }

    function _readDone(text: var): void {
        const job = root._reading;
        root._reading = null;
        if (job !== null && text !== null) {
            let parsed = null;
            try {
                parsed = JSON.parse(text);
            } catch (e) {}
            if (job.kind === "day") {
                const want = root._data.index[job.key];
                if (Logic.dayError(parsed) !== "" || parsed.date !== job.key)
                    console.warn(`[Vitals] day file ${job.key} is unreadable`);
                // A file older than the index is a write still queued; the new Day is cached.
                else if (want !== undefined && parsed.hash === want.hash) {
                    root._cache(job.key, parsed);
                    root.dayLoaded(job.key);
                }
            } else {
                const points = Logic.routePoints(parsed?.points);
                if (points !== null) {
                    root._routeCache[job.key] = points;
                    root.routeLoaded(job.key);
                } else {
                    console.warn(`[Vitals] route file ${job.key} is unreadable`);
                }
            }
        }
        Qt.callLater(root._readNext);
    }

    FileView {
        id: reader
        printErrors: false
        onLoaded: root._readDone(reader.text())
        onLoadFailed: root._readDone(null)
    }

    // ── Writes: one store process at a time, in order ───────────────────
    property var _writeQueue: []

    function _store(req: var): void {
        root._writeQueue.push(JSON.stringify(Object.assign({ dir: root.storeDir }, req)));
        root._flush();
    }

    function _flush(): void {
        if (writer.running || root._writeQueue.length === 0)
            return;
        writer.payload = root._writeQueue.shift();
        writer.running = true;
    }

    Process {
        id: writer
        property string payload: ""
        stdinEnabled: true
        command: ["python3", `${Directories.scriptPath}/vitals/vitals_store.py`]
        stderr: StdioCollector {
            id: writerErr
        }
        onStarted: writer.write(writer.payload + "\n")
        onExited: code => {
            if (code !== 0)
                console.warn("[Vitals] store write failed:", writerErr.text.trim());
            writer.payload = "";
            Qt.callLater(root._flush);
        }
    }
}
