.pragma library

// What the calendar widget shows, from CalendarService's event list
// ({ content, startDate, endDate, allDay, color, location, ... }). Pure, so the
// rules are tested without the service.

function _date(value) {
    if (value instanceof Date)
        return value;
    var d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
}

function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function _normalized(events) {
    var out = [];
    var list = events || [];
    for (var i = 0; i < list.length; i++) {
        var e = list[i];
        if (!e)
            continue;
        var start = _date(e.startDate);
        if (!start)
            continue;
        var end = _date(e.endDate) || start;
        if (end < start)
            end = start;
        out.push({ event: e, start: start, end: end, allDay: e.allDay === true });
    }
    out.sort(function (a, b) {
        if (a.allDay !== b.allDay)
            return a.allDay ? -1 : 1;
        return a.start - b.start;
    });
    return out;
}

// Events touching the given day: all-day first, then by start.
function dayEvents(events, day) {
    var from = startOfDay(day);
    var to = new Date(from.getFullYear(), from.getMonth(), from.getDate() + 1);
    return _normalized(events).filter(function (item) {
        // An all-day event's end is exclusive midnight; a timed one ending at
        // midnight does not reach into the next day either.
        return item.start < to && (item.end > from || (item.end.getTime() === item.start.getTime() && item.start >= from));
    });
}

// Timed events not over yet, starting within `days` days, soonest first.
// All-day events are left out: they are the day itself, not "what's next".
function upcoming(events, now, limit, days) {
    var horizon = new Date(now.getTime() + (days || 7) * 86400000);
    var out = _normalized(events).filter(function (item) {
        return !item.allDay && item.end > now && item.start < horizon;
    });
    out.sort(function (a, b) { return a.start - b.start; });
    return limit > 0 ? out.slice(0, limit) : out;
}

function isHappening(item, now) {
    return item.start <= now && item.end > now;
}

// "now", "in 25 min", "in 3 h", "tomorrow" — how far an event is.
function relative(item, now, tr) {
    var t = tr || function (s) { return s; };
    if (isHappening(item, now))
        return t("Now");
    var minutes = Math.round((item.start - now) / 60000);
    if (minutes < 60)
        return t("In %1 min").replace("%1", String(Math.max(1, minutes)));
    if (sameDay(item.start, now))
        return t("In %1 h").replace("%1", String(Math.round(minutes / 60)));
    var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    if (sameDay(item.start, tomorrow))
        return t("Tomorrow");
    return "";
}

// The next few days with something on them, for the panel.
function nextDays(events, now, count) {
    var out = [];
    for (var i = 1; i <= count; i++) {
        var day = new Date(now.getFullYear(), now.getMonth(), now.getDate() + i);
        var list = dayEvents(events, day);
        if (list.length > 0)
            out.push({ day: day, events: list });
    }
    return out;
}
