.pragma library

.import "shapes/shapes/morph.js" as Morph

/**
 * Shared morphs, one per (start, end) polygon pair.
 *
 * Building a Morph matches the two outlines feature by feature, which costs
 * 0.6-1 ms on a downclocked CPU. MaterialShape's polygons are module-level
 * singletons, so every badge on a settings page asks for the same handful of
 * pairs - there is no reason to match them again for each one. A Morph never
 * changes after construction (asCubics() allocates its own output), so one
 * instance can serve every canvas.
 *
 * Keys are ids stamped on the polygon objects (plain JS, never QObjects).
 * Callers that build a fresh polygon per evaluation would grow the cache
 * without bound, so it is simply emptied past a small size.
 */
var _entries = new Map();
var _nextId = 1;
var _limit = 128;

function _id(polygon) {
    if (polygon.__morphCacheId === undefined)
        polygon.__morphCacheId = _nextId++;
    return polygon.__morphCacheId;
}

function entry(start, end) {
    if (!start || !end)
        return null;
    const key = _id(start) + ":" + _id(end);
    let found = _entries.get(key);
    if (!found) {
        if (_entries.size >= _limit)
            _entries.clear();
        found = {
            morph: new Morph.Morph(start, end),
            settled: null
        };
        _entries.set(key, found);
    }
    return found;
}

/// The finished shape, which is what nearly every paint draws.
function settledCubics(found) {
    if (!found)
        return [];
    if (found.settled === null)
        found.settled = found.morph.asCubics(1);
    return found.settled;
}
