.pragma library

// Every toggle the classic panel knows how to draw, in the order the edit
// tray offers the ones that are currently hidden. The classic panel has no
// pages and no sizes, so a type name is the whole record - unlike the Android
// catalog, which also owns size policy.
var TOGGLE_TYPES = [
    "network",
    "bluetooth",
    "vpn",
    "tailscale",
    "nightLight",
    "gameMode",
    "idleInhibitor",
    "modes",
    "easyEffects",
    "cloudflareWarp",
    "keyboardBacklight",
    "keypressDisplay"
];

function allTypes() {
    return TOGGLE_TYPES.slice();
}

function hasType(type) {
    return typeof type === "string" && TOGGLE_TYPES.indexOf(type) >= 0;
}

// Config exposes a QML list, which is array-like but not a JS array.
function asArray(value) {
    if (value === null || value === undefined)
        return [];
    if (Array.isArray(value))
        return value.slice();
    var result = [];
    if (typeof value.length === "number") {
        for (var i = 0; i < value.length; i++)
            result.push(value[i]);
    }
    return result;
}

// Keeps the user's order, drops anything this build cannot draw and anything
// listed twice. A type with no delegate would leave a hole in the grid.
function normalize(rawToggles) {
    var raw = asArray(rawToggles);
    var result = [];
    var seen = Object.create(null);
    for (var i = 0; i < raw.length; i++) {
        var type = raw[i];
        if (!hasType(type)) {
            console.warn("[ClassicQuickToggles] unknown toggle dropped: " + type);
            continue;
        }
        if (seen[type])
            continue;
        seen[type] = true;
        result.push(type);
    }
    return result;
}

function unusedTypes(usedToggles) {
    var used = asArray(usedToggles);
    var result = [];
    for (var i = 0; i < TOGGLE_TYPES.length; i++) {
        if (used.indexOf(TOGGLE_TYPES[i]) < 0)
            result.push(TOGGLE_TYPES[i]);
    }
    return result;
}
