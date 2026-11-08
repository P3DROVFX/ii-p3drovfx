.pragma library

// Display helpers for the Football overview: times, day labels and the
// formation layout of a lineup. Pure functions; the page passes the locale in.

function pad(value) {
    return String(value).padStart(2, "0");
}

function kickoffTime(isoDate) {
    if (!isoDate)
        return "";
    const date = new Date(isoDate);
    if (isNaN(date.getTime()))
        return "";
    return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function shortDate(isoDate, locale) {
    if (!isoDate)
        return "";
    const date = new Date(isoDate);
    if (isNaN(date.getTime()))
        return "";
    return date.toLocaleDateString(locale, "d MMM");
}

function longDate(isoDate, locale) {
    if (!isoDate)
        return "";
    const date = new Date(isoDate);
    if (isNaN(date.getTime()))
        return "";
    return date.toLocaleDateString(locale, "dddd, d MMMM yyyy");
}

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date, days) {
    const next = startOfDay(date);
    next.setDate(next.getDate() + days);
    return next;
}

function dayOffset(date) {
    const today = startOfDay(new Date());
    return Math.round((startOfDay(date) - today) / 86400000);
}

// "LIVE 63'", "HT", "FT", "16:00" for a match row/chip.
function statusText(match, liveLabel) {
    if (!match)
        return "";
    if (match.state === "in")
        return match.clock !== "" ? match.clock : (match.statusDetail || liveLabel);
    if (match.state === "post")
        return match.statusDetail || "FT";
    return kickoffTime(match.date);
}

// ── Lineup layout ────────────────────────────────────────────────────────────

function positionDepth(abbreviation) {
    const base = String(abbreviation || "").toUpperCase().replace(/-[LRC]$/, "");
    if (base === "G" || base === "GK")
        return 0;
    if (base === "LWB" || base === "RWB" || base === "WB")
        return 1.6;
    if (base === "CD" || base === "CB" || base === "SW" || base === "D" || base === "LB" || base === "RB")
        return 1;
    if (base === "DM" || base === "CDM")
        return 2;
    if (base === "AM" || base === "CAM")
        return 4;
    if (base === "LW" || base === "RW" || base === "W")
        return 4.5;
    if (base === "CF" || base === "ST" || base === "F" || base === "SS" || base === "FW" || base === "LF" || base === "RF")
        return 5;
    if (base === "LM" || base === "RM" || base === "CM" || base === "M")
        return 3;
    return 3;
}

// Left (-) to right (+) seen from the team's own goal.
function positionLateral(abbreviation) {
    const value = String(abbreviation || "").toUpperCase();
    if (/-L$/.test(value))
        return -0.5;
    if (/-R$/.test(value))
        return 0.5;
    if (/^L/.test(value))
        return -1;
    if (/^R/.test(value))
        return 1;
    return 0;
}

// Starters grouped into formation lines, goalkeeper first. The formation
// string fixes how many players each line holds; positions decide who goes
// where, which survives ESPN's formation slots not being in line order.
// `positions` maps athlete id → English abbreviation: ESPN localises the
// abbreviations with the payload's language, and the layout needs the English
// ones. Without it the localised value is used as is.
function formationLines(lineup, positions) {
    const map = positions ?? ({});
    const starters = (lineup?.starters ?? []).map(player => Object.assign({}, player, { pos: map[player.id] || player.pos }));
    if (starters.length === 0)
        return [];
    const keeperIndex = starters.findIndex(player => positionDepth(player.pos) === 0);
    const keeper = keeperIndex !== -1 ? starters.splice(keeperIndex, 1)[0] : starters.shift();
    starters.sort((left, right) => {
        const depth = positionDepth(left.pos) - positionDepth(right.pos);
        return depth !== 0 ? depth : left.place - right.place;
    });
    let sizes = String(lineup?.formation || "").split("-").map(part => parseInt(part, 10)).filter(size => size > 0);
    const total = sizes.reduce((sum, size) => sum + size, 0);
    if (total !== starters.length)
        sizes = starters.length === 10 ? [4, 4, 2] : [starters.length];
    const lines = [[keeper]];
    let offset = 0;
    sizes.forEach(size => {
        const line = starters.slice(offset, offset + size);
        offset += size;
        line.sort((left, right) => positionLateral(left.pos) - positionLateral(right.pos));
        lines.push(line);
    });
    return lines;
}
