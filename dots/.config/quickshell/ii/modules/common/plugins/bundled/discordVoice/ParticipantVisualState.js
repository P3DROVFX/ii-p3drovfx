.pragma library

// Repeater delegates are rebuilt when the bridge publishes a fresh participant
// array. Retain only the last shape per Discord user so a replacement delegate
// can animate from what was actually on screen instead of appearing in its new
// state immediately.
// Entries are only useful while a user is on screen or about to return, so the
// map is capped rather than grown for the lifetime of the shell. Keys keep
// insertion order, which makes the oldest entry the first one to drop.
var MAX_ENTRIES = 128

var shapes = Object.create(null)

function previous(userId, fallback) {
    return userId && shapes[userId] !== undefined ? shapes[userId] : fallback
}

function remember(userId, shape) {
    if (!userId)
        return
    // Re-insert so a user still in the call moves back to the newest position
    // and cannot be evicted ahead of someone who left.
    delete shapes[userId]
    shapes[userId] = shape
    var keys = Object.keys(shapes)
    for (var index = 0; index < keys.length - MAX_ENTRIES; ++index)
        delete shapes[keys[index]]
}
