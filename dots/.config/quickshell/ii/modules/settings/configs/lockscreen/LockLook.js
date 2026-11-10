.pragma library

// The lock's four wallpaper treatments as single values: 0 is off, anything above
// is on at that strength. Blur is in screen pixels (0–50), the rest are 0–1.
var EFFECTS = ["blur", "desaturate", "colorWash", "vignette"];

var PRESETS = [
    { id: "clear", blur: 0, desaturate: 0, colorWash: 0, vignette: 0 },
    { id: "soft", blur: 20, desaturate: 0, colorWash: 0, vignette: 0.3 },
    { id: "frosted", blur: 45, desaturate: 0.25, colorWash: 0, vignette: 0.3 },
    { id: "muted", blur: 30, desaturate: 0.8, colorWash: 0, vignette: 0.5 },
    { id: "tinted", blur: 35, desaturate: 0.4, colorWash: 0.35, vignette: 0.2 },
    { id: "noir", blur: 10, desaturate: 1, colorWash: 0, vignette: 0.7 }
];

function valueOf(lock, key) {
    var effect = lock[key];
    if (!effect || !effect.enable)
        return 0;
    return key === "blur" ? effect.radius : effect.amount;
}

// Dragging to zero turns the effect off and keeps its last strength for next time.
function setValue(lock, key, value) {
    var effect = lock[key];
    if (value <= 0.0001) {
        effect.enable = false;
        return;
    }
    if (key === "blur")
        effect.radius = value;
    else
        effect.amount = value;
    effect.enable = true;
}

function apply(lock, preset) {
    for (var i = 0; i < EFFECTS.length; i++)
        setValue(lock, EFFECTS[i], preset[EFFECTS[i]]);
}

function matches(lock, preset) {
    for (var i = 0; i < EFFECTS.length; i++) {
        var key = EFFECTS[i];
        var tolerance = key === "blur" ? 0.5 : 0.01;
        if (Math.abs(valueOf(lock, key) - preset[key]) > tolerance)
            return false;
    }
    return true;
}

function activeCount(lock) {
    var count = 0;
    for (var i = 0; i < EFFECTS.length; i++)
        if (valueOf(lock, EFFECTS[i]) > 0)
            count++;
    return count;
}
