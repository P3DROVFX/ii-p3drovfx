.pragma library

// The numeral systems the bar can draw instead of 1, 2, 3 …: workspace N shows entry N-1.
// An empty map means plain digits. The config stores these 20-entry maps; past
// the end of a recognised map, label() generates the rest so workspace 21+ keeps
// its numeral style instead of falling back to digits.
const maps = {
    "normal": [],
    "han": ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十"],
    "roman": ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"],
    "greek": ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ", "λ", "μ", "ν", "ξ", "ο", "π", "ρ", "σ", "τ", "υ"],
    // Suzhou rod numerals: 1-9 are upright strokes and the tens place has its own glyphs.
    "rods": ["〡", "〢", "〣", "〤", "〥", "〦", "〧", "〨", "〩", "〸", "〸〡", "〸〢", "〸〣", "〸〤", "〸〥", "〸〦", "〸〧", "〸〨", "〸〩", "〹"]
};

const greekLetters = ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ", "λ", "μ", "ν", "ξ", "ο", "π", "ρ", "σ", "τ", "υ", "φ", "χ", "ψ", "ω"];
const hanDigits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"];
const rodDigits = ["〇", "〡", "〢", "〣", "〤", "〥", "〦", "〧", "〨", "〩"];
const rodHorizontal = ["", "一", "二", "三"];

function roman(n) {
    if (n >= 4000)
        return String(n);
    const table = [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"],
                   [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]];
    let out = "";
    for (const [value, glyph] of table) {
        while (n >= value) {
            out += glyph;
            n -= value;
        }
    }
    return out;
}

// Standard Chinese numerals below 10000: 二十一, 一百零五, 一千二百.
function han(n) {
    if (n >= 10000)
        return String(n);
    const units = [[1000, "千"], [100, "百"], [10, "十"]];
    let out = "";
    let pendingZero = false;
    for (const [value, unit] of units) {
        const digit = Math.floor(n / value);
        n %= value;
        if (digit === 0) {
            if (out !== "")
                pendingZero = true;
            continue;
        }
        if (pendingZero)
            out += "零";
        pendingZero = false;
        // 十 alone opens the teens (十一), like the stored map; 一十 everywhere else.
        out += (value === 10 && digit === 1 && out === "") ? unit : hanDigits[digit] + unit;
    }
    if (n > 0)
        out += (pendingZero ? "零" : "") + hanDigits[n];
    return out;
}

// Greek letters in order (α … ω), then bijective base-24 like spreadsheet columns (αα, αβ …).
function greek(n) {
    let out = "";
    while (n > 0) {
        n -= 1;
        out = greekLetters[n % 24] + out;
        n = Math.floor(n / 24);
    }
    return out;
}

// Suzhou numerals: 10/20/30 have their own tens glyphs, matching the stored map;
// past 39 the digits go positional, and a 1-3 digit next to another 1-3 digit is
// written horizontally so the strokes stay readable.
function rods(n) {
    if (n < 40) {
        const tens = Math.floor(n / 10), ones = n % 10;
        return (tens ? ["", "〸", "〹", "〺"][tens] : "") + (ones ? rodDigits[ones] : "");
    }
    const digits = String(n).split("").map(Number);
    let out = "";
    let previousVertical = false;
    for (const d of digits) {
        const small = d >= 1 && d <= 3;
        if (small && previousVertical) {
            out += rodHorizontal[d];
            previousVertical = false;
        } else {
            out += rodDigits[d];
            previousVertical = small;
        }
    }
    return out;
}

const generators = { "han": han, "roman": roman, "greek": greek, "rods": rods };

// The style whose stored map begins with `map`, so a config saved before the
// generators existed (or a shorter map) still extends past its last entry.
function styleOf(map) {
    if (!map || map.length === 0)
        return "";
    for (const key in generators) {
        const canonical = maps[key];
        const n = Math.min(map.length, canonical.length);
        let match = true;
        for (let i = 0; i < n; i++) {
            if (String(map[i]) !== canonical[i]) {
                match = false;
                break;
            }
        }
        if (match)
            return key;
    }
    return "";
}

function label(id, map) {
    const entry = map ? map[id - 1] : undefined;
    if (entry)
        return String(entry);
    const style = styleOf(map);
    return style && id > 0 ? generators[style](id) : String(id);
}

// Workspaces a card shows as a sample: the first five.
const sampleIds = [1, 2, 3, 4, 5];

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
