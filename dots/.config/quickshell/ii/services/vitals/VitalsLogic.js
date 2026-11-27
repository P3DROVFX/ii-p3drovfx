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
        // _setIndex swaps the index and its dates one after the other; a binding woken
        // between the two sees dates the index no longer has.
        if (!s)
            continue;
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

// ── Assistant ───────────────────────────────────────────────────────────
// What the read-only assistant tools return: aggregates only. Age instead of the birth
// date, no route points and no exercise ids, no per-minute bins (hours at most), times as
// local "HH:MM".

function _r(v, decimals) {
    var f = Math.pow(10, decimals || 0);
    return Math.round(v * f) / f;
}

function _clock(ms) {
    var d = new Date(ms);
    return (d.getHours() < 10 ? "0" : "") + d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes();
}

function _inRange(date, fromDate, toDate) {
    return !(fromDate && date < fromDate) && !(toDate && date > toDate);
}

/// The profile without the birth date: {age?, sex?, heightCm?, weightKg?}.
function profileDigest(meta, today) {
    var p = (meta && meta.profile) || {};
    var out = {};
    var years = age(p.birthDate || "", today);
    if (years >= 0)
        out.age = years;
    if (typeof p.sex === "string")
        out.sex = p.sex;
    if (num(p.heightCm))
        out.heightCm = p.heightCm;
    if (num(p.weightKg))
        out.weightKg = p.weightKg;
    return out;
}

/// A measurement entry with its time as "HH:MM".
function _measure(entry) {
    var out = {};
    for (var f in entry)
        out[f] = f === "time" ? _clock(entry.time) : (num(entry[f]) ? _r(entry[f], 2) : entry[f]);
    return out;
}

/// Mean per hour of the day (24 entries, null without data) of [minute, value] bins.
function hourlyMeans(bins) {
    var sum = [], n = [], out = [];
    for (var h = 0; h < 24; h++) {
        sum.push(0);
        n.push(0);
    }
    for (var i = 0; i < (bins || []).length; i++) {
        var hour = Math.floor(bins[i][0] / 60);
        if (hour >= 0 && hour < 24 && num(bins[i][1])) {
            sum[hour] += bins[i][1];
            n[hour]++;
        }
    }
    for (h = 0; h < 24; h++)
        out.push(n[h] > 0 ? _r(sum[h] / n[h], 1) : null);
    return out;
}

/// Minutes per stage of a night's [offsetMin, durMin, stage] list.
function stageMinutes(stages) {
    var out = {};
    for (var i = 0; i < (stages || []).length; i++)
        out[stages[i][2]] = (out[stages[i][2]] || 0) + stages[i][1];
    return out;
}

/// One day: from its Summary, plus hours, stages and workouts when its Day is loaded.
function dayDigest(date, summary, day) {
    if (!summary)
        return null;
    var out = { date: date }, k;
    if (Object.keys(summary.t || {}).length > 0) {
        out.totals = {};
        for (k in summary.t)
            out.totals[k] = _r(summary.t[k], 1);
    }
    if (Object.keys(summary.s || {}).length > 0) {
        out.samples = {};
        for (k in summary.s)
            out.samples[k] = { min: _r(summary.s[k][0], 1), avg: _r(summary.s[k][1], 1), max: _r(summary.s[k][2], 1) };
    }
    if (summary.sleep) {
        out.sleep = { start: _clock(summary.sleep.start), end: _clock(summary.sleep.end), minutes: summary.sleep.min };
        if (num(summary.sleep.score))
            out.sleep.score = summary.sleep.score;
    }
    if (summary.n && summary.n.exercise > 0)
        out.exercise = { sessions: summary.n.exercise, minutes: summary.exMin };
    if (Object.keys(summary.m || {}).length > 0) {
        out.measurements = {};
        for (k in summary.m)
            out.measurements[k] = _measure(summary.m[k]);
    }
    if (Object.keys(summary.sc || {}).length > 0)
        out.scores = summary.sc;
    if (!day)
        return out;

    var steps = day.totals && day.totals.steps;
    if (steps && Array.isArray(steps.hourly))
        out.stepsByHour = steps.hourly;
    var hr = day.samples && day.samples.heartRate;
    if (hr && Array.isArray(hr.bins))
        out.heartRateByHour = hourlyMeans(hr.bins);
    var night = mainSleep(day);
    if (out.sleep && night && Array.isArray(night.stages) && night.stages.length > 0)
        out.sleep.stageMinutes = stageMinutes(night.stages);
    var ex = (day.sessions && day.sessions.exercise) || [];
    if (ex.length > 0) {
        out.workouts = [];
        var fields = ["kcal", "distanceM", "steps", "hrAvg", "hrMax", "hrMin", "elevationM", "speedAvgMps"];
        for (var i = 0; i < ex.length; i++) {
            var w = { type: ex[i].type, start: _clock(ex[i].start), minutes: Math.round((ex[i].end - ex[i].start) / 60000) };
            if (typeof ex[i].title === "string")
                w.title = ex[i].title;
            for (var f = 0; f < fields.length; f++)
                if (num(ex[i][fields[f]]))
                    w[fields[f]] = _r(ex[i][fields[f]], 1);
            out.workouts.push(w);
        }
    }
    for (k in (day.sessions || {})) {
        if (k === "sleep" || k === "exercise")
            continue;
        var list = day.sessions[k], ms = 0;
        for (var j = 0; j < list.length; j++)
            ms += list[j].end - list[j].start;
        out.sessions = out.sessions || {};
        out.sessions[k] = { count: list.length, minutes: Math.round(ms / 60000) };
    }
    return out;
}

/// A date range at a glance: per key the total/mean/extremes over the days that have it.
function rangeDigest(index, dates, fromDate, toDate) {
    var ds = dates.filter(function (d) { return _inRange(d, fromDate, toDate); });
    var out = { from: fromDate, to: toDate, daysWithData: ds.length };
    var totals = {}, samples = {}, scores = {}, measurements = {};
    var nights = [], exSessions = 0, exMinutes = 0, k;
    for (var i = 0; i < ds.length; i++) {
        var s = index[ds[i]];
        for (k in (s.t || {})) {
            var t = totals[k] || (totals[k] = { total: 0, days: 0, best: null });
            t.total += s.t[k];
            t.days++;
            if (t.best === null || s.t[k] > t.best.value)
                t.best = { date: ds[i], value: _r(s.t[k], 1) };
        }
        for (k in (s.s || {})) {
            var m = samples[k] || (samples[k] = { sum: 0, days: 0, min: s.s[k][0], max: s.s[k][2] });
            m.sum += s.s[k][1];
            m.days++;
            m.min = Math.min(m.min, s.s[k][0]);
            m.max = Math.max(m.max, s.s[k][2]);
        }
        for (k in (s.sc || {})) {
            var c = scores[k] || (scores[k] = { sum: 0, days: 0, min: s.sc[k], max: s.sc[k] });
            c.sum += s.sc[k];
            c.days++;
            c.min = Math.min(c.min, s.sc[k]);
            c.max = Math.max(c.max, s.sc[k]);
        }
        for (k in (s.m || {})) {
            if (!measurements[k])
                measurements[k] = { first: _measure(s.m[k]), firstDate: ds[i] };
            measurements[k].last = _measure(s.m[k]);
            measurements[k].lastDate = ds[i];
        }
        if (s.sleep)
            nights.push(s.sleep);
        if (s.n && s.n.exercise > 0) {
            exSessions += s.n.exercise;
            exMinutes += s.exMin;
        }
    }
    out.totals = {};
    for (k in totals)
        out.totals[k] = { total: _r(totals[k].total, 1), perDay: _r(totals[k].total / totals[k].days, 1), days: totals[k].days, best: totals[k].best };
    out.samples = {};
    for (k in samples)
        out.samples[k] = { avg: _r(samples[k].sum / samples[k].days, 1), min: _r(samples[k].min, 1), max: _r(samples[k].max, 1), days: samples[k].days };
    out.scores = {};
    for (k in scores)
        out.scores[k] = { avg: _r(scores[k].sum / scores[k].days, 1), min: scores[k].min, max: scores[k].max, days: scores[k].days };
    out.measurements = measurements;
    if (nights.length > 0) {
        var mins = nights.map(function (n) { return n.min; });
        var scored = nights.filter(function (n) { return num(n.score); });
        out.sleep = {
            nights: nights.length,
            avgMinutes: Math.round(mins.reduce(function (a, b) { return a + b; }, 0) / mins.length),
            minMinutes: Math.min.apply(null, mins),
            maxMinutes: Math.max.apply(null, mins)
        };
        if (scored.length > 0)
            out.sleep.avgScore = _r(scored.reduce(function (a, n) { return a + n.score; }, 0) / scored.length, 1);
    }
    out.exercise = { sessions: exSessions, minutes: exMinutes };
    return out;
}

/// One value per day of `key` (as series()), as weekly means past 62 days so a long
/// range stays short, with the overall mean and extremes.
function trendDigest(index, dates, key, fromDate, toDate) {
    var pts = series(index, dates, key, fromDate, toDate);
    var out = { key: key, from: fromDate, to: toDate, days: pts.length };
    if (pts.length === 0)
        return out;
    var vals = pts.map(function (p) { return p.value; });
    out.mean = _r(vals.reduce(function (a, b) { return a + b; }, 0) / vals.length, 1);
    out.min = _r(Math.min.apply(null, vals), 1);
    out.max = _r(Math.max.apply(null, vals), 1);
    if (pts.length <= 62) {
        out.points = pts.map(function (p) { return [p.date, _r(p.value, 1)]; });
        return out;
    }
    // Weeks counted from the first day of the range that has data.
    out.weekly = [];
    var start = pts[0].date, sum = 0, n = 0;
    for (var i = 0; i <= pts.length; i++) {
        var p = pts[i];
        if (n > 0 && (p === undefined || daysBetween(start, p.date) >= 7)) {
            out.weekly.push([start, _r(sum / n, 1)]);
            start = p ? addDays(start, Math.floor(daysBetween(start, p.date) / 7) * 7) : start;
            sum = 0;
            n = 0;
        }
        if (p !== undefined) {
            sum += p.value;
            n++;
        }
    }
    return out;
}
