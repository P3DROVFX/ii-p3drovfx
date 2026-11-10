.pragma library

// Pure policy for the dock's overflow group.
//
// Widgets, actions and pinned launchers can leave the tray too little room for
// the apps that keep opening. Instead of letting the row run past the tray and
// clip, the launchers the user is least likely to want are folded into one
// ephemeral app group. Nothing here touches dock.order or dock.appGroups: the
// fold is recomputed from the current model each time, so it undoes itself as
// soon as there is room again.
//
// Like DockReorder.js, this is free of QML so tests/dock/ can cover it.

// Launchers that can be folded, least wanted first:
//   1. running apps that are not pinned, least recently used first;
//   2. pinned apps with no window, from the end of the dock;
//   3. pinned apps with windows, least recently used first.
// `recencyOf(item)` returns a timestamp (0 = unknown); ties keep the later
// item in the dock, which is where newly opened apps land.
function foldPriority(items, recencyOf) {
    var running = [];
    var idle = [];
    var pinnedRunning = [];
    for (var i = 0; i < items.length; i++) {
        var item = items[i];
        if (!item || item.type !== "app")
            continue;
        var data = item.appData || {};
        var hasWindows = !!(data.toplevels && data.toplevels.length > 0);
        var entry = { key: String(item.orderKey), index: i, recency: Number(recencyOf(item)) || 0 };
        if (!data.pinned)
            running.push(entry);
        else if (!hasWindows)
            idle.push(entry);
        else
            pinnedRunning.push(entry);
    }
    var byRecency = function (a, b) { return a.recency !== b.recency ? a.recency - b.recency : a.index - b.index; };
    running.sort(byRecency);
    pinnedRunning.sort(byRecency);
    idle.sort(function (a, b) { return b.index - a.index; });
    return running.concat(idle, pinnedRunning).map(function (entry) { return entry.key; });
}

function isLauncher(item) {
    return !!item && (item.type === "app" || item.type === "appGroup");
}

// `items` without the folded keys, with `group` right after the last launcher
// still on the dock (or where the first folded one was, when none is left).
function withFolded(items, foldedKeys, group) {
    var folded = {};
    for (var k = 0; k < foldedKeys.length; k++)
        folded[foldedKeys[k]] = true;

    var result = [];
    var firstFoldedAt = -1;
    for (var i = 0; i < items.length; i++) {
        if (folded[String(items[i].orderKey)]) {
            if (firstFoldedAt < 0)
                firstFoldedAt = result.length;
            continue;
        }
        result.push(items[i]);
    }

    var insertAt = -1;
    for (var j = result.length - 1; j >= 0; j--) {
        if (isLauncher(result[j])) {
            insertAt = j + 1;
            break;
        }
    }
    if (insertAt < 0)
        insertAt = firstFoldedAt < 0 ? result.length : firstFoldedAt;
    result.splice(insertAt, 0, group);
    return result;
}

// options:
//   budget    main-axis room the tray has (<= 0 = unknown, never fold)
//   measure   function(items) -> estimated main-axis extent of that row
//   recencyOf function(item) -> last-used timestamp
//   makeGroup function(foldedItems) -> the group item
// Returns { items, foldedKeys }. A fold always takes at least two launchers —
// a group of one saves nothing.
function fold(items, options) {
    var none = { items: items, foldedKeys: [] };
    var budget = Number(options.budget);
    if (!items || items.length === 0 || !(budget > 0) || options.measure(items) <= budget)
        return none;

    var priority = foldPriority(items, options.recencyOf);
    if (priority.length < 2)
        return none;

    var build = function (keys) {
        // Members in dock order, so the tile reads like the row it replaced.
        var members = items.filter(function (item) { return keys.indexOf(String(item.orderKey)) >= 0; });
        return withFolded(items, keys, options.makeGroup(members));
    };

    var keys = [];
    var next = items;
    for (var p = 0; p < priority.length; p++) {
        keys.push(priority[p]);
        if (keys.length < 2)
            continue;
        next = build(keys);
        if (options.measure(next) <= budget)
            break;
    }
    return { items: next, foldedKeys: keys };
}
