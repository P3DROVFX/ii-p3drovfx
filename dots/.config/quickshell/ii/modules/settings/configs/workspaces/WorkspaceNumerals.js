.pragma library

// The numeral systems the bar can draw instead of 1, 2, 3 …: workspace N shows entry N-1.
// An empty map means plain digits.
const maps = {
    "normal": [],
    "han": ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十"],
    "roman": ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"],
    "greek": ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ", "λ", "μ", "ν", "ξ", "ο", "π", "ρ", "σ", "τ", "υ"],
    // Suzhou rod numerals: 1-9 are upright strokes and the tens place has its own glyphs.
    "rods": ["〡", "〢", "〣", "〤", "〥", "〦", "〧", "〨", "〩", "〸", "〸〡", "〸〢", "〸〣", "〸〤", "〸〥", "〸〦", "〸〧", "〸〨", "〸〩", "〹"]
};

// Workspaces a card shows as a sample: the first five.
const sampleIds = [1, 2, 3, 4, 5];

function label(id, map) {
    return String(map[id - 1] || id);
}

function samples(map) {
    return sampleIds.map(id => label(id, map));
}

function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

function idFor(current) {
    for (const key in maps) {
        if (same(maps[key], current))
            return key;
    }
    return "";
}
