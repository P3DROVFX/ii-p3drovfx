.pragma library

// Strings here are ids and glyphs only; the page names them through Translation.tr.

var STYLES = [
    { id: "default", icon: "workspaces", shape: "Cookie9Sided", indicator: true, arrow: true, icons: true, numbers: true },
    { id: "minimal", icon: "navigation", shape: "Pill", indicator: true, arrow: false, icons: false, numbers: false },
    { id: "expressive", icon: "fluid_med", shape: "Cookie7Sided", indicator: false, arrow: false, icons: false, numbers: true },
    { id: "dock", icon: "dock_to_left", shape: "Square", indicator: true, arrow: false, icons: true, numbers: true },
    { id: "index", icon: "format_list_numbered", shape: "Pentagon", indicator: false, arrow: false, icons: false, numbers: true }
];

var COLOR_MODES = [
    "primary", "primaryContainer",
    "secondary", "secondaryContainer",
    "tertiary", "tertiaryContainer",
    "neutral", "neutralContainer"
];

var NUMERALS = [
    { id: "normal", map: [] },
    { id: "han", map: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十"] },
    { id: "roman", map: ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"] },
    { id: "greek", map: ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ", "λ", "μ", "ν", "ξ", "ο", "π", "ρ", "σ", "τ", "υ"] },
    { id: "rods", map: ["〡", "〢", "〣", "〤", "〥", "〦", "〧", "〨", "〩", "〸", "〸〡", "〸〢", "〸〣", "〸〤", "〸〥", "〸〦", "〸〧", "〸〨", "〸〩", "〹"] }
];

var SHAPES = [
    "Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond",
    "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided",
    "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst",
    "Flower", "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"
];

var RANDOM_SHAPES = ["Cookie7Sided", "Clover4Leaf", "Gem", "Sunny", "Pentagon", "Flower", "SoftBurst", "Cookie9Sided"];

var INDICATORS = [{ id: "pill" }, { id: "shape" }, { id: "random" }, { id: "arrow" }];


// The stage's pretend desktop: windows per workspace (app classes) and the tour the focus takes.
var DEMO_WINDOWS = [
    ["firefox", "kitty"],
    ["code"],
    ["org.gnome.Nautilus", "spotify", "discord"],
    [],
    ["obsidian"],
    [],
    ["steam"],
    [],
    ["thunderbird", "kitty"],
    []
];
var DEMO_TOUR = [0, 1, 2, 4, 2, 1, 0, 3];
var COMPACT_BEFORE = [true, false, true, false, true, true];

function style(id) {
    for (var i = 0; i < STYLES.length; i++)
        if (STYLES[i].id === id)
            return STYLES[i];
    return STYLES[0];
}

function indicatorOf(cfg) {
    if (cfg.useDirectionArrowForActiveIndicator)
        return "arrow";
    if (cfg.useRandomShapeForActiveIndicator)
        return "random";
    if (cfg.useMaterialShapeForActiveIndicator)
        return "shape";
    return "pill";
}

function applyIndicator(cfg, mode) {
    cfg.useMaterialShapeForActiveIndicator = mode === "shape";
    cfg.useRandomShapeForActiveIndicator = mode === "random";
    cfg.useDirectionArrowForActiveIndicator = mode === "arrow";
}

function numeralOf(map) {
    var key = JSON.stringify(map || []);
    for (var i = 0; i < NUMERALS.length; i++)
        if (JSON.stringify(NUMERALS[i].map) === key)
            return NUMERALS[i].id;
    return "custom";
}

function numeralMap(id) {
    for (var i = 0; i < NUMERALS.length; i++)
        if (NUMERALS[i].id === id)
            return NUMERALS[i].map.slice();
    return [];
}

function label(map, index) {
    return String((map && map[index]) || (index + 1));
}

function demoWindows(slot, limit) {
    var list = DEMO_WINDOWS[slot % DEMO_WINDOWS.length];
    return list.slice(0, Math.max(0, limit));
}
