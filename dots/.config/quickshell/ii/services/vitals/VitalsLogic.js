.pragma library

// Pure logic for VitalsService (scripts/iiLink/PROTOCOL.md, "Vitals"): checking what the
// phone sends, the per-day Summary the index keeps, and the reads the app makes from it.
// No Quickshell types, so scripts/tests/test_vitals_contract.py runs it in node.

var KINDS = ["totals", "samples", "sessions", "measurements", "scores"];
var DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
var HASH_RE = /^[0-9a-f]{16}$/;
// Keys become JSON object keys and, for exercise ids, file names.
var KEY_RE = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;

function isDate(s) {
    if (typeof s !== "string" || !DATE_RE.test(s))
        return false;
    var d = new Date(Date.UTC(Number(s.slice(0, 4)), Number(s.slice(5, 7)) - 1, Number(s.slice(8, 10))));
    return toDate(d.getTime()) === s;
}

function isHash(s) {
    return typeof s === "string" && HASH_RE.test(s);
}

function num(v) {
    return typeof v === "number" && isFinite(v);
}

function isObj(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function toDate(utcMs) {
    var d = new Date(utcMs);
    var m = d.getUTCMonth() + 1, day = d.getUTCDate();
    return d.getUTCFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day;
}

/// Calendar arithmetic on "YYYY-MM-DD" (in UTC, so no DST hour shifts a day).
function addDays(date, n) {
    return toDate(Date.UTC(Number(date.slice(0, 4)), Number(date.slice(5, 7)) - 1, Number(date.slice(8, 10)) + n));
}

function daysBetween(from, to) {
    var a = Date.UTC(Number(from.slice(0, 4)), Number(from.slice(5, 7)) - 1, Number(from.slice(8, 10)));
    var b = Date.UTC(Number(to.slice(0, 4)), Number(to.slice(5, 7)) - 1, Number(to.slice(8, 10)));
    return Math.round((b - a) / 86400000);
}

// ── Validation ──────────────────────────────────────────────────────────
// Each returns "" when the value is usable, else a reason that names the key but never a
// value (reasons go to the shell log).

function _checkTotals(k, v) {
    if (!isObj(v) || !num(v.day))
        return "totals." + k + ".day";
    if (v.hourly !== undefined) {
        if (!Array.isArray(v.hourly) || v.hourly.length !== 24)
            return "totals." + k + ".hourly";
        for (var i = 0; i < 24; i++)
            if (!num(v.hourly[i]))
                return "totals." + k + ".hourly";
    }
    return "";
}

function _checkSamples(k, v) {
    if (!isObj(v) || !num(v.min) || !num(v.max) || !num(v.avg))
        return "samples." + k;
    if (v.last !== undefined && !(Array.isArray(v.last) && v.last.length === 2 && num(v.last[0]) && num(v.last[1])))
        return "samples." + k + ".last";
    if (v.bins !== undefined) {
        if (!Array.isArray(v.bins))
            return "samples." + k + ".bins";
        for (var i = 0; i < v.bins.length; i++) {
            var b = v.bins[i];
            if (!Array.isArray(b) || b.length < 2 || !num(b[0]) || b[0] < 0 || b[0] > 1439 || !num(b[1]))
                return "samples." + k + ".bins";
        }
    }
    return "";
}

function _checkSessions(k, v) {
    if (!Array.isArray(v))
        return "sessions." + k;
    for (var i = 0; i < v.length; i++) {
        var s = v[i];
        if (!isObj(s) || !num(s.start) || !num(s.end) || s.end < s.start)
            return "sessions." + k + "[" + i + "]";
        if (k === "exercise" && !isHash(s.id))
            return "sessions.exercise[" + i + "].id";
        if (k === "sleep" && s.stages !== undefined) {
            if (!Array.isArray(s.stages))
                return "sessions.sleep[" + i + "].stages";
            for (var j = 0; j < s.stages.length; j++) {
                var st = s.stages[j];
                if (!Array.isArray(st) || st.length < 3 || !num(st[0]) || !num(st[1]) || typeof st[2] !== "string")
                    return "sessions.sleep[" + i + "].stages";
            }
        }
    }
    return "";
}

function _checkMeasurements(k, v) {
    if (!Array.isArray(v))
        return "measurements." + k;
    for (var i = 0; i < v.length; i++)
        if (!isObj(v[i]) || !num(v[i].time))
            return "measurements." + k + "[" + i + "]";
    return "";
}

function _checkScores(k, v) {
    return num(v) ? "" : "scores." + k;
}

var _checks = {
    totals: _checkTotals,
    samples: _checkSamples,
    sessions: _checkSessions,
    measurements: _checkMeasurements,
    scores: _checkScores
};

/// "" when `d` is a Day the store can keep as it is, else why not.
function dayError(d) {
    if (!isObj(d))
        return "not an object";
    if (!isDate(d.date))
        return "date";
    if (!isHash(d.hash))
        return "hash";
    for (var i = 0; i < KINDS.length; i++) {
        var kind = KINDS[i];
        if (d[kind] === undefined)
            continue;
        if (!isObj(d[kind]))
            return kind;
        for (var k in d[kind]) {
            if (!KEY_RE.test(k))
                return kind + " key";
            var why = _checks[kind](k, d[kind][k]);
            if (why !== "")
                return why;
        }
    }
    if (d.source !== undefined) {
        if (!isObj(d.source))
            return "source";
        for (var s in d.source)
            if (!KEY_RE.test(s) || typeof d.source[s] !== "string")
                return "source";
    }
    return "";
}

/// "" when `m` is a usable meta (`sources` is its one required field).
function metaError(m) {
    if (!isObj(m) || !isObj(m.sources))
        return "meta.sources";
    if (m.oldest !== undefined && !isDate(m.oldest))
        return "meta.oldest";
    if (m.newest !== undefined && !isDate(m.newest))
        return "meta.newest";
    return "";
}

/// Route points `[[epochMs, lat, lon, altM|null], …]`, or null when they are not that.
function routePoints(points) {
    if (!Array.isArray(points))
        return null;
    for (var i = 0; i < points.length; i++) {
        var p = points[i];
        if (!Array.isArray(p) || p.length < 3 || !num(p[0]) || !num(p[1]) || !num(p[2])
            || Math.abs(p[1]) > 90 || Math.abs(p[2]) > 180 || (p.length > 3 && p[3] !== null && !num(p[3])))
            return null;
    }
    return points;
}

// ── Summary ─────────────────────────────────────────────────────────────

/// The night a day belongs to: the longest sleep session filed under it (sessions are filed
/// under the day they end), or null.
function mainSleep(day) {
    var list = day && day.sessions && Array.isArray(day.sessions.sleep) ? day.sessions.sleep : [];
    var best = null;
    for (var i = 0; i < list.length; i++)
        if (best === null || list[i].end - list[i].start > best.end - best.start)
            best = list[i];
    return best;
}

/// The index entry for a valid Day (PROTOCOL.md, "Vitals" → store). Every field is there,
/// empty when the day has nothing of it, except `sleep` (no session) and `rt` (no route).
function summarize(day) {
    var out = { hash: day.hash, t: {}, s: {}, last: {}, n: {}, exMin: 0, m: {}, sc: {} };
    var k;
    for (k in (day.totals || {}))
        out.t[k] = day.totals[k].day;
    for (k in (day.samples || {})) {
        var smp = day.samples[k];
        out.s[k] = [smp.min, smp.avg, smp.max];
        if (smp.last !== undefined)
            out.last[k] = smp.last;
    }
    for (k in (day.sessions || {}))
        out.n[k] = day.sessions[k].length;
    var ex = day.sessions && day.sessions.exercise ? day.sessions.exercise : [];
    var exMs = 0, routes = [];
    for (var i = 0; i < ex.length; i++) {
        exMs += ex[i].end - ex[i].start;
        if (ex[i].route === true)
            routes.push(ex[i].id);
    }
    out.exMin = Math.round(exMs / 60000);
    if (routes.length > 0)
        out.rt = routes;
    var sl = mainSleep(day);
    if (sl !== null) {
        out.sleep = { start: sl.start, end: sl.end, min: Math.round((sl.end - sl.start) / 60000) };
        if (num(sl.score))
            out.sleep.score = sl.score;
    }
    for (k in (day.measurements || {})) {
        var list = day.measurements[k], lastM = null;
        for (var j = 0; j < list.length; j++)
            if (lastM === null || list[j].time >= lastM.time)
                lastM = list[j];
        if (lastM !== null)
            out.m[k] = lastM;
    }
    for (k in (day.scores || {}))
        out.sc[k] = day.scores[k];
    return out;
}

/**
 * What one `vitals` message changes, against the index the PC holds.
 * Returns {index, write: [Day], skipped: [{date, why}], unchanged: n}: `index` is a new
 * object only when something changed (else the same one), `write` the days whose hash
 * differs (to store as received), `skipped` the malformed ones.
 */
function applyDays(index, days) {
    var out = { index: index, write: [], skipped: [], unchanged: 0 };
    if (!Array.isArray(days))
        return out;
    var next = null;
    for (var i = 0; i < days.length; i++) {
        var d = days[i];
        var why = dayError(d);
        if (why !== "") {
            out.skipped.push({ date: isObj(d) && isDate(d.date) ? d.date : "?", why: why });
            continue;
        }
        var have = (next || index)[d.date];
        if (have && have.hash === d.hash) {
            out.unchanged++;
            continue;
        }
        if (next === null)
            next = Object.assign({}, index);
        next[d.date] = summarize(d);
        out.write.push(d);
    }
    if (next !== null)
        out.index = next;
    return out;
}

// ── Retention ───────────────────────────────────────────────────────────

/// The oldest date kept with `retentionDays` (today counts as one), or "" for forever.
function cutoff(today, retentionDays) {
    var n = Math.floor(Number(retentionDays) || 0);
    return n > 0 ? addDays(today, 1 - n) : "";
}

/// {index, dates: [pruned], routes: [route ids of pruned days]}; the same index when
/// nothing is older than `cut`.
function prune(index, cut) {
    var out = { index: index, dates: [], routes: [] };
    if (cut === "")
        return out;
    for (var date in index) {
        if (date >= cut)
            continue;
        out.dates.push(date);
        var rt = index[date].rt || [];
        for (var i = 0; i < rt.length; i++)
            out.routes.push(rt[i]);
    }
    if (out.dates.length > 0) {
        out.index = Object.assign({}, index);
        for (var j = 0; j < out.dates.length; j++)
            delete out.index[out.dates[j]];
    }
    out.dates.sort();
    return out;
}

// ── Reads ───────────────────────────────────────────────────────────────

function sortedDates(index) {
    return Object.keys(index).sort();
}

/// {key: true} for every key any kept day has, plus "sleep"/"exercise" from sessions.
function present(index) {
    var out = {};
    for (var date in index) {
        var s = index[date];
        var groups = [s.t, s.s, s.n, s.m, s.sc];
        for (var g = 0; g < groups.length; g++)
            for (var k in (groups[g] || {}))
                if (groups[g] !== s.n || groups[g][k] > 0)
                    out[k] = true;
    }
    return out;
}

/**
 * One value per day for `key`, from the index alone: totals → day total, samples → the
 * day's mean, scores → score, "sleepMin" → main night's minutes, "exMin" → exercise
 * minutes, "<measurement>.<field>" (e.g. "body.weightKg") → that field of the day's last
 * measurement. Days without the key are left out.
 */
function value(summary, key) {
    if (!summary)
        return undefined;
    if (key === "sleepMin")
        return summary.sleep ? summary.sleep.min : undefined;
    if (key === "exMin")
        return summary.n && summary.n.exercise > 0 ? summary.exMin : undefined;
    var dot = key.indexOf(".");
    if (dot > 0) {
        var m = summary.m ? summary.m[key.slice(0, dot)] : undefined;
        var f = m ? m[key.slice(dot + 1)] : undefined;
        return num(f) ? f : undefined;
    }
    if (summary.t && summary.t[key] !== undefined)
        return summary.t[key];
    if (summary.s && summary.s[key] !== undefined)
        return summary.s[key][1];
    if (summary.sc && summary.sc[key] !== undefined)
        return summary.sc[key];
    return undefined;
}

function series(index, dates, key, fromDate, toDate) {
    var out = [];
    for (var i = 0; i < dates.length; i++) {
        var date = dates[i];
        if ((fromDate && date < fromDate) || (toDate && date > toDate))
            continue;
        var v = value(index[date], key);
        if (v !== undefined)
            out.push({ date: date, value: v });
    }
    return out;
}

/// {value, time, date} for the newest day that has `key`; `time` is epoch ms when the data
/// carries one (a sample's last reading, a measurement, a night's end), else null.
function latest(index, dates, key) {
    for (var i = dates.length - 1; i >= 0; i--) {
        var date = dates[i], s = index[date];
        if (s.last && s.last[key])
            return { value: s.last[key][1], time: s.last[key][0], date: date };
        if (s.m && s.m[key])
            return { value: s.m[key], time: s.m[key].time, date: date };
        if ((key === "sleep" || key === "sleepMin") && s.sleep)
            return { value: key === "sleep" ? s.sleep : s.sleep.min, time: s.sleep.end, date: date };
        var v = value(s, key);
        if (v !== undefined)
            return { value: v, time: null, date: date };
    }
    return null;
}

/// The main night of `date`: from the Day when it is loaded (stages, source), else from
/// its Summary alone.
function sleepFor(summary, day) {
    if (day) {
        var sl = mainSleep(day);
        if (sl === null)
            return null;
        return {
            start: sl.start, end: sl.end, min: Math.round((sl.end - sl.start) / 60000),
            score: num(sl.score) ? sl.score : null,
            stages: Array.isArray(sl.stages) ? sl.stages : [],
            source: day.source && day.source.sleep ? day.source.sleep : ""
        };
    }
    if (!summary || !summary.sleep)
        return null;
    return {
        start: summary.sleep.start, end: summary.sleep.end, min: summary.sleep.min,
        score: num(summary.sleep.score) ? summary.sleep.score : null, stages: null, source: ""
    };
}

/// Route ids the kept days have and the PC lacks (`have`: {id: stored | false = none}).
function missingRoutes(index, dates, have) {
    var out = [];
    for (var i = dates.length - 1; i >= 0; i--) {
        var rt = index[dates[i]].rt || [];
        for (var j = 0; j < rt.length; j++)
            if (have[rt[j]] === undefined)
                out.push(rt[j]);
    }
    return out;
}

// ── Sync ────────────────────────────────────────────────────────────────

/// `since` for the get on connect and Sync now: a week before the newest day kept; "" with
/// nothing kept, or when the steps the phone last applied (`meta.stepsFrom`) are not the
/// ones wanted (changed while the phone was away: steps differ on every day).
function sinceOnConnect(dates, appliedStepsFrom, stepsFrom) {
    if (dates.length === 0 || (appliedStepsFrom && appliedStepsFrom !== stepsFrom))
        return "";
    return addDays(dates[dates.length - 1], -7);
}

function getMessage(since, stepsFrom) {
    return { t: "get", what: "vitals", since: since, stepsFrom: stepsFrom };
}

/// The get for an answer page's next page, or null when the answer is complete (or the
/// page names no valid `next`).
function nextGet(m, stepsFrom) {
    return m && m.more === true && isDate(m.next) ? getMessage(m.next, stepsFrom) : null;
}

/// Backfill progress 0–1: how far the last received day is between where the answer
/// started (its `since`, or the phone's oldest day) and the phone's newest day.
function progress(start, last, newest) {
    if (!isDate(start) || !isDate(last) || !isDate(newest))
        return 0;
    var span = daysBetween(start, newest);
    if (span <= 0)
        return 1;
    return Math.max(0, Math.min(1, daysBetween(start, last) / span));
}

// ── Profile ─────────────────────────────────────────────────────────────

/// Whole years from `birthDate` to `today`, or -1.
function age(birthDate, today) {
    if (!isDate(birthDate) || !isDate(today) || birthDate > today)
        return -1;
    var years = Number(today.slice(0, 4)) - Number(birthDate.slice(0, 4));
    if (today.slice(5) < birthDate.slice(5))
        years--;
    return years;
}

/// Five heart-rate zones from HRmax = 208 − 0.7 × age (Tanaka 2001), at 50/60/70/80/90/100 %.
function hrZones(years) {
    if (!(years >= 0))
        return [];
    var max = 208 - 0.7 * years;
    var cuts = [0.5, 0.6, 0.7, 0.8, 0.9, 1];
    var out = [];
    for (var z = 0; z < 5; z++)
        out.push({ zone: z + 1, from: Math.round(max * cuts[z]), to: Math.round(max * cuts[z + 1]) });
    return out;
}
