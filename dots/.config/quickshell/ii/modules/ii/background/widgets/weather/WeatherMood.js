.pragma library

// The expressive weather widgets' shared reading of the weather: which family
// a WWO code belongs to, the Material shape that stands for it, and whether
// it is night at the place (from the service's sunrise/sunset strings).

var _families = {
    clear: ["113"],
    partly: ["116"],
    cloud: ["119", "122"],
    fog: ["143", "185", "248", "260"],
    storm: ["200", "386", "389", "392", "395"],
    snow: ["179", "227", "230", "320", "323", "326", "329", "332", "335", "338", "368", "371", "374", "377", "350"],
    rain: ["176", "182", "263", "266", "281", "284", "293", "296", "299", "302", "305", "308", "311", "314", "317", "353", "356", "359", "362", "365"]
};

function family(code) {
    var key = String(code);
    for (var name in _families) {
        if (_families[name].indexOf(key) >= 0)
            return name;
    }
    return "cloud";
}

// A shape per family: the sun's rays, a puffy cloud, a drop, a flake...
function shapeName(fam, night) {
    switch (fam) {
    case "clear": return night ? "Circle" : "VerySunny";
    case "partly": return night ? "Bun" : "Sunny";
    case "cloud": return "Puffy";
    case "fog": return "Pill";
    case "rain": return "Gem";
    case "snow": return "Clover8Leaf";
    case "storm": return "SoftBoom";
    }
    return "Puffy";
}

// The shape a hover morphs into: same family, another voice.
function altShapeName(fam, night) {
    switch (fam) {
    case "clear": return night ? "Cookie12Sided" : "SoftBurst";
    case "partly": return "Cookie9Sided";
    case "cloud": return "PuffyDiamond";
    case "fog": return "Oval";
    case "rain": return "Cookie4Sided";
    case "snow": return "Flower";
    case "storm": return "Boom";
    }
    return "Cookie9Sided";
}

// "6:12", "06:12", "6:12 PM" -> minutes since midnight; NaN when unreadable.
function minutesOf(text) {
    var m = String(text || "").trim().match(/^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?$/);
    if (!m)
        return NaN;
    var h = parseInt(m[1], 10) % 24;
    if (m[3]) {
        h = h % 12;
        if (m[3].toUpperCase() === "PM")
            h += 12;
    }
    return h * 60 + parseInt(m[2], 10);
}

// 0 at sunrise, 1 at sunset; below 0 before dawn, above 1 after dusk.
function dayProgress(date, sunrise, sunset) {
    var rise = minutesOf(sunrise);
    var set = minutesOf(sunset);
    if (!isFinite(rise) || !isFinite(set) || set <= rise)
        return 0.5;
    var now = date.getHours() * 60 + date.getMinutes();
    return (now - rise) / (set - rise);
}

function isNight(date, sunrise, sunset) {
    var p = dayProgress(date, sunrise, sunset);
    return p < 0 || p > 1;
}

// "27°C" -> "27"; keeps the sign.
function number(temp) {
    var m = String(temp || "").match(/-?\d+/);
    return m ? m[0] : "--";
}
