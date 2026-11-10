.pragma library

/**
 * Number formatting for the usage overlay.
 *
 * Every figure here is read at a glance next to a dozen others, so precision is
 * traded for scannability: two significant parts at most, and a unit that changes
 * with the magnitude rather than a long string of zeroes.
 */

/// Seconds as "3 h 12 min" / "12 min" / "48 s". Anything under a second reads as
/// nothing rather than "0 s" — a rounding artefact is not information.
function duration(seconds) {
    const s = Math.round(seconds ?? 0);
    if (s <= 0)
        return "—";
    if (s < 60)
        return `${s} s`;
    const minutes = Math.floor(s / 60);
    if (minutes < 60)
        return `${minutes} min`;
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest === 0 ? `${hours} h` : `${hours} h ${rest} min`;
}

/// Compact form for chart axes and dense rows: "3h12", "12m", "48s".
function durationShort(seconds) {
    const s = Math.round(seconds ?? 0);
    if (s <= 0)
        return "";
    if (s < 60)
        return `${s}s`;
    const minutes = Math.floor(s / 60);
    if (minutes < 60)
        return `${minutes}m`;
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return rest === 0 ? `${hours}h` : `${hours}h${rest}`;
}

/// Watt-hours, switching to mWh below 1 Wh. Battery figures span three orders of
/// magnitude between a daemon and a browser, so a fixed unit would waste the column.
function energy(wh) {
    const value = wh ?? 0;
    if (value <= 0)
        return "—";
    if (value < 0.001)
        return "<1 mWh";
    if (value < 1)
        return `${Math.round(value * 1000)} mWh`;
    if (value < 10)
        return `${value.toFixed(2)} Wh`;
    return `${value.toFixed(1)} Wh`;
}

function energyFromMj(mj) {
    return energy((mj ?? 0) / 3600000);
}

/// MiB as stored by the sampler.
function memory(mib) {
    const value = mib ?? 0;
    if (value <= 0)
        return "—";
    if (value < 1024)
        return `${Math.round(value)} MiB`;
    return `${(value / 1024).toFixed(1)} GiB`;
}

/// Bytes in decimal SI units ("840 kB", "1.2 GB"), as network data is quoted: a
/// gigabyte of traffic is 10^9 bytes, unlike a gibibyte of memory.
function bytes(b) {
    const value = b ?? 0;
    if (value <= 0)
        return "—";
    const units = ["B", "kB", "MB", "GB", "TB"];
    let unit = 0;
    let scaled = value;
    while (scaled >= 1000 && unit < units.length - 1) {
        scaled /= 1000;
        unit++;
    }
    if (unit === 0)
        return `${Math.round(scaled)} B`;
    return `${scaled < 10 ? scaled.toFixed(1) : Math.round(scaled)} ${units[unit]}`;
}

/// KiB as stored by the sampler.
function bytesFromKib(kib) {
    return bytes((kib ?? 0) * 1024);
}

function count(n) {
    return (n ?? 0) <= 0 ? "—" : `${Math.round(n)}`;
}

/// "14:00" for an hour-of-day bucket index.
function hourLabel(hour) {
    return `${hour < 10 ? "0" : ""}${hour}:00`;
}

/// Month abbreviations for the day axis. Hardcoded like `hourLabel`'s "HH:00":
/// this file is a pragma library and has no QML locale to ask.
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/// Day of month for a "YYYY-MM-DD" key. `withMonth` spells the month out as well,
/// for the days one starts and for the ends of the range — a bare number repeats
/// every four weeks and never says which side of a boundary it falls on.
function dayLabel(dateKey, withMonth) {
    const parts = dateKey.split("-");
    const day = parseInt(parts[2]);
    if (!withMonth)
        return `${day}`;
    return `${day} ${MONTHS[parseInt(parts[1]) - 1] ?? ""}`;
}
