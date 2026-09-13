.pragma library

// Pure geometry and policy for the dock's drag-to-reorder gesture.
//
// Everything here is deliberately free of QML: the dock content item is a very
// large component that cannot be instantiated in a test, so the decisions that
// used to be tangled into it — which slot a pointer is over, when a drag turns
// into a grouping gesture, how smart grouping and manual placement coexist —
// live in this library instead and are covered by tests/dock/.
//
// A "slot" is one item's untransformed layout box on the dock's main axis:
// { start, end }. The caller snapshots the whole table once when the drag
// starts, so preview translations and items appearing behind the pointer can
// never move the target out from under the gesture.

function finiteOr(value, fallback) {
    var number = Number(value);
    return isFinite(number) ? number : fallback;
}

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

// QML list<string> properties reach JavaScript as array-likes rather than real
// Arrays, so every list crossing that boundary is normalised here.
function toStringArray(value) {
    if (value === null || value === undefined)
        return [];
    var result = [];
    if (typeof value.length !== "number")
        return result;
    for (var i = 0; i < value.length; i++)
        result.push(String(value[i]));
    return result;
}

function slotExtent(slot) {
    if (!slot)
        return 0;
    return Math.max(0, finiteOr(slot.end, 0) - finiteOr(slot.start, 0));
}

function slotCenter(slot) {
    if (!slot)
        return 0;
    return finiteOr(slot.start, 0) + slotExtent(slot) / 2;
}

// ---------------------------------------------------------------------------
// Drag state
// ---------------------------------------------------------------------------

function createDragState() {
    return resetDragState({});
}

function resetDragState(state) {
    var target = state || {};
    target.targetIndex = -1;
    target.groupIndex = -1;
    target.groupSince = 0;
    target.groupArmed = false;
    return target;
}

// ---------------------------------------------------------------------------
// Which slot is the pointer over
// ---------------------------------------------------------------------------

// Index of the slot containing `pointer`, or -1 when the pointer sits in a gap
// or past either end. Slots are assumed sorted by start.
function slotIndexAt(slots, pointer) {
    var list = slots || [];
    var position = finiteOr(pointer, 0);
    for (var i = 0; i < list.length; i++) {
        if (!list[i])
            continue;
        if (position >= finiteOr(list[i].start, 0) && position <= finiteOr(list[i].end, 0))
            return i;
    }
    return -1;
}

// Same, but never gives up: a pointer in a gap or beyond the ends resolves to
// the closest slot. Reordering must keep working while the pointer travels
// through the spacing between two icons.
function nearestSlotIndex(slots, pointer) {
    var list = slots || [];
    if (list.length === 0)
        return -1;
    var exact = slotIndexAt(list, pointer);
    if (exact >= 0)
        return exact;

    var position = finiteOr(pointer, 0);
    var bestIndex = -1;
    var bestDistance = Infinity;
    for (var i = 0; i < list.length; i++) {
        if (!list[i])
            continue;
        var start = finiteOr(list[i].start, 0);
        var end = finiteOr(list[i].end, 0);
        var distance = position < start ? start - position : (position > end ? position - end : 0);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = i;
        }
    }
    return bestIndex;
}

// ---------------------------------------------------------------------------
// Drop index
// ---------------------------------------------------------------------------

// Resolve the index the dragged item should land on.
//
// The rule is positional, not cumulative: whichever slot the pointer is over
// wins, so the target can never drift away from what the user sees. Taking a
// neighbour over requires penetrating its slot by `hysteresis` of that slot's
// own extent, which keeps a pointer resting on a boundary from flipping the
// dock back and forth and scales correctly for a 4-slot widget sitting next to
// a 1-slot icon.
//
// `state.targetIndex` carries the previous decision and is updated in place.
function resolveDropIndex(slots, pointer, sourceIndex, state, options) {
    var list = slots || [];
    var config = options || {};
    var result = { index: sourceIndex, changed: false, hovered: -1 };
    if (list.length === 0)
        return result;

    var position = finiteOr(pointer, 0);
    var previous = state && state.targetIndex >= 0 && state.targetIndex < list.length
        ? state.targetIndex
        : clamp(finiteOr(sourceIndex, 0), 0, list.length - 1);
    var candidate = nearestSlotIndex(list, position);
    result.hovered = candidate;
    if (candidate < 0) {
        result.index = previous;
        return result;
    }

    var hysteresis = clamp(finiteOr(config.hysteresis, 0.25), 0, 0.49);
    if (candidate !== previous && hysteresis > 0) {
        var slot = list[candidate];
        var extent = slotExtent(slot);
        var margin = extent * hysteresis;
        // Zero-extent slots (an item mid-exit) can never be a target.
        if (extent <= 0) {
            result.index = previous;
            return result;
        }
        if (candidate > previous && position < finiteOr(slot.start, 0) + margin)
            candidate = previous;
        else if (candidate < previous && position > finiteOr(slot.end, 0) - margin)
            candidate = previous;
    }

    result.index = candidate;
    result.changed = candidate !== previous;
    if (state)
        state.targetIndex = candidate;
    return result;
}

// Pixel offset a non-dragged item takes while the reorder is previewed.
//
// Reinserting the dragged item pushes the whole run between the old and the new
// position by exactly one footprint — the dragged item's own extent plus the
// spacing it used. Measuring that from the slot table is what lets a 4-slot
// widget displace its neighbours correctly; the old code shifted everything by
// one guessed icon width, so the preview never matched the drop.
function previewShift(slots, sourceIndex, targetIndex, index, spacing) {
    var list = slots || [];
    var source = finiteOr(sourceIndex, -1);
    var target = finiteOr(targetIndex, -1);
    if (source < 0 || target < 0 || source === target)
        return 0;
    if (index === source || index < 0 || index >= list.length)
        return 0;
    if (!list[source])
        return 0;

    // Spacing is allowed to be negative: the dock lets icons overlap.
    var step = slotExtent(list[source]) + finiteOr(spacing, 0);
    if (source < target)
        return (index > source && index <= target) ? -step : 0;
    return (index >= target && index < source) ? step : 0;
}

// ---------------------------------------------------------------------------
// Grouping intent
// ---------------------------------------------------------------------------

// Decide whether the gesture is asking to drop one app onto another to group
// them, rather than to reorder.
//
// Two conditions, both of which the old whole-slot test lacked:
//   * the pointer must be inside the middle `centerZone` of the target, so
//     sliding past an icon to reach the far side of the dock stays a reorder;
//   * it must stay there for `dwellMs`, so grouping is a deliberate hold and
//     never something a fast pass-through triggers by accident.
//
// `groupable[i]` is supplied by the caller (it depends on item types and on the
// dragged item, both fixed for the whole gesture). Returns the armed target or
// -1, and the progress towards arming so the UI can show the intent building.
function resolveGroupIntent(slots, pointer, sourceIndex, groupable, state, options) {
    var list = slots || [];
    var config = options || {};
    var flags = groupable || [];
    var now = finiteOr(config.now, 0);
    var result = { index: -1, armed: false, candidate: -1, progress: 0 };

    if (!config.enabled) {
        if (state) {
            state.groupIndex = -1;
            state.groupArmed = false;
        }
        return result;
    }

    var centerZone = clamp(finiteOr(config.centerZone, 0.5), 0.05, 1);
    var dwellMs = Math.max(0, finiteOr(config.dwellMs, 180));
    var candidate = slotIndexAt(list, finiteOr(pointer, 0));

    if (candidate >= 0 && (candidate === sourceIndex || flags[candidate] !== true))
        candidate = -1;

    if (candidate >= 0) {
        // Only the middle of an icon means "onto this one".
        var slot = list[candidate];
        var half = slotExtent(slot) * centerZone / 2;
        var center = slotCenter(slot);
        var position = finiteOr(pointer, 0);
        if (half <= 0 || position < center - half || position > center + half)
            candidate = -1;
    }

    if (!state) {
        result.candidate = candidate;
        result.armed = candidate >= 0 && dwellMs === 0;
        result.index = result.armed ? candidate : -1;
        result.progress = result.armed ? 1 : 0;
        return result;
    }

    if (candidate !== state.groupIndex) {
        state.groupIndex = candidate;
        state.groupSince = now;
        state.groupArmed = candidate >= 0 && dwellMs === 0;
    } else if (candidate >= 0 && !state.groupArmed && now - state.groupSince >= dwellMs) {
        state.groupArmed = true;
    }

    result.candidate = candidate;
    result.armed = state.groupArmed && candidate >= 0;
    result.index = result.armed ? candidate : -1;
    result.progress = candidate < 0
        ? 0
        : (dwellMs === 0 ? 1 : clamp((now - state.groupSince) / dwellMs, 0, 1));
    return result;
}

// ---------------------------------------------------------------------------
// Smart grouping
// ---------------------------------------------------------------------------

// Sort items into category runs, but treat every manually placed item as an
// anchor that keeps the exact slot the user dropped it on.
//
// Smart grouping used to sort the whole dock unconditionally, which quietly
// undid every drag: a widget is alone in its category, so it always snapped
// straight back and repositioning looked broken. Anchors make the two features
// coexist — what you have not touched is auto-arranged, what you have dragged
// stays put.
function applySmartGrouping(items, categories, manualKeys) {
    var source = items || [];
    if (source.length < 2)
        return source.slice();

    var anchored = {};
    var keys = toStringArray(manualKeys);
    for (var k = 0; k < keys.length; k++)
        anchored[keys[k]] = true;

    var slots = new Array(source.length);
    var free = [];
    for (var i = 0; i < source.length; i++) {
        var item = source[i];
        var orderKey = item ? String(item.orderKey ?? "") : "";
        if (orderKey !== "" && anchored[orderKey] === true) {
            slots[i] = item;
            continue;
        }
        slots[i] = null;
        free.push({
            index: i,
            value: item,
            category: finiteOr(categories ? categories[i] : 0, 0)
        });
    }

    free.sort(function (a, b) {
        if (a.category !== b.category)
            return a.category - b.category;
        return a.index - b.index;
    });

    var cursor = 0;
    for (var slotIndex = 0; slotIndex < slots.length; slotIndex++) {
        if (slots[slotIndex] === null)
            slots[slotIndex] = free[cursor++].value;
    }
    return slots;
}

// Keys that no longer name an item in the dock are dropped, so anchors cannot
// pile up forever as apps are unpinned and groups dissolve.
function pruneManualKeys(manualKeys, liveKeys) {
    var keys = toStringArray(manualKeys);
    var live = {};
    var source = toStringArray(liveKeys);
    for (var i = 0; i < source.length; i++)
        live[source[i]] = true;

    var result = [];
    for (var k = 0; k < keys.length; k++) {
        if (live[keys[k]] === true && result.indexOf(keys[k]) < 0)
            result.push(keys[k]);
    }
    return result;
}

function withManualKey(manualKeys, orderKey) {
    var key = String(orderKey ?? "");
    var result = toStringArray(manualKeys);
    if (key !== "" && result.indexOf(key) < 0)
        result.push(key);
    return result;
}

// ---------------------------------------------------------------------------
// Enter / exit retention
// ---------------------------------------------------------------------------

// Items removed from the model are handed back for one animation cycle, at the
// index they used to occupy, flagged so the delegate can play an exit instead
// of vanishing with its delegate. `retained` is the caller's list of
// { key, item, index, at } records.
function mergeExitingItems(items, retained, now, durationMs) {
    var source = (items || []).slice();
    var held = retained || [];
    if (held.length === 0)
        return source;

    var live = {};
    for (var i = 0; i < source.length; i++) {
        var key = source[i] ? String(source[i].orderKey ?? "") : "";
        if (key !== "")
            live[key] = true;
    }

    var pending = [];
    for (var h = 0; h < held.length; h++) {
        var record = held[h];
        if (!record || !record.item)
            continue;
        if (live[String(record.key)] === true)
            continue;
        if (finiteOr(now, 0) - finiteOr(record.at, 0) > Math.max(0, finiteOr(durationMs, 0)))
            continue;
        pending.push(record);
    }

    pending.sort(function (a, b) { return finiteOr(a.index, 0) - finiteOr(b.index, 0); });
    for (var p = 0; p < pending.length; p++) {
        var entry = pending[p];
        var clone = {};
        for (var field in entry.item)
            clone[field] = entry.item[field];
        clone.__exiting = true;
        source.splice(clamp(finiteOr(entry.index, source.length), 0, source.length), 0, clone);
    }
    return source;
}

// Keys present in `next` but not in `previous`, stamped with the time they
// appeared. A Repeater over a plain array rebuilds every delegate whenever the
// array is replaced, so "was this delegate just created?" is not the same
// question as "is this item new to the dock?" — only the second one may play an
// entrance.
function collectAddedKeys(previous, next, now) {
    var before = {};
    var source = previous || [];
    for (var i = 0; i < source.length; i++) {
        var key = source[i] ? String(source[i].orderKey ?? "") : "";
        if (key !== "")
            before[key] = true;
    }

    var added = {};
    var target = next || [];
    for (var n = 0; n < target.length; n++) {
        var item = target[n];
        if (!item || item.__exiting === true)
            continue;
        var itemKey = String(item.orderKey ?? "");
        if (itemKey === "" || before[itemKey] === true)
            continue;
        added[itemKey] = finiteOr(now, 0);
    }
    return added;
}

// Records for items present in `previous` but gone from `next`, ready to be
// appended to the retention list.
function collectRemovedItems(previous, next, now) {
    var before = previous || [];
    var after = next || [];
    var live = {};
    for (var i = 0; i < after.length; i++) {
        var key = after[i] ? String(after[i].orderKey ?? "") : "";
        if (key !== "")
            live[key] = true;
    }

    var removed = [];
    for (var b = 0; b < before.length; b++) {
        var item = before[b];
        if (!item || item.__exiting === true)
            continue;
        var itemKey = String(item.orderKey ?? "");
        if (itemKey === "" || live[itemKey] === true)
            continue;
        removed.push({
            key: itemKey,
            item: item,
            index: b,
            at: finiteOr(now, 0)
        });
    }
    return removed;
}
