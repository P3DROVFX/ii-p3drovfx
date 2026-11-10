// Pure helpers for the timetable sports schedule cache.
//
// They live in a plain `.js` module so node can exercise them outside the QML
// engine: `scripts/calendar/tests/test_timetable_sports_cache_helpers.py` pins
// the ESPN query granularity, the change detection that keeps the calendar
// views from rebuilding themselves, and the input signature that lets a
// fruitless rebuild be skipped. The service passes its own `dayKey` in, so
// nothing here depends on Qt.

// ESPN's scoreboard answers a whole month (`dates=202609`) but rejects a
// `from-to` range (`dates=20260830-20261003`) with HTTP 400, so a range is
// requested one month at a time and merged into the same cache entry.
// Returns `YYYYMM` keys, oldest first, for every month the range touches.
function espnMonths(fromKey, toKey) {
    const months = [];
    const from = new Date(fromKey + "T00:00:00");
    const to = new Date(toKey + "T00:00:00");
    if (isNaN(from.getTime()) || isNaN(to.getTime()) || to.getTime() < from.getTime())
        return months;
    const cursor = new Date(from.getFullYear(), from.getMonth(), 1);
    while (cursor.getTime() <= to.getTime() && months.length < 24) {
        months.push(String(cursor.getFullYear()) + (cursor.getMonth() < 9 ? "0" : "") + String(cursor.getMonth() + 1));
        cursor.setMonth(cursor.getMonth() + 1);
    }
    return months;
}

// Which month a request is currently fetching, clamped to the list.
function monthForIndex(months, index) {
    if (!Array.isArray(months) || months.length === 0)
        return "";
    return months[Math.max(0, Math.min(Number(index ?? 0), months.length - 1))];
}

// The fields a calendar view actually reads from a game DTO. `content` carries
// the score and `status` the live minute, so a score or a minute change still
// reaches the views; nothing else about a game is rendered.
function sameGame(left, right) {
    return String(left?.id ?? "") === String(right?.id ?? "")
        && String(left?.content ?? "") === String(right?.content ?? "")
        && String(left?.state ?? "") === String(right?.state ?? "")
        && String(left?.status ?? "") === String(right?.status ?? "")
        && String(left?.start ?? "") === String(right?.start ?? "");
}

function sameGames(previous, next) {
    if (!Array.isArray(previous) || previous.length !== next.length)
        return false;
    for (let i = 0; i < next.length; i++) {
        if (!sameGame(previous[i], next[i]))
            return false;
    }
    return true;
}

// Groups games by day, reusing the previous array for a day whose games did not
// change: the month cell derives its whole entry list from that array, and a
// new identity there rebuilds every chip delegate of the cell.
function gamesByDay(games, dayKeyOf, previous) {
    const before = previous ?? ({});
    const next = ({});
    for (let i = 0; i < games.length; i++) {
        const key = dayKeyOf(games[i]?.startDate);
        if (String(key ?? "").length === 0)
            continue;
        if (!next[key])
            next[key] = [];
        next[key].push(games[i]);
    }
    for (const key in next) {
        if (before[key] && sameGames(before[key], next[key]))
            next[key] = before[key];
    }
    return next;
}

// A signature of everything the projection depends on, so a rebuild triggered
// by something that changed none of it (a failed fetch, a repeated range
// request) can be skipped instead of republishing the whole grid.
function sourceSignature(rangeStart, rangeEnd, teamFilter, sources) {
    const list = sources ?? [];
    const parts = [String(rangeStart ?? ""), String(rangeEnd ?? ""), String(teamFilter ?? ""), String(list.length)];
    for (let i = 0; i < list.length; i++) {
        const source = list[i];
        parts.push(String(source?.key ?? "") + "|" + String(Number(source?.cached?.fetchedAt ?? 0)) + "|" + String((source?.events ?? []).length));
    }
    return parts.join("~");
}

if (typeof module !== "undefined") {
    module.exports = {
        espnMonths,
        monthForIndex,
        sameGame,
        sameGames,
        gamesByDay,
        sourceSignature
    };
}