.pragma library

// Length, weight, temperature, data, area, volume, speed and time units for
// the converter widgets (the dock's tile and the desktop's Converter).
// Linear units are stored as their size in the category's base unit
// (metre, gram, byte); temperature goes through Celsius.

var categories = [
    { id: "length", title: "Length", symbol: "straighten",
      units: [
          { id: "mm", label: "mm", factor: 0.001 },
          { id: "cm", label: "cm", factor: 0.01 },
          { id: "m", label: "m", factor: 1 },
          { id: "km", label: "km", factor: 1000 },
          { id: "in", label: "in", factor: 0.0254 },
          { id: "ft", label: "ft", factor: 0.3048 },
          { id: "yd", label: "yd", factor: 0.9144 },
          { id: "mi", label: "mi", factor: 1609.344 }
      ] },
    { id: "weight", title: "Weight", symbol: "scale",
      units: [
          { id: "mg", label: "mg", factor: 0.001 },
          { id: "g", label: "g", factor: 1 },
          { id: "kg", label: "kg", factor: 1000 },
          { id: "t", label: "t", factor: 1000000 },
          { id: "oz", label: "oz", factor: 28.349523125 },
          { id: "lb", label: "lb", factor: 453.59237 },
          { id: "st", label: "st", factor: 6350.29318 }
      ] },
    { id: "temperature", title: "Temperature", symbol: "thermostat",
      units: [
          { id: "c", label: "°C" },
          { id: "f", label: "°F" },
          { id: "k", label: "K" }
      ] },
    { id: "data", title: "Data", symbol: "storage",
      units: [
          { id: "b", label: "B", factor: 1 },
          { id: "kb", label: "KB", factor: 1e3 },
          { id: "mb", label: "MB", factor: 1e6 },
          { id: "gb", label: "GB", factor: 1e9 },
          { id: "tb", label: "TB", factor: 1e12 },
          { id: "kib", label: "KiB", factor: 1024 },
          { id: "mib", label: "MiB", factor: 1048576 },
          { id: "gib", label: "GiB", factor: 1073741824 },
          { id: "tib", label: "TiB", factor: 1099511627776 }
      ] },
    { id: "area", title: "Area", symbol: "square_foot",
      units: [
          { id: "cm2", label: "cm²", factor: 0.0001 },
          { id: "m2", label: "m²", factor: 1 },
          { id: "ha", label: "ha", factor: 10000 },
          { id: "km2", label: "km²", factor: 1000000 },
          { id: "in2", label: "in²", factor: 0.00064516 },
          { id: "ft2", label: "ft²", factor: 0.09290304 },
          { id: "ac", label: "ac", factor: 4046.8564224 },
          { id: "mi2", label: "mi²", factor: 2589988.110336 }
      ] },
    { id: "volume", title: "Volume", symbol: "water_full",
      units: [
          { id: "ml", label: "mL", factor: 0.001 },
          { id: "l", label: "L", factor: 1 },
          { id: "m3", label: "m³", factor: 1000 },
          { id: "tsp", label: "tsp", factor: 0.00492892159375 },
          { id: "tbsp", label: "tbsp", factor: 0.01478676478125 },
          { id: "cup", label: "cup", factor: 0.2365882365 },
          { id: "floz", label: "fl oz", factor: 0.0295735295625 },
          { id: "gal", label: "gal", factor: 3.785411784 }
      ] },
    { id: "speed", title: "Speed", symbol: "speed",
      units: [
          { id: "mps", label: "m/s", factor: 1 },
          { id: "kmh", label: "km/h", factor: 1 / 3.6 },
          { id: "mph", label: "mph", factor: 0.44704 },
          { id: "kn", label: "kn", factor: 1852 / 3600 },
          { id: "fps", label: "ft/s", factor: 0.3048 }
      ] },
    { id: "time", title: "Time", symbol: "schedule",
      units: [
          { id: "ms", label: "ms", factor: 0.001 },
          { id: "s", label: "s", factor: 1 },
          { id: "min", label: "min", factor: 60 },
          { id: "h", label: "h", factor: 3600 },
          { id: "d", label: "d", factor: 86400 },
          { id: "wk", label: "wk", factor: 604800 },
          { id: "yr", label: "yr", factor: 31557600 }
      ] }
];

function category(id) {
    for (var i = 0; i < categories.length; i++) {
        if (categories[i].id === id)
            return categories[i];
    }
    return categories[0];
}

function unit(categoryId, unitId) {
    var units = category(categoryId).units;
    for (var i = 0; i < units.length; i++) {
        if (units[i].id === unitId)
            return units[i];
    }
    return null;
}

// The pair a category opens with when the saved one does not belong to it.
function defaultPair(categoryId) {
    switch (categoryId) {
    case "weight": return { from: "kg", to: "lb" };
    case "temperature": return { from: "c", to: "f" };
    case "data": return { from: "gb", to: "gib" };
    case "area": return { from: "m2", to: "ft2" };
    case "volume": return { from: "l", to: "gal" };
    case "speed": return { from: "kmh", to: "mph" };
    case "time": return { from: "h", to: "min" };
    default: return { from: "cm", to: "in" };
    }
}

function _toCelsius(value, unitId) {
    if (unitId === "f")
        return (value - 32) * 5 / 9;
    if (unitId === "k")
        return value - 273.15;
    return value;
}

function _fromCelsius(value, unitId) {
    if (unitId === "f")
        return value * 9 / 5 + 32;
    if (unitId === "k")
        return value + 273.15;
    return value;
}

// NaN when the input or a unit is not understood.
function convert(value, categoryId, fromId, toId) {
    var v = Number(value);
    if (!isFinite(v))
        return NaN;
    if (categoryId === "temperature") {
        if (!unit(categoryId, fromId) || !unit(categoryId, toId))
            return NaN;
        return _fromCelsius(_toCelsius(v, fromId), toId);
    }
    var from = unit(categoryId, fromId);
    var to = unit(categoryId, toId);
    if (!from || !to)
        return NaN;
    return v * from.factor / to.factor;
}

// Accepts "1,5", "1.5", "1 500", "-3".
function parse(text) {
    var s = String(text || "").trim().replace(/\s+/g, "");
    if (s.length === 0)
        return NaN;
    // A lone comma is a decimal separator; with both, the last one is.
    if (s.indexOf(",") >= 0 && s.indexOf(".") < 0)
        s = s.replace(",", ".");
    else if (s.indexOf(",") >= 0 && s.indexOf(".") >= 0)
        s = s.lastIndexOf(",") > s.lastIndexOf(".") ? s.replace(/\./g, "").replace(",", ".") : s.replace(/,/g, "");
    if (!/^[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/i.test(s))
        return NaN;
    return Number(s);
}

// Up to five significant digits, no trailing zeros, no exponent for everyday sizes.
function format(value) {
    if (!isFinite(value))
        return "—";
    if (value === 0)
        return "0";
    var abs = Math.abs(value);
    if (abs >= 1e15 || abs < 1e-6)
        return value.toExponential(3).replace(/\.?0+e/, "e");
    var digits = abs >= 1 ? Math.max(0, 5 - Math.floor(Math.log10(abs)) - 1) : 4 - Math.floor(Math.log10(abs));
    var fixed = value.toFixed(Math.min(10, Math.max(0, digits)));
    if (fixed.indexOf(".") >= 0)
        fixed = fixed.replace(/0+$/, "").replace(/\.$/, "");
    return fixed;
}
