.pragma library

// Only appearance parameters belong here. Leave blur.enabled to Hyprland / Game
// Mode so reapplying a saved look cannot undo a temporary blur-disable override.
function numberInRange(value, fallback, minimum, maximum, integer) {
    const number = typeof value === "number" && isFinite(value) ? value : fallback;
    const bounded = Math.max(minimum, Math.min(maximum, number));
    return integer ? Math.round(bounded) : Math.round(bounded * 10000) / 10000;
}

function booleanValue(value, fallback) {
    return typeof value === "boolean" ? value : fallback;
}

function buildScript(size, options) {
    const blur = options || {};
    const values = {
        // Size zero was already offered by Windows Config (no blur).
        size: numberInRange(size, 10, 0, 100, true),
        passes: numberInRange(blur.passes, 3, 1, 10, true),
        noise: numberInRange(blur.noise, 0.05, 0, 1, false),
        contrast: numberInRange(blur.contrast, 0.89, 0, 2, false),
        brightness: numberInRange(blur.brightness, 1, 0, 2, false),
        vibrancy: numberInRange(blur.vibrancy, 0.2, 0, 1, false),
        vibrancy_darkness: numberInRange(blur.vibrancyDarkness, 0.2, 0, 1, false),
        ignore_opacity: booleanValue(blur.ignoreOpacity, true),
        new_optimizations: booleanValue(blur.newOptimizations, true),
        xray: booleanValue(blur.xray, false),
        special: booleanValue(blur.special, false),
        popups: booleanValue(blur.popups, false),
        popups_ignorealpha: numberInRange(blur.popupsIgnoreAlpha, 0.6, 0, 1, false),
        input_methods: booleanValue(blur.inputMethods, true),
        input_methods_ignorealpha: numberInRange(blur.inputMethodsIgnoreAlpha, 0.8, 0, 1, false)
    };
    // X-ray requires the optimized blur path. Preserve the preference while the
    // optimization is off, and restore it when that path is enabled again.
    values.xray = values.new_optimizations && values.xray;
    return "hl.config({ decoration = { blur = { " + Object.keys(values).map(function(key) {
        return key + " = " + String(values[key]);
    }).join(", ") + " } } })";
}
