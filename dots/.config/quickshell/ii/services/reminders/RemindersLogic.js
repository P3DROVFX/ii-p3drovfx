.pragma library

// Pure helpers for Reminders: the data shape, repeat rules, when a reminder alerts next,
// the smart lists, search and sort. No QML types in here, so
// scripts/tests/test_reminders_logic.cjs can run it under Node.
//
// A reminder carries the occurrence it is waiting on, not a series: `schedule.date` and
// `schedule.time` are the pending occurrence, and completing a repeating reminder moves
// them to the next one (Samsung Reminder's rule — an unfinished repeat does not advance).

// ── Shape ────────────────────────────────────────────────────────────────────

var DEFAULT_CATEGORY = "default";
var ALERT_LEVELS = ["light", "medium", "strong"];
var REPEAT_UNITS = ["minute", "hour", "day", "week", "month", "year"];
var SMART_LISTS = ["today", "scheduled", "important", "noAlert", "completed"];
var SORT_KEYS = ["alertTime", "modified", "created", "name", "category"];

function makeId(prefix, now) {
    var stamp = Math.floor(Number(now) || Date.now()).toString(36);
    return String(prefix || "r") + "-" + stamp + "-" + Math.random().toString(36).slice(2, 8);
}

function pad(value) {
    var text = String(Math.floor(Math.abs(Number(value) || 0)));
    return text.length < 2 ? "0" + text : text;
}

function dayKey(date) {
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate());
}

function timeKey(date) {
    return pad(date.getHours()) + ":" + pad(date.getMinutes());
}

/** "yyyy-MM-dd" → local midnight, or null. */
function parseDay(text) {
    var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(text || ""));
    if (!match)
        return null;
    var date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    return isNaN(date.getTime()) ? null : date;
}

/** "HH:mm" → [hours, minutes], or null. */
function parseTime(text) {
    var match = /^(\d{1,2}):(\d{2})$/.exec(String(text || ""));
    if (!match)
        return null;
    var hours = Number(match[1]);
    var minutes = Number(match[2]);
    if (hours > 23 || minutes > 59)
        return null;
    return [hours, minutes];
}

function daysInMonth(year, month) {
    return new Date(year, month + 1, 0).getDate();
}

function boolArray7(value) {
    var out = [false, false, false, false, false, false, false];
    if (value && typeof value.length === "number") {
        for (var i = 0; i < 7 && i < value.length; i++)
            out[i] = Boolean(value[i]);
    }
    return out;
}

function toArray(value) {
    if (!value || typeof value.length !== "number" || typeof value === "string")
        return [];
    return Array.prototype.slice.call(value);
}

function normalizeRepeat(value) {
    if (!value || typeof value !== "object")
        return null;
    var unit = REPEAT_UNITS.indexOf(String(value.unit)) >= 0 ? String(value.unit) : "";
    if (!unit)
        return null;
    var end = value.end && typeof value.end === "object" ? value.end : {};
    var kind = ["never", "count", "until"].indexOf(String(end.kind)) >= 0 ? String(end.kind) : "never";
    var monthDays = toArray(value.monthDays).map(Number).filter(function (day) {
        return day >= 1 && day <= 31;
    });
    var yearDates = toArray(value.yearDates).map(String).filter(function (text) {
        return /^\d{2}-\d{2}$/.test(text);
    });
    return {
        unit: unit,
        interval: Math.max(1, Math.min(999, Math.floor(Number(value.interval) || 1))),
        weekdays: boolArray7(value.weekdays),
        monthDays: uniqueSorted(monthDays),
        yearDates: uniqueSorted(yearDates),
        anchor: parseDay(value.anchor) ? String(value.anchor) : "",
        end: {
            kind: kind,
            count: Math.max(1, Math.floor(Number(end.count) || 1)),
            until: parseDay(end.until) ? String(end.until) : ""
        }
    };
}

function uniqueSorted(list) {
    var out = [];
    for (var i = 0; i < list.length; i++) {
        if (out.indexOf(list[i]) < 0)
            out.push(list[i]);
    }
    return out.sort(function (a, b) {
        return a < b ? -1 : a > b ? 1 : 0;
    });
}

function normalizeSchedule(value) {
    if (!value || typeof value !== "object" || !parseDay(value.date))
        return null;
    var repeat = normalizeRepeat(value.repeat);
    if (repeat && !repeat.anchor)
        repeat.anchor = String(value.date);
    return {
        date: String(value.date),
        time: parseTime(value.time) ? String(value.time) : "",
        repeat: repeat,
        occurrence: Math.max(0, Math.floor(Number(value.occurrence) || 0))
    };
}

function normalizeEarly(value) {
    if (!value || typeof value !== "object")
        return null;
    var kind = ["day", "week", "custom"].indexOf(String(value.kind)) >= 0 ? String(value.kind) : "";
    if (!kind)
        return null;
    var at = Math.floor(Number(value.at) || 0);
    if (kind === "custom" && at <= 0)
        return null;
    return { kind: kind, at: kind === "custom" ? at : 0 };
}

function normalizeChecklist(value) {
    return toArray(value).filter(function (item) {
        return item && typeof item === "object";
    }).map(function (item, index) {
        return {
            id: String(item.id || ("c" + index)),
            text: String(item.text || ""),
            done: Boolean(item.done)
        };
    });
}

function normalizeAttachments(value) {
    return toArray(value).filter(function (item) {
        return item && typeof item === "object" && ["image", "file", "link"].indexOf(String(item.kind)) >= 0;
    }).map(function (item, index) {
        return {
            id: String(item.id || ("a" + index)),
            kind: String(item.kind),
            path: String(item.path || ""),
            url: String(item.url || ""),
            name: String(item.name || "")
        };
    }).filter(function (item) {
        return item.kind === "link" ? item.url.length > 0 : item.path.length > 0;
    });
}

function normalizeReminder(value, now) {
    var source = value && typeof value === "object" ? value : {};
    var stamp = Math.floor(Number(now) || Date.now());
    var created = Math.floor(Number(source.createdAt) || stamp);
    var alert = ALERT_LEVELS.indexOf(String(source.alert)) >= 0 ? String(source.alert) : "default";
    var remote = source.remote && typeof source.remote === "object" ? source.remote : null;
    return {
        id: String(source.id || makeId("r", stamp)),
        title: String(source.title || ""),
        notes: String(source.notes || ""),
        categoryId: String(source.categoryId || DEFAULT_CATEGORY),
        important: Boolean(source.important),
        completed: Boolean(source.completed),
        completedAt: Math.floor(Number(source.completedAt) || 0),
        deletedAt: Math.floor(Number(source.deletedAt) || 0),
        createdAt: created,
        modifiedAt: Math.floor(Number(source.modifiedAt) || created),
        checklist: normalizeChecklist(source.checklist),
        attachments: normalizeAttachments(source.attachments),
        schedule: normalizeSchedule(source.schedule),
        alert: alert,
        early: normalizeEarly(source.early),
        snoozedUntil: Math.floor(Number(source.snoozedUntil) || 0),
        firedFor: String(source.firedFor || ""),
        earlyFiredFor: String(source.earlyFiredFor || ""),
        remote: remote ? JSON.parse(JSON.stringify(remote)) : null
    };
}

function normalizeCategory(value, index) {
    var source = value && typeof value === "object" ? value : {};
    var remote = source.remote && typeof source.remote === "object" ? source.remote : null;
    return {
        id: String(source.id || makeId("c")),
        name: String(source.name || ""),
        color: /^#[0-9a-fA-F]{6}$/.test(String(source.color || "")) ? String(source.color) : "",
        icon: String(source.icon || "list"),
        pinned: Boolean(source.pinned),
        order: Number.isFinite(Number(source.order)) ? Number(source.order) : index,
        remote: remote ? JSON.parse(JSON.stringify(remote)) : null
    };
}

/** The whole store as read from disk: always valid, always has the default category. */
function normalizeStore(value, now, defaultName) {
    var source = value && typeof value === "object" ? value : {};
    var categories = toArray(source.categories).map(normalizeCategory);
    if (!categories.some(function (category) { return category.id === DEFAULT_CATEGORY; }))
        categories.unshift(normalizeCategory({ id: DEFAULT_CATEGORY, name: defaultName || "My reminders", icon: "checklist" }, -1));
    var known = {};
    categories.forEach(function (category) { known[category.id] = true; });
    var reminders = toArray(source.reminders).map(function (item) {
        var reminder = normalizeReminder(item, now);
        if (!known[reminder.categoryId])
            reminder.categoryId = DEFAULT_CATEGORY;
        return reminder;
    });
    var tombstones = toArray(source.tombstones).filter(function (item) {
        return item && typeof item === "object";
    }).map(function (item) {
        return { kind: String(item.kind || "task"), listId: String(item.listId || ""), taskId: String(item.taskId || "") };
    });
    return {
        version: 1,
        categories: sortCategories(categories),
        reminders: reminders,
        tombstones: tombstones,
        recent: toArray(source.recent).map(String).filter(function (text) { return text.length > 0; }).slice(0, 30),
        sync: source.sync && typeof source.sync === "object" ? JSON.parse(JSON.stringify(source.sync)) : {}
    };
}

function sortCategories(categories) {
    return categories.slice().sort(function (a, b) {
        if (a.id === DEFAULT_CATEGORY)
            return -1;
        if (b.id === DEFAULT_CATEGORY)
            return 1;
        if (a.pinned !== b.pinned)
            return a.pinned ? -1 : 1;
        return a.order - b.order;
    });
}

// ── When ─────────────────────────────────────────────────────────────────────

/**
 * The moment the pending occurrence is due, as a Date, or null without a schedule.
 * An all-day reminder alerts at `allDayTime` ("HH:mm") on its day.
 */
function dueAt(reminder, allDayTime) {
    var schedule = reminder && reminder.schedule;
    if (!schedule)
        return null;
    var day = parseDay(schedule.date);
    if (!day)
        return null;
    var time = parseTime(schedule.time) || parseTime(allDayTime) || [9, 0];
    return new Date(day.getFullYear(), day.getMonth(), day.getDate(), time[0], time[1]);
}

/** Identifies the pending occurrence, so an alert never fires twice for it. */
function occurrenceKey(reminder) {
    var schedule = reminder && reminder.schedule;
    return schedule ? schedule.date + "T" + (schedule.time || "allday") : "";
}

function earlyAt(reminder, allDayTime) {
    var early = reminder && reminder.early;
    var due = dueAt(reminder, allDayTime);
    if (!early || !due)
        return null;
    if (early.kind === "custom")
        return early.at > 0 && early.at < due.getTime() ? new Date(early.at) : null;
    var days = early.kind === "week" ? 7 : 1;
    var at = new Date(due.getFullYear(), due.getMonth(), due.getDate() - days, due.getHours(), due.getMinutes());
    return at;
}

function isLive(reminder) {
    return Boolean(reminder) && !reminder.deletedAt && !reminder.completed;
}

/**
 * Every alert still to come for one reminder: [{ kind: "main"|"early", at: ms, key }].
 * A snooze replaces the main alert's moment; an alert already fired for this
 * occurrence is left out.
 */
function pendingAlerts(reminder, allDayTime) {
    if (!isLive(reminder) || !reminder.schedule)
        return [];
    var key = occurrenceKey(reminder);
    var out = [];
    if (reminder.snoozedUntil > 0) {
        out.push({ kind: "main", at: reminder.snoozedUntil, key: key });
    } else if (reminder.firedFor !== key) {
        var due = dueAt(reminder, allDayTime);
        if (due)
            out.push({ kind: "main", at: due.getTime(), key: key });
    }
    if (reminder.earlyFiredFor !== key) {
        var early = earlyAt(reminder, allDayTime);
        var main = dueAt(reminder, allDayTime);
        if (early && main && early.getTime() < main.getTime())
            out.push({ kind: "early", at: early.getTime(), key: key });
    }
    return out;
}

/** The earliest alert across the list, or null: { id, kind, at, key }. */
function nextAlert(reminders, allDayTime) {
    var best = null;
    toArray(reminders).forEach(function (reminder) {
        pendingAlerts(reminder, allDayTime).forEach(function (alert) {
            if (!best || alert.at < best.at)
                best = { id: reminder.id, kind: alert.kind, at: alert.at, key: alert.key };
        });
    });
    return best;
}

/** Every alert due at or before `now`: [{ id, kind, at, key }], oldest first. */
function dueAlerts(reminders, now, allDayTime) {
    var out = [];
    toArray(reminders).forEach(function (reminder) {
        pendingAlerts(reminder, allDayTime).forEach(function (alert) {
            if (alert.at <= now)
                out.push({ id: reminder.id, kind: alert.kind, at: alert.at, key: alert.key });
        });
    });
    return out.sort(function (a, b) { return a.at - b.at; });
}

// ── Repeat ───────────────────────────────────────────────────────────────────

function weekStartOf(date, firstDay) {
    var shift = (date.getDay() - firstDay + 7) % 7;
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() - shift);
}

function weeksBetween(a, b) {
    return Math.round((b.getTime() - a.getTime()) / (7 * 86400000));
}

function monthsBetween(a, b) {
    return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
}

/**
 * The occurrence after `schedule`'s current one, as { date, time }, or null once the
 * rule has ended. `firstDay` is the week's first day as Date.getDay() (0 = Sunday), so
 * "every 2 weeks" counts weeks the way the user's calendar draws them.
 */
function nextOccurrence(schedule, firstDay) {
    if (!schedule || !schedule.repeat)
        return null;
    var rule = schedule.repeat;
    var current = parseDay(schedule.date);
    if (!current)
        return null;
    var anchor = parseDay(rule.anchor) || current;
    var time = parseTime(schedule.time);
    var next = null;

    if (rule.unit === "minute" || rule.unit === "hour") {
        var base = new Date(current.getFullYear(), current.getMonth(), current.getDate(),
            time ? time[0] : 0, time ? time[1] : 0);
        var step = rule.interval * (rule.unit === "hour" ? 60 : 1);
        var moved = new Date(base.getTime() + step * 60000);
        next = { date: dayKey(moved), time: time ? timeKey(moved) : "" };
    } else if (rule.unit === "day") {
        var day = new Date(current.getFullYear(), current.getMonth(), current.getDate() + rule.interval);
        next = { date: dayKey(day), time: schedule.time };
    } else if (rule.unit === "week") {
        var weekdays = rule.weekdays.indexOf(true) >= 0 ? rule.weekdays : null;
        var first = Number.isFinite(Number(firstDay)) ? Number(firstDay) : 1;
        var anchorWeek = weekStartOf(anchor, first);
        for (var offset = 1; offset <= 7 * rule.interval + 7; offset++) {
            var candidate = new Date(current.getFullYear(), current.getMonth(), current.getDate() + offset);
            var weekOk = weeksBetween(anchorWeek, weekStartOf(candidate, first)) % rule.interval === 0;
            var dayOk = weekdays ? weekdays[candidate.getDay()] : candidate.getDay() === anchor.getDay();
            if (weekOk && dayOk) {
                next = { date: dayKey(candidate), time: schedule.time };
                break;
            }
        }
    } else if (rule.unit === "month") {
        var days = rule.monthDays.length > 0 ? rule.monthDays : [anchor.getDate()];
        for (var m = 0; m <= 12 * rule.interval && !next; m++) {
            var monthStart = new Date(current.getFullYear(), current.getMonth() + m, 1);
            if (monthsBetween(anchor, monthStart) % rule.interval !== 0)
                continue;
            var length = daysInMonth(monthStart.getFullYear(), monthStart.getMonth());
            // A day past the month's end lands on its last day: "the 31st" still pays rent
            // in February. Clamping can make two days meet, so keep each date once.
            var seen = {};
            for (var d = 0; d < days.length; d++) {
                var dayOfMonth = Math.min(days[d], length);
                if (seen[dayOfMonth])
                    continue;
                seen[dayOfMonth] = true;
                var hit = new Date(monthStart.getFullYear(), monthStart.getMonth(), dayOfMonth);
                if (hit.getTime() > current.getTime()) {
                    next = { date: dayKey(hit), time: schedule.time };
                    break;
                }
            }
        }
    } else if (rule.unit === "year") {
        var dates = rule.yearDates.length > 0 ? rule.yearDates : [pad(anchor.getMonth() + 1) + "-" + pad(anchor.getDate())];
        for (var y = 0; y <= 8 * rule.interval && !next; y++) {
            var year = current.getFullYear() + y;
            if ((year - anchor.getFullYear()) % rule.interval !== 0)
                continue;
            for (var i = 0; i < dates.length; i++) {
                var parts = dates[i].split("-").map(Number);
                var month = parts[0] - 1;
                var dom = Math.min(parts[1], daysInMonth(year, month));
                var when = new Date(year, month, dom);
                if (when.getTime() > current.getTime()) {
                    next = { date: dayKey(when), time: schedule.time };
                    break;
                }
            }
        }
    }

    if (!next)
        return null;
    var done = schedule.occurrence + 1;
    if (rule.end.kind === "count" && done >= rule.end.count)
        return null;
    if (rule.end.kind === "until") {
        var until = parseDay(rule.end.until);
        var nextDay = parseDay(next.date);
        if (until && nextDay && nextDay.getTime() > until.getTime())
            return null;
    }
    return next;
}

/**
 * Completing a reminder: a repeating one moves on to its next occurrence and stays
 * open (its checklist unticks for the new round); anything else is done.
 * Returns the edited copy.
 */
function complete(reminder, now, firstDay) {
    var copy = normalizeReminder(reminder, now);
    copy.modifiedAt = now;
    copy.snoozedUntil = 0;
    var next = copy.schedule ? nextOccurrence(copy.schedule, firstDay) : null;
    if (next) {
        copy.schedule.date = next.date;
        copy.schedule.time = next.time;
        copy.schedule.occurrence += 1;
        copy.firedFor = "";
        copy.earlyFiredFor = "";
        copy.checklist = copy.checklist.map(function (item) {
            return { id: item.id, text: item.text, done: false };
        });
        if (copy.early && copy.early.kind === "custom")
            copy.early = null;
        return copy;
    }
    copy.completed = true;
    copy.completedAt = now;
    return copy;
}

function restore(reminder, now) {
    var copy = normalizeReminder(reminder, now);
    copy.completed = false;
    copy.completedAt = 0;
    copy.deletedAt = 0;
    copy.modifiedAt = now;
    return copy;
}

// ── Lists ────────────────────────────────────────────────────────────────────

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

/** Does the reminder belong to smart list `list` ("today", "scheduled", …)? */
function inSmartList(reminder, list, now) {
    if (!reminder || reminder.deletedAt)
        return false;
    if (list === "completed")
        return reminder.completed;
    if (reminder.completed)
        return false;
    if (list === "important")
        return reminder.important;
    if (list === "noAlert")
        return !reminder.schedule;
    if (list === "scheduled")
        return Boolean(reminder.schedule);
    if (list === "today") {
        var day = reminder.schedule ? parseDay(reminder.schedule.date) : null;
        // Overdue reminders stay in Today until they are dealt with.
        return Boolean(day) && day.getTime() <= startOfDay(now).getTime();
    }
    if (list === "all")
        return true;
    return false;
}

function smartCounts(reminders, now) {
    var counts = { today: 0, scheduled: 0, important: 0, noAlert: 0, completed: 0, all: 0 };
    toArray(reminders).forEach(function (reminder) {
        Object.keys(counts).forEach(function (list) {
            if (inSmartList(reminder, list, now))
                counts[list]++;
        });
    });
    return counts;
}

function categoryCounts(reminders) {
    var counts = {};
    toArray(reminders).forEach(function (reminder) {
        if (!isLive(reminder))
            return;
        counts[reminder.categoryId] = (counts[reminder.categoryId] || 0) + 1;
    });
    return counts;
}

function isOverdue(reminder, now, allDayTime) {
    if (!isLive(reminder))
        return false;
    var due = dueAt(reminder, allDayTime);
    if (!due)
        return false;
    if (!reminder.schedule.time)
        return startOfDay(due).getTime() < startOfDay(now).getTime();
    return due.getTime() < now.getTime();
}

function hasImages(reminder) {
    return reminder.attachments.some(function (item) { return item.kind === "image"; });
}

function hasLinks(reminder) {
    return reminder.attachments.some(function (item) { return item.kind === "link"; });
}

/**
 * Search: every word must appear in the title, notes, checklist or a link. `filters`
 * narrows to reminders with a checklist / images / links; `completed` searches the
 * completed ones instead of the open ones.
 */
function search(reminders, query, filters) {
    var words = String(query || "").toLowerCase().split(/\s+/).filter(function (word) { return word.length > 0; });
    var want = filters || {};
    return toArray(reminders).filter(function (reminder) {
        if (reminder.deletedAt)
            return false;
        if (Boolean(want.completed) !== reminder.completed)
            return false;
        if (want.checklist && reminder.checklist.length === 0)
            return false;
        if (want.images && !hasImages(reminder))
            return false;
        if (want.links && !hasLinks(reminder))
            return false;
        if (words.length === 0)
            return Boolean(want.checklist || want.images || want.links || want.completed);
        var haystack = [reminder.title, reminder.notes].concat(reminder.checklist.map(function (item) {
            return item.text;
        })).concat(reminder.attachments.map(function (item) {
            return item.url || item.name;
        })).join("\n").toLowerCase();
        return words.every(function (word) { return haystack.indexOf(word) >= 0; });
    });
}

/** Past titles that start with (or contain) what is being typed, newest first. */
function suggestions(recent, reminders, text, limit) {
    var needle = String(text || "").trim().toLowerCase();
    if (needle.length === 0)
        return [];
    var pool = toArray(recent).concat(toArray(reminders).map(function (reminder) {
        return reminder.title;
    }));
    var seen = {};
    var starts = [];
    var contains = [];
    pool.forEach(function (title) {
        var key = String(title || "").trim();
        var lower = key.toLowerCase();
        if (!key || seen[lower] || lower === needle)
            return;
        seen[lower] = true;
        if (lower.indexOf(needle) === 0)
            starts.push(key);
        else if (lower.indexOf(needle) > 0)
            contains.push(key);
    });
    return starts.concat(contains).slice(0, limit || 5);
}

/**
 * Sorted copy. Alert time puts the soonest first and unscheduled ones last; the
 * category sort follows the user's category order. `pinImportant` floats starred
 * reminders above the rest without changing their order among themselves.
 */
function sortReminders(reminders, key, pinImportant, categoryOrder, allDayTime) {
    var order = categoryOrder || {};
    var list = toArray(reminders).slice();
    var byTitle = function (a, b) {
        return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : a.title.toLowerCase() > b.title.toLowerCase() ? 1 : 0;
    };
    var compare;
    if (key === "modified") {
        compare = function (a, b) { return b.modifiedAt - a.modifiedAt; };
    } else if (key === "created") {
        compare = function (a, b) { return b.createdAt - a.createdAt; };
    } else if (key === "name") {
        compare = byTitle;
    } else if (key === "category") {
        compare = function (a, b) {
            var diff = (order[a.categoryId] || 0) - (order[b.categoryId] || 0);
            return diff !== 0 ? diff : byTitle(a, b);
        };
    } else if (key === "completed") {
        compare = function (a, b) { return b.completedAt - a.completedAt; };
    } else {
        compare = function (a, b) {
            var ta = dueAt(a, allDayTime);
            var tb = dueAt(b, allDayTime);
            if (ta && tb && ta.getTime() !== tb.getTime())
                return ta.getTime() - tb.getTime();
            if (ta && !tb)
                return -1;
            if (!ta && tb)
                return 1;
            return b.createdAt - a.createdAt;
        };
    }
    list.sort(function (a, b) {
        if (pinImportant && a.important !== b.important)
            return a.important ? -1 : 1;
        return compare(a, b);
    });
    return list;
}

/**
 * Groups for a dated list: Overdue, Today, Tomorrow, This week, Later, No date.
 * [{ key, reminders }] in that order, empty groups dropped.
 */
function groupByDay(reminders, now, allDayTime) {
    var today = startOfDay(now).getTime();
    var day = 86400000;
    var groups = { overdue: [], today: [], tomorrow: [], week: [], later: [], none: [] };
    toArray(reminders).forEach(function (reminder) {
        var due = dueAt(reminder, allDayTime);
        if (!due) {
            groups.none.push(reminder);
            return;
        }
        var start = startOfDay(due).getTime();
        if (isOverdue(reminder, now, allDayTime))
            groups.overdue.push(reminder);
        else if (start === today)
            groups.today.push(reminder);
        else if (start === today + day)
            groups.tomorrow.push(reminder);
        else if (start < today + 7 * day)
            groups.week.push(reminder);
        else
            groups.later.push(reminder);
    });
    return ["overdue", "today", "tomorrow", "week", "later", "none"].filter(function (key) {
        return groups[key].length > 0;
    }).map(function (key) {
        return { key: key, reminders: groups[key] };
    });
}

/** Reminders whose pending occurrence falls on [from, to) — for the timetable. */
function inRange(reminders, from, to, allDayTime) {
    return toArray(reminders).filter(function (reminder) {
        if (reminder.deletedAt || !reminder.schedule)
            return false;
        var due = dueAt(reminder, allDayTime);
        return due && due.getTime() >= from && due.getTime() < to;
    });
}

/** Recycle-bin and completed clean-up: the ids to drop for good. */
function expired(reminders, now, trashDays, completedDays) {
    var day = 86400000;
    return toArray(reminders).filter(function (reminder) {
        if (reminder.deletedAt > 0)
            return trashDays > 0 && now - reminder.deletedAt >= trashDays * day;
        if (reminder.completed)
            return completedDays > 0 && reminder.completedAt > 0 && now - reminder.completedAt >= completedDays * day;
        return false;
    }).map(function (reminder) { return reminder.id; });
}

// ── Templates ────────────────────────────────────────────────────────────────

/**
 * "Try these out": drafts pre-filled the way Samsung Reminder's templates are. Titles
 * come in through `labels` so they stay translatable on the QML side.
 */
function templateDraft(id, now, labels) {
    var text = labels || {};
    var today = startOfDay(now);
    var tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
    var nextOfDay = function (weekday) {
        var shift = (weekday - today.getDay() + 7) % 7 || 7;
        return new Date(today.getFullYear(), today.getMonth(), today.getDate() + shift);
    };
    if (id === "workout") {
        var start = nextOfDay(today.getDay() <= 2 ? 2 : 4);
        return {
            title: text.workout || "Workout",
            schedule: {
                date: dayKey(start), time: "18:00",
                repeat: { unit: "week", interval: 1, weekdays: [false, false, true, false, true, false, false], end: { kind: "never" } }
            }
        };
    }
    if (id === "payment") {
        var due = new Date(today.getFullYear(), today.getMonth() + (today.getDate() > 1 ? 1 : 0), 1);
        return {
            title: text.payment || "Pay the bills",
            important: true,
            schedule: { date: dayKey(due), time: "10:00", repeat: { unit: "month", interval: 1, monthDays: [1], end: { kind: "never" } } }
        };
    }
    if (id === "pickup") {
        return { title: text.pickup || "Pick up", schedule: { date: dayKey(tomorrow), time: "17:00", repeat: null } };
    }
    if (id === "home") {
        return { title: text.home || "When I get home", schedule: { date: dayKey(today), time: "19:00", repeat: null } };
    }
    if (id === "grocery") {
        var items = toArray(text.groceryItems);
        return {
            title: text.grocery || "Grocery list",
            checklist: items.map(function (item, index) {
                return { id: "c" + index, text: String(item), done: false };
            })
        };
    }
    return null;
}
