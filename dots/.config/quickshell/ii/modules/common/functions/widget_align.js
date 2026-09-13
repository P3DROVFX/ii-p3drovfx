.pragma library

// Aligning and distributing a selection of desktop widgets, as arithmetic.
//
// Pure for the same reason `widget_nudge.js` is: nothing about a rendered
// widget is reachable from qmltestrunner, so the part worth checking - where
// each member lands, and what happens when one of them cannot get there - has
// to live somewhere a test can call. The canvas measures the boxes and writes
// the positions; everything between is here.
//
// A member is `{ id, box: { x, y, width, height }, minX, maxX, minY, maxY }`.
// `box` is the DRAWN rectangle, which is not the stored position: a widget's
// Item scale is applied around its centre, so the two differ by the offsets
// AbstractBackgroundWidget publishes. The answers are therefore DELTAS, which
// are the same in either frame - the caller adds them to whatever coordinate
// it stores, and nothing here has to know which frame that is.

var MODES = [
    "left", "hcenter", "right",
    "top", "vcenter", "bottom",
    "hdistribute", "vdistribute"
];

function isHorizontal(mode) {
    return mode === "left" || mode === "hcenter" || mode === "right" || mode === "hdistribute";
}

function isDistribute(mode) {
    return mode === "hdistribute" || mode === "vdistribute";
}

// The fewest members a mode does anything with. Aligning two is a real answer;
// distributing two is not - the two ends of a distribution are held fixed, so
// with nothing between them there is nothing to place.
function minimumMembers(mode) {
    return isDistribute(mode) ? 3 : 2;
}

// The selection's own bounding box, which is what "centre" means here. The
// average of the members' centres is the other candidate and it is the wrong
// one: it drifts toward whichever side happens to hold more widgets, so
// centring a selection twice moves it the second time.
function bounds(members) {
    var list = asList(members);
    if (list.length === 0) return null;
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (var i = 0; i < list.length; i++) {
        var box = list[i].box;
        if (!box) continue;
        minX = Math.min(minX, box.x);
        minY = Math.min(minY, box.y);
        maxX = Math.max(maxX, box.x + box.width);
        maxY = Math.max(maxY, box.y + box.height);
    }
    if (!isFinite(minX)) return null;
    return { x: minX, y: minY, width: maxX - minX, height: maxY - minY };
}

// Where each member's box wants to start, before any clamp. Distribution keeps
// the two OUTERMOST members exactly where they are and shares what is left
// between the rest: an equal gap is the only reading of "distribute" that does
// not also move the selection.
function wantedStarts(members, mode) {
    var list = asList(members);
    var frame = bounds(list);
    if (frame === null) return {};
    var horizontal = isHorizontal(mode);
    var out = {};

    if (!isDistribute(mode)) {
        for (var i = 0; i < list.length; i++) {
            var box = list[i].box;
            if (!box) continue;
            if (mode === "left") out[list[i].id] = frame.x;
            else if (mode === "right") out[list[i].id] = frame.x + frame.width - box.width;
            else if (mode === "hcenter") out[list[i].id] = frame.x + (frame.width - box.width) / 2;
            else if (mode === "top") out[list[i].id] = frame.y;
            else if (mode === "bottom") out[list[i].id] = frame.y + frame.height - box.height;
            else if (mode === "vcenter") out[list[i].id] = frame.y + (frame.height - box.height) / 2;
        }
        return out;
    }

    var ordered = sortedAlong(list, horizontal);
    if (ordered.length < 3) return {};
    var span = horizontal ? frame.width : frame.height;
    var occupied = 0;
    for (var j = 0; j < ordered.length; j++)
        occupied += horizontal ? ordered[j].box.width : ordered[j].box.height;
    // Overlapping boxes give a negative gap, and that is a legitimate answer:
    // it spreads them evenly through the room they have rather than refusing.
    var gap = (span - occupied) / (ordered.length - 1);
    var cursor = horizontal ? frame.x : frame.y;
    for (var k = 0; k < ordered.length; k++) {
        out[ordered[k].id] = cursor;
        cursor += (horizontal ? ordered[k].box.width : ordered[k].box.height) + gap;
    }
    return out;
}

// The move each member makes, keyed by id, with each member's own clamp
// applied. Members that would not move are left out, so a second press of the
// same button commits nothing rather than writing every unchanged position
// back and filling the undo stack.
//
// Clamped INDIVIDUALLY, unlike a nudge: a nudge moves the cluster rigidly and
// so shrinks to the smallest headroom, but an alignment is a statement about
// each member's own edge. One member against a wall must not drag the rest
// away from the line they were asked to sit on.
function deltas(members, mode) {
    var list = asList(members);
    if (MODES.indexOf(mode) === -1) return {};
    if (list.length < minimumMembers(mode)) return {};
    var wanted = wantedStarts(list, mode);
    var horizontal = isHorizontal(mode);
    var out = {};
    for (var i = 0; i < list.length; i++) {
        var member = list[i];
        if (!member.box || !(member.id in wanted)) continue;
        var from = horizontal ? member.box.x : member.box.y;
        var delta = wanted[member.id] - from;
        var low = horizontal ? member.minX : member.minY;
        var high = horizontal ? member.maxX : member.maxY;
        var stored = horizontal ? member.x : member.y;
        delta = clampDelta(delta, stored, low, high);
        if (Math.abs(delta) < 0.5) continue;
        out[member.id] = horizontal ? { dx: delta, dy: 0 } : { dx: 0, dy: delta };
    }
    return out;
}

// How far this member may actually travel, given where its STORED coordinate
// is and what its own clamp allows. The delta is measured off the drawn box
// and applied to the stored coordinate, which is what makes the two frames
// interchangeable here.
function clampDelta(delta, stored, minimum, maximum) {
    if (delta === 0) return 0;
    var low = isNumber(minimum) ? minimum : -Infinity;
    var high = isNumber(maximum) ? maximum : Infinity;
    var target = Math.max(low, Math.min(high, stored + delta));
    return target - stored;
}

function sortedAlong(list, horizontal) {
    var out = [];
    for (var i = 0; i < list.length; i++)
        if (list[i].box) out.push(list[i]);
    out.sort(function (a, b) {
        return horizontal ? (a.box.x - b.box.x) : (a.box.y - b.box.y);
    });
    return out;
}

function isNumber(value) {
    return typeof value === "number" && isFinite(value);
}

// Array-LIKENESS, not Array.isArray: a list that has crossed a QML property
// boundary keeps its indices and its length and loses the brand.
function asList(value) {
    if (value === null || value === undefined) return [];
    if (typeof value.length !== "number") return [];
    var out = [];
    for (var index = 0; index < value.length; index++) {
        if (value[index]) out.push(value[index]);
    }
    return out;
}
