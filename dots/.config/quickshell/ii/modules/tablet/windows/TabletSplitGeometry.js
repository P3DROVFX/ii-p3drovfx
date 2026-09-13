.pragma library

/**
 * The dividers between tiled windows, found from the geometry Hyprland reports.
 *
 * Hyprland does not expose its layout tree, so the gutters are read back from the windows
 * themselves: two windows whose facing edges are one gap apart and which overlap along that
 * edge share a divider. Dividers on the same line are merged, so a window beside a stack of
 * two gets one handle for the whole edge rather than one per neighbour.
 *
 * Pure: windows in, dividers out. Every rect is `{ address, x, y, width, height }` in layout
 * coordinates.
 */

function unique(list) {
    return list.filter((value, index) => list.indexOf(value) === index);
}

function dividers(windows, options) {
    const maxGap = (options && options.maxGap) || 48;
    const minOverlap = (options && options.minOverlap) || 48;
    const found = [];

    for (const a of windows) {
        for (const b of windows) {
            if (a === b)
                continue;

            const vGap = b.x - (a.x + a.width);
            if (vGap > 0 && vGap <= maxGap) {
                const start = Math.max(a.y, b.y);
                const end = Math.min(a.y + a.height, b.y + b.height);
                if (end - start >= minOverlap)
                    found.push({ orientation: "vertical", position: a.x + a.width, thickness: vGap,
                                 start: start, end: end, before: [a.address], after: [b.address] });
            }

            const hGap = b.y - (a.y + a.height);
            if (hGap > 0 && hGap <= maxGap) {
                const start = Math.max(a.x, b.x);
                const end = Math.min(a.x + a.width, b.x + b.width);
                if (end - start >= minOverlap)
                    found.push({ orientation: "horizontal", position: a.y + a.height, thickness: hGap,
                                 start: start, end: end, before: [a.address], after: [b.address] });
            }
        }
    }

    found.sort((p, q) => (p.orientation < q.orientation ? -1 : p.orientation > q.orientation ? 1 : 0)
        || (p.position - q.position) || (p.start - q.start));

    const merged = [];
    for (const d of found) {
        const into = merged.find(m => m.orientation === d.orientation
            && Math.abs(m.position - d.position) <= 2
            && Math.abs(m.thickness - d.thickness) <= 2
            && d.start <= m.end + m.thickness + 2);
        if (into) {
            into.start = Math.min(into.start, d.start);
            into.end = Math.max(into.end, d.end);
            into.before = unique(into.before.concat(d.before));
            into.after = unique(into.after.concat(d.after));
        } else {
            merged.push({ orientation: d.orientation, position: d.position, thickness: d.thickness,
                          start: d.start, end: d.end, before: d.before.slice(), after: d.after.slice() });
        }
    }
    // Keyed by what it separates, not where it is: the key has to survive the divider being
    // dragged, or the handle under the finger is rebuilt on every step of the resize.
    merged.forEach(d => d.key = `${d.orientation}:${d.before.slice().sort().join(",")}`);
    return merged;
}

function byAddress(windows) {
    const map = {};
    for (const w of windows)
        map[w.address] = w;
    return map;
}

/**
 * The divider moved to `position` (its leading edge): the sizes to dispatch.
 *
 * Only the windows before the divider are resized. Hyprland's dwindle resizes a window by
 * moving the split it shares with its neighbour, and for the second child of a split an exact
 * size comes out mirrored — asking the right window for 600px gave the left one 600px. The
 * first child answers exactly, so it is always the one asked.
 */
function resizePlan(divider, windows, position, minSize) {
    const map = byAddress(windows);
    const before = divider.before.map(a => map[a]).filter(Boolean);
    const after = divider.after.map(a => map[a]).filter(Boolean);
    const floor = minSize || 160;
    const vertical = divider.orientation === "vertical";

    const lowest = Math.max(...before.map(w => (vertical ? w.x : w.y) + floor));
    const highest = Math.min(...after.map(w => vertical ? w.x + w.width : w.y + w.height)) - floor - divider.thickness;
    const clamped = Math.round(Math.max(lowest, Math.min(highest, position)));

    return {
        position: clamped,
        resizes: before.map(w => vertical
            ? { address: w.address, width: clamped - w.x, height: w.height }
            : { address: w.address, width: w.width, height: clamped - w.y })
    };
}

/// Where the divider sits when both sides get the same share of the span it cuts.
function evenPosition(divider, windows) {
    const map = byAddress(windows);
    const before = divider.before.map(a => map[a]).filter(Boolean);
    const after = divider.after.map(a => map[a]).filter(Boolean);
    const vertical = divider.orientation === "vertical";
    const first = Math.min(...before.map(w => vertical ? w.x : w.y));
    const last = Math.max(...after.map(w => vertical ? w.x + w.width : w.y + w.height));
    return Math.round(first + (last - first - divider.thickness) / 2);
}
