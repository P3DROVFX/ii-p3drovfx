.pragma library

// Emoji glyphs are text, so sampling a representative pixel is neither
// stable nor cheap. These category offsets keep the selected cell expressive
// while still deriving every actual colour from the active Material palette.
function hueForCategory(category) {
    switch (String(category ?? "")) {
    case "people": return 28;
    case "nature": return 104;
    case "food": return 12;
    case "objects": return 212;
    case "symbols": return 286;
    default: return 0;
    }
}
