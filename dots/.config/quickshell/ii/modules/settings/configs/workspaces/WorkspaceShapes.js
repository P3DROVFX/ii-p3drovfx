.pragma library

// Every MaterialShape the bar may draw for the active indicator or an app icon mask.
const all = ["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill", "Triangle", "Diamond",
    "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided",
    "Cookie9Sided", "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
    "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"];

// "Cookie12Sided" -> "Cookie 12 Sided"
function label(name) {
    return String(name).replace(/([a-z])([A-Z0-9])/g, "$1 $2").replace(/([0-9])([A-Z])/g, "$1 $2");
}
