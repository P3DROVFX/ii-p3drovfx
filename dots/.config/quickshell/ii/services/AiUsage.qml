pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Token accounting for the AI chat, one bucket per local day.
 *
 * `Ai` hands each finished response here (from markDone, the single choke
 * point every response passes exactly once); input/output/thinking/total are
 * whatever the provider's last usage frame said, or -1 across the board when
 * the dialect never reports usage — requests still count, tokens do not.
 * Responses carry an outcome too: `ok` unless the message was flagged with an
 * error kind, which feeds the success-rate donut. Today's entry additionally
 * keeps an hourly breakdown for the "Today" view; older days are flattened
 * back to day totals so the file stays small.
 *
 * The whole ledger is one flat map persisted through the same FileView +
 * JsonAdapter pattern as AppUsage: a top-level `var` (never a `var` inside a
 * nested JsonObject — that trips Quickshell's JSON adapter), atomic writes,
 * readiness guard and retry-then-create against hot-reload inode races.
 */
Singleton {
    id: root

    /**
 * {days: {"2026-08-16": {input, output, thinking, total, cost, costResponses,
 *                         requests, ok, err,
 *                         hours: {"14": {total, cost, costResponses, requests, ok, err}},
 *                         models: {"provider:model": {total, cost, costResponses, requests}}}},
 *  models: {"provider:model": {total, cost, costResponses, requests}},
 *  allTime: {input, output, thinking, total, cost, costResponses, requests, ok, err}}
     */
    property var data: ({})
    property bool ready: false
    // A response can finish before this singleton's FileView has loaded on a
    // fresh shell start. Keep those records in RAM, then merge them only after
    // the persisted ledger is in place instead of silently losing local and
    // free-model usage.
    property var pendingResponses: []
    property real initTimestamp: Date.now()
    property int missingFileGracePeriod: 2000
    property int missingFileRetryInterval: 1500
    // Two years of one-entry-per-day is tens of kilobytes; older days go.
    readonly property int retentionDays: 740

    readonly property var allTime: root.data.allTime ?? ({})
    readonly property bool hasData: (root.allTime.total ?? 0) > 0 || (root.allTime.requests ?? 0) > 0
    readonly property int todayTotal: root.totalSince(0)
    readonly property int weekTotal: root.totalSince(6)
    readonly property int monthTotal: root.totalSince(29)
    readonly property int todayRequests: root.requestsSince(0)
    readonly property int monthRequests: root.requestsSince(29)

    function dayKey(date): string {
        return Qt.formatDate(date, "yyyy-MM-dd");
    }

    function dayEntry(date): var {
        const days = root.data.days ?? ({});
        return days[root.dayKey(date)] ?? null;
    }

    /** Token total over the last `daysBack` days, today included. */
    function totalSince(daysBack: int): int {
        let sum = 0;
        for (let i = 0; i <= daysBack; ++i) {
            const day = new Date();
            day.setDate(day.getDate() - i);
            const entry = root.dayEntry(day);
            if (entry)
                sum += Math.max(0, Number(entry.total) || 0);
        }
        return sum;
    }

    function requestsSince(daysBack: int): int {
        let sum = 0;
        for (let i = 0; i <= daysBack; ++i) {
            const day = new Date();
            day.setDate(day.getDate() - i);
            const entry = root.dayEntry(day);
            if (entry)
                sum += Math.max(0, Number(entry.requests) || 0);
        }
        return sum;
    }

    /** Reported USD charges over the last `daysBack` days, today included. */
    function costSince(daysBack: int): real {
        let sum = 0;
        for (let i = 0; i <= daysBack; ++i) {
            const day = new Date();
            day.setDate(day.getDate() - i);
            const entry = root.dayEntry(day);
            if (entry)
                sum += Math.max(0, Number(entry.cost) || 0);
        }
        return sum;
    }

    /** Number of responses whose provider supplied an exact monetary charge. */
    function costResponsesSince(daysBack: int): int {
        let count = 0;
        for (let i = 0; i <= daysBack; ++i) {
            const day = new Date();
            day.setDate(day.getDate() - i);
            const entry = root.dayEntry(day);
            if (entry)
                count += Math.max(0, Number(entry.costResponses) || 0);
        }
        return count;
    }

    /** {input, output, thinking} over the last `daysBack` days, zeros included. */
    function splitSince(daysBack: int): var {
        const split = {input: 0, output: 0, thinking: 0};
        for (let i = 0; i <= daysBack; ++i) {
            const day = new Date();
            day.setDate(day.getDate() - i);
            const entry = root.dayEntry(day);
            if (!entry)
                continue;
            split.input += Math.max(0, Number(entry.input) || 0);
            split.output += Math.max(0, Number(entry.output) || 0);
            split.thinking += Math.max(0, Number(entry.thinking) || 0);
        }
        return split;
    }

    /**
     * {ok, err} over the last `daysBack` days. Days recorded before outcome
     * tracking existed read as zero on both sides — they stay in request and
     * token totals, they just do not vote on the success rate.
     */
    function outcomeSince(daysBack: int): var {
        const outcome = {ok: 0, err: 0};
        for (let i = 0; i <= daysBack; ++i) {
            const day = new Date();
            day.setDate(day.getDate() - i);
            const entry = root.dayEntry(day);
            if (!entry)
                continue;
            outcome.ok += Math.max(0, Number(entry.ok) || 0);
            outcome.err += Math.max(0, Number(entry.err) || 0);
        }
        return outcome;
    }

    /**
     * Oldest-first series of the last `count` days for bar charts:
     * [{key, label, value, requests, tooltip}] with zero-filled gaps.
     */
    function daySeries(count: int): var {
        const result = [];
        for (let i = count - 1; i >= 0; --i) {
            const day = new Date();
            day.setDate(day.getDate() - i);
            const entry = root.dayEntry(day);
            const value = entry ? Math.max(0, Number(entry.total) || 0) : 0;
            const requests = entry ? Math.max(0, Number(entry.requests) || 0) : 0;
            result.push({
                key: root.dayKey(day),
                label: Qt.formatDate(day, "d"),
                value: value,
                requests: requests,
                tooltip: Qt.formatDate(day, "dd/MM") + " · " + root.formatTokens(value)
                    + " " + Translation.tr("tokens") + " · " + String(requests)
                    + " " + Translation.tr("requests")
            });
        }
        return result;
    }

    /** Same shape as daySeries, but the 24 buckets of today. */
    function hourSeries(): var {
        const entry = root.dayEntry(new Date());
        const hours = entry && entry.hours ? entry.hours : ({});
        const result = [];
        for (let hour = 0; hour < 24; ++hour) {
            const bucket = hours[String(hour)];
            const value = bucket ? Math.max(0, Number(bucket.total) || 0) : 0;
            const requests = bucket ? Math.max(0, Number(bucket.requests) || 0) : 0;
            const label = hour < 10 ? "0" + hour : String(hour);
            result.push({
                key: label,
                label: label,
                value: value,
                requests: requests,
                tooltip: label + ":00 · " + root.formatTokens(value)
                    + " " + Translation.tr("tokens") + " · " + String(requests)
                    + " " + Translation.tr("requests")
            });
        }
        return result;
    }

    /** Highest-usage models first: [{id, total, requests}]. */
    function topModels(limit: int): var {
        const models = root.data.models ?? ({});
        const rows = [];
        for (const id in models) {
            const entry = models[id];
            if (!entry)
                continue;
            rows.push({
                id: id,
                total: Math.max(0, Number(entry.total) || 0),
                requests: Math.max(0, Number(entry.requests) || 0)
            });
        }
        rows.sort((a, b) => b.total - a.total || b.requests - a.requests);
        return limit > 0 ? rows.slice(0, limit) : rows;
    }

    /**
     * Same shape, aggregated over the last `daysBack` days from the per-day
     * model buckets. Days recorded before those buckets existed contribute
     * nothing — the all-time `models` map stays the complete history.
     */
    function topModelsSince(daysBack: int, limit: int): var {
        const totals = ({});
        for (let i = 0; i <= daysBack; ++i) {
            const day = new Date();
            day.setDate(day.getDate() - i);
            const entry = root.dayEntry(day);
            if (!entry || !entry.models)
                continue;
            for (const id in entry.models) {
                const modelEntry = entry.models[id];
                if (!modelEntry)
                    continue;
                let bucket = totals[id];
                if (!bucket) {
                    bucket = {total: 0, requests: 0};
                    totals[id] = bucket;
                }
                bucket.total += Math.max(0, Number(modelEntry.total) || 0);
                bucket.requests += Math.max(0, Number(modelEntry.requests) || 0);
            }
        }
        const rows = [];
        for (const id in totals)
            rows.push({id: id, total: totals[id].total, requests: totals[id].requests});
        rows.sort((a, b) => b.total - a.total || b.requests - a.requests);
        return limit > 0 ? rows.slice(0, limit) : rows;
    }

    function formatTokens(value): string {
        const tokens = Math.max(0, Math.round(Number(value) || 0));
        if (tokens >= 1000000)
            return (tokens / 1000000).toFixed(tokens % 1000000 === 0 ? 0 : 1) + "M";
        if (tokens >= 1000)
            return (tokens / 1000).toFixed(tokens % 1000 === 0 ? 0 : 1) + "k";
        return String(tokens);
    }

    function formatCost(value): string {
        const cost = Math.max(0, Number(value) || 0);
        if (cost >= 1)
            return "$" + cost.toFixed(2);
        if (cost >= 0.01)
            return "$" + cost.toFixed(3);
        return "$" + cost.toFixed(4);
    }

    function recordResponse(model: string, input: int, output: int, thinking: int, total: int, ok: bool, cost = -1) {
        const record = {
            model: String(model ?? ""),
            input: Number(input),
            output: Number(output),
            thinking: Number(thinking),
            total: Number(total),
            ok: ok === true,
            cost: Number(cost)
        };
        if (!root.ready) {
            root.pendingResponses = [...root.pendingResponses, record];
            return;
        }
        root.applyResponse(record);
    }

    function flushPendingResponses() {
        if (!root.ready || root.pendingResponses.length === 0)
            return;
        const queued = root.pendingResponses;
        root.pendingResponses = [];
        for (let index = 0; index < queued.length; index++)
            root.applyResponse(queued[index]);
    }

    function applyResponse(record: var) {
        const clean = value => Number(value) >= 0 ? Math.round(Number(value)) : 0;
        const next = {
            days: Object.assign({}, root.data.days ?? ({})),
            models: Object.assign({}, root.data.models ?? ({})),
            allTime: Object.assign({
                input: 0, output: 0, thinking: 0, total: 0, cost: 0, costResponses: 0,
                requests: 0, ok: 0, err: 0
            }, root.allTime)
        };

        const now = new Date();
        const key = root.dayKey(now);
        const day = Object.assign({
            input: 0, output: 0, thinking: 0, total: 0, cost: 0, costResponses: 0,
            requests: 0, ok: 0, err: 0
        }, next.days[key]);
        day.requests += 1;
        if (record.ok)
            day.ok += 1;
        else
            day.err += 1;

        const usageKnown = Number(record.total) >= 0;
        if (usageKnown) {
            day.input += clean(record.input);
            day.output += clean(record.output);
            day.thinking += clean(record.thinking);
            day.total += clean(record.total);
            next.allTime.input += clean(record.input);
            next.allTime.output += clean(record.output);
            next.allTime.thinking += clean(record.thinking);
            next.allTime.total += clean(record.total);
        }
        const costKnown = isFinite(Number(record.cost)) && Number(record.cost) >= 0;
        if (costKnown) {
            const cost = Number(record.cost);
            day.cost += cost;
            day.costResponses += 1;
            next.allTime.cost += cost;
            next.allTime.costResponses += 1;
        }
        next.allTime.requests += 1;
        if (record.ok)
            next.allTime.ok += 1;
        else
            next.allTime.err += 1;

        // Only today keeps the hourly breakdown the "Today" view charts.
        const hours = Object.assign({}, day.hours ?? ({}));
        const hourKey = String(now.getHours());
        const hourBucket = Object.assign({total: 0, cost: 0, costResponses: 0, requests: 0, ok: 0, err: 0}, hours[hourKey]);
        hourBucket.requests += 1;
        if (record.ok)
            hourBucket.ok += 1;
        else
            hourBucket.err += 1;
        if (usageKnown)
            hourBucket.total += clean(record.total);
        if (costKnown) {
            hourBucket.cost += Number(record.cost);
            hourBucket.costResponses += 1;
        }
        hours[hourKey] = hourBucket;
        day.hours = hours;
        next.days[key] = day;

        const modelId = record.model;
        if (modelId.length > 0) {
            const modelEntry = Object.assign({total: 0, cost: 0, costResponses: 0, requests: 0}, next.models[modelId]);
            modelEntry.requests += 1;
            if (usageKnown)
                modelEntry.total += clean(record.total);
            if (costKnown) {
                modelEntry.cost += Number(record.cost);
                modelEntry.costResponses += 1;
            }
            next.models[modelId] = modelEntry;

            // The same totals inside the day bucket give "top models" a
            // period window; `day` is already the copy stored in next.days.
            const dayModels = Object.assign({}, day.models ?? ({}));
            const dayModel = Object.assign({total: 0, cost: 0, costResponses: 0, requests: 0}, dayModels[modelId]);
            dayModel.requests += 1;
            if (usageKnown)
                dayModel.total += clean(record.total);
            if (costKnown) {
                dayModel.cost += Number(record.cost);
                dayModel.costResponses += 1;
            }
            dayModels[modelId] = dayModel;
            day.models = dayModels;
        }

        // Drop buckets older than the retention window and flatten the hourly
        // breakdown of past days; the cut is date-based, never "delete what I
        // cannot parse".
        const cutoff = new Date();
        cutoff.setDate(cutoff.getDate() - root.retentionDays);
        const cutoffKey = root.dayKey(cutoff);
        for (const dayKey_ in next.days) {
            if (dayKey_ < cutoffKey) {
                delete next.days[dayKey_];
                continue;
            }
            const entry = next.days[dayKey_];
            if (dayKey_ !== key && entry && entry.hours) {
                const flat = Object.assign({}, entry);
                delete flat.hours;
                next.days[dayKey_] = flat;
            }
        }

        root.data = next;
    }

    // ── Persistence (AppUsage pattern) ─────────────────────────────────────
    Timer {
        id: fileReloadTimer
        interval: 100
        repeat: false
        onTriggered: usageFileView.reload()
    }

    Timer {
        id: fileWriteTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (!root.ready) {
                fileWriteTimer.restart();
                return;
            }
            usageFileView.writeAdapter()
        }
    }

    Timer {
        id: missingFileRetryTimer
        interval: root.missingFileRetryInterval
        repeat: false
        onTriggered: usageFileView.reload()
    }

    onDataChanged: {
        if (root.ready)
            fileWriteTimer.restart();
    }

    FileView {
        id: usageFileView
        path: Directories.aiUsage
        watchChanges: true
        atomicWrites: true
        onFileChanged: fileReloadTimer.restart()
        onLoaded: {
            const loaded = usageAdapter.data;
            // A missing or corrupted file must not wipe what this session
            // already collected — only replace when the read has the shape.
            if (loaded && typeof loaded === "object" && (loaded.days !== undefined || loaded.allTime !== undefined))
                root.data = loaded;
            root.ready = true;
            root.flushPendingResponses();
        }
        onLoadFailed: error => {
            if (error != FileViewError.FileNotFound)
                return;
            const elapsed = Date.now() - root.initTimestamp;
            if (elapsed > root.missingFileGracePeriod) {
                root.ready = true;
                root.flushPendingResponses();
                fileWriteTimer.restart();
            } else {
                missingFileRetryTimer.restart();
            }
        }

        adapter: JsonAdapter {
            id: usageAdapter
            property var data: root.data
        }
    }
}
