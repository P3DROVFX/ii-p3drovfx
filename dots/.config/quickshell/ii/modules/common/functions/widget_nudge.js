.pragma library
// Ported verbatim from XephyLon/immaterial-impulse (GPL-3.0), v0.32.0:
//   dots/.config/quickshell/imi/modules/common/functions/widget_nudge.js
// Original author: XephyLon. Reached from QML through WidgetNudge.qml.

// Moving a selected widget with the arrow keys, as arithmetic.
//
// Pure for the reason every other decision on this canvas is: nothing about a
// rendered widget is reachable from qmltestrunner, so the part worth checking
// - where a press lands, and what a group does when one member reaches a wall
// - has to live somewhere a test can call.
//
// One press is one lattice cell. There is deliberately no fine mode: a widget
// placed by keyboard lands on the same grid as one placed by mouse, which is
// what makes the two ways of moving a widget agree about where things sit.

// The lattice step for a key, or null for a key this does not answer. Returned
// as a direction rather than a distance so the caller supplies the lattice -
// the canvas scales it, and a module that read a token would be a second place
// that has to agree about the cell size.
function direction(key, keys) {
    const k = keys || {};
    if (key === k.left) return { dx: -1, dy: 0 };
    if (key === k.right) return { dx: 1, dy: 0 };
    if (key === k.up) return { dx: 0, dy: -1 };
    if (key === k.down) return { dx: 0, dy: 1 };
    return null;
}

// Where one press lands: a whole cell along, snapped back onto the lattice.
//
// The snap is not redundant. A widget can sit OFF the lattice - the edge snap
// parks it one gap from a neighbour's edge (measured: 465 on a 12px lattice),
// and a stored position predating a lattice change is off it too. Adding a
// cell to 465 gives 477, which is still off; rounding the sum lands 480 and
// every press after it is a clean cell. The first press of such a burst
// therefore moves 15px rather than 12, which is the whole point: it is the
// press that gets the widget onto the grid.
//
// `origin` is the lattice's own offset in this axis (AbstractWidget's
// snapOffsetX/Y), because a subclass whose coordinate is not the one it stores
// moves the lattice into the frame it means something in.
function step(current, delta, lattice, origin) {
    const cell = positive(lattice);
    if (cell === 0) return current + delta;
    const base = origin || 0;
    return Math.round((current + delta - base) / cell) * cell + base;
}

// The delta a whole selection may travel, given what each member can take.
//
// A group moves rigidly - the same answer the group drag gives, where the
// cluster stops when its FIRST member reaches an edge rather than deforming
// as members clamp individually. So the shared delta is shrunk to the
// smallest headroom in the direction of travel, and a selection already
// against the wall does not move at all (which is what makes a nudge into a
// wall commit nothing, rather than writing every member's unchanged position
// back and filling the undo stack).
//
// Members are { x, y, minX, maxX, minY, maxY }; the bounds are each member's
// own clamp, since widgets differ in size.
function groupDelta(members, dx, dy) {
    const list = asList(members);
    if (list.length === 0) return { dx: 0, dy: 0 };
    let allowedX = dx;
    let allowedY = dy;
    for (const member of list) {
        allowedX = shrink(allowedX, member.x, member.minX, member.maxX);
        allowedY = shrink(allowedY, member.y, member.minY, member.maxY);
    }
    return { dx: allowedX, dy: allowedY };
}

// How far one member may travel before its own clamp bites, capped by what the
// group has already agreed to.
function shrink(delta, value, minimum, maximum) {
    if (delta === 0) return 0;
    const low = isNumber(minimum) ? minimum : -Infinity;
    const high = isNumber(maximum) ? maximum : Infinity;
    if (delta > 0) return Math.max(0, Math.min(delta, high - value));
    return Math.min(0, Math.max(delta, low - value));
}

function isNumber(value) {
    return typeof value === "number" && isFinite(value);
}

function positive(value) {
    return isNumber(value) && value > 0 ? value : 0;
}

// Array-LIKENESS, not Array.isArray: a list that has crossed a QML property
// boundary keeps its indices and its length and loses the brand.
function asList(value) {
    if (value === null || value === undefined) return [];
    if (typeof value.length !== "number") return [];
    const out = [];
    for (let index = 0; index < value.length; index++) {
        if (value[index]) out.push(value[index]);
    }
    return out;
}
