.pragma library

// The lock screen's three islands as three ordered lists in
// `Config.options.lock.islands`. This module is the only place that turns a
// stored list into the order the surface draws, and it is arithmetic only so
// a contract test can hold it still.

// Each default is the order LockSurface has always drawn, so a config that
// never stored a list renders exactly what it rendered before. Config.qml's
// schema defaults must equal these lists.
var MAIN_DEFAULT = ["fingerprint", "password", "confirm"];
var LEFT_DEFAULT = ["battery", "capsLock", "alarm", "weather", "keyboardLayout", "keepAwake", "mode"];
var RIGHT_DEFAULT = ["sleep", "power", "reboot"];

function defaultsFor(island) {
    if (island === "main") return MAIN_DEFAULT;
    if (island === "left") return LEFT_DEFAULT;
    return RIGHT_DEFAULT;
}

// The password field is drawn from the main list like everything else but
// takes no drag of its own; its neighbours move around it.
function reorderable(island, id) {
    return !(island === "main" && id === "password");
}

// The order the island DRAWS, resolved against its defaults:
// - a known id missing from the stored list (written by an older version)
//   renders at its default position rather than disappearing;
// - an unknown stored id (written by a newer version) is skipped for
//   rendering but never removed here - resolving is a read.
// Index-walked because a QML list property keeps `length` but not the Array
// brand across the QVariant crossing.
function orderedItems(stored, defaults) {
    var order = [];
    var count = stored && typeof stored.length === "number" ? stored.length : 0;
    for (var i = 0; i < count; i++) {
        var id = stored[i];
        if (defaults.indexOf(id) !== -1 && order.indexOf(id) === -1)
            order.push(id);
    }
    for (var d = 0; d < defaults.length; d++) {
        if (order.indexOf(defaults[d]) !== -1)
            continue;
        var at = 0;
        for (var p = d - 1; p >= 0; p--) {
            var prev = order.indexOf(defaults[p]);
            if (prev !== -1) {
                at = prev + 1;
                break;
            }
        }
        order.splice(at, 0, defaults[d]);
    }
    return order;
}

// What a committed reorder writes: the moved rendered order plus every
// unknown stored id appended, so a newer version's entry loses its position
// but never its presence.
function storedOrder(moved, stored, defaults) {
    var result = moved.slice();
    var count = stored && typeof stored.length === "number" ? stored.length : 0;
    for (var i = 0; i < count; i++) {
        if (defaults.indexOf(stored[i]) === -1 && result.indexOf(stored[i]) === -1)
            result.push(stored[i]);
    }
    return result;
}
