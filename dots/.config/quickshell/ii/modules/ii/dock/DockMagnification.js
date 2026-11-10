.pragma library

// Pure motion and layout math for the dock's macOS-style magnification lens.
//
// Deliberately free of QML: DockContent.qml is far too large to instantiate in
// a test, so the decisions that shape the lens — how far it trails the cursor,
// how a wide widget follows it, how much room a magnified item needs — live
// here and are covered by tests/dock/.
//
// "Main axis" is the dock's long side (x when horizontal, y when vertical).
// Every distance is measured against the unmagnified layout: the lens never
// reads back the geometry it drives.

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

// ── Lens dynamics ─────────────────────────────────────────────────────────

// One critically damped spring step, integrated exactly for a constant target:
//   x(t) = T + (A + B t) e^(-w t),   A = x0 - T,   B = v0 + w A
// Being exact, the step is stable at any frame time — the shell may stall for
// 100 ms and the lens still resumes without exploding — and being critically
// damped it never overshoots, so the lens cannot grow past the cursor and come
// back, which at icon scale reads as a snap rather than as physics.
function springStep(position, velocity, target, omega, dt) {
    const w = Math.max(0.001, omega);
    const time = clamp(dt, 0, 0.1);
    if (!(time > 0))
        return { position: position, velocity: velocity };
    const decay = Math.exp(-w * time);
    const a = position - target;
    const b = velocity + w * a;
    const na = (a + b * time) * decay;
    return { position: target + na, velocity: b * decay - w * na };
}

// The stiffness that leaves the lens trailing a cursor moving at constant
// speed by `lagMs`: a tracking spring settles at 2v/w behind its target. The
// same number is the spring's time constant, so one profile value says both
// how much inertia the lens has and how long it takes to come to rest.
function trackingOmega(lagMs) {
    return 2000 / Math.max(1, lagMs);
}

// The stiffness that brings a step response within 2% of its target in
// `settleMs`: (1 + wt)e^(-wt) = 0.02 at wt ≈ 5.84, rounded up so the promise
// is "within settleMs", never "a hair after it".
function settleOmega(settleMs) {
    return 5850 / Math.max(1, settleMs);
}

// ── Influence field ───────────────────────────────────────────────────────

// One item's share of the field at `distance` from the pointer, 0..1. Cosine
// is the default and reaches zero with a flat slope, so an item entering the
// field starts growing from nothing instead of popping in.
function factorForDistance(distance, radius, curve) {
    const reach = Math.max(1, radius);
    if (!(distance < reach))
        return 0;
    const t = clamp(distance / reach, 0, 1);
    if (curve === "gaussian") {
        const sigma = reach / 2.5;
        const cutoff = Math.exp(-(reach * reach) / (2 * sigma * sigma));
        return Math.max(0, (Math.exp(-(distance * distance) / (2 * sigma * sigma)) - cutoff) / (1 - cutoff));
    }
    return 0.5 * (1 + Math.cos(Math.PI * t));
}

// The field at the pointer carries the lens' enter/exit strength: an item is
// magnified by how close the smoothed pointer is, scaled by how far the lens
// has grown in.
function weightForDistance(distance, radius, curve, strength) {
    return factorForDistance(distance, radius, curve) * clamp(strength, 0, 1);
}

// ── Cell-averaged field (a width that holds still) ───────────────────────
//
// Sampling the field at each item's centre made the dock's total width ripple
// as the pointer crossed a row of identical icons: the sum of point samples of
// a bump depends on where the samples fall relative to its peak. Averaging the
// field over each item's CELL (its slot plus the spacing, so the cells tile the
// lens axis) turns that sum into the integral of the field — constant while the
// lens is inside the dock, easing down only at its ends.

// Antiderivative of the cosine bump 0.5·(1 + cos(πx/r)) on [-r, r], flat 0
// outside it; G(r) - G(-r) = r.
function _cosineIntegral(x, r) {
    const t = clamp(x, -r, r);
    return 0.5 * (t + (r / Math.PI) * Math.sin(Math.PI * t / r));
}

// Mean of factorForDistance over [center - halfWidth, center + halfWidth]
// with the pointer at `pointer`.
function cellAverage(center, halfWidth, pointer, radius, curve) {
    const reach = Math.max(1, radius);
    const h = Math.max(0.5, halfWidth);
    const a = center - h - pointer;
    const b = center + h - pointer;
    if (a >= reach || b <= -reach)
        return 0;
    if (curve !== "gaussian")
        return (_cosineIntegral(b, reach) - _cosineIntegral(a, reach)) / (b - a);
    // Simpson's rule; the gaussian bump is smooth, 12 panels are plenty.
    const n = 12;
    const step = (b - a) / n;
    let sum = 0;
    for (let i = 0; i <= n; i++) {
        const x = a + i * step;
        const w = (i === 0 || i === n) ? 1 : (i % 2 === 1 ? 4 : 2);
        sum += w * factorForDistance(Math.abs(x), reach, curve);
    }
    return (sum * step / 3) / (b - a);
}

// An item's lens weight from its cell. `peak` is the average a cell of the
// reference width reaches centred under the pointer; dividing by it lets the
// item under the pointer still reach the full lens. Every weight is divided by
// the same constant, so the total stays as steady as the averages are.
function cellWeight(center, halfWidth, pointer, radius, curve, strength, peak) {
    const average = cellAverage(center, halfWidth, pointer, radius, curve);
    return clamp(average / Math.max(0.0001, peak), 0, 1) * clamp(strength, 0, 1);
}

// ── Layout ────────────────────────────────────────────────────────────────

// The visual scale of one item's content: the whole lens for a single icon, a
// muted share for a widget drawn as one wide card, whose body would otherwise
// grow several times as wide as its neighbours.
function contentScale(weight, scaleMax, contentFactor) {
    return 1 + Math.max(0, scaleMax - 1) * clamp(weight, 0, 1) * Math.max(0, contentFactor);
}

// The main-axis room that scale needs. The slot grows by exactly the amount
// the content grows — for every item type and every content factor — so a
// magnifying item pushes its neighbours along the dock instead of drawing over
// them. Returns 0 when the dock keeps its base spacing.
function layoutExtra(weight, scaleMax, extent, contentFactor, dynamicSpacing) {
    if (!dynamicSpacing)
        return 0;
    return Math.max(0, extent) * (contentScale(weight, scaleMax, contentFactor) - 1);
}

// ── Slot space: the lens measured in "how much each item grows" ───────────
//
// Pixels are the wrong ruler for a row of icons and wide cards. A 199 px card
// that grows by its muted share puts far less growth per pixel on the axis
// than the icons beside it, so the dock's width depended on where the lens
// stood — and sampling the card at its centre made it swell and shrink while
// the pointer travelled across it. In slot space every item spans the room
// its growth needs at the icon's rate: an icon one cell, a card
// magExtent·factor/iconExtent cells. Growth per unit is then the same
// everywhere, the total holds still by construction, the slot grows by
// exactly what the card grows, and crossing a 199 px card moves the lens only
// about two icons' worth — the card changes slowly instead of breathing.

// The slot-space cell of one item. Icons keep their own cell; a body-scaled
// card takes the icons' growth density.
function slotCell(lensCell, magExtent, magFactor, fromBody, iconExtent, iconPitch) {
    if (!fromBody)
        return Math.max(1, lensCell);
    return Math.max(1, Math.max(1, iconPitch) * Math.max(0, magExtent) * Math.max(0, magFactor) / Math.max(1, iconExtent));
}

// Map a lens coordinate into slot space. `cells` is the row in order, each
// { lensStart, lensCell, slotStart, slotCell }, tiling both axes. Inside a
// cell the position keeps its fraction; outside the row it extends 1:1.
function toSlotSpace(p, cells) {
    const n = cells ? cells.length : 0;
    if (n === 0)
        return p;
    const first = cells[0];
    if (p <= first.lensStart)
        return first.slotStart - (first.lensStart - p);
    for (let i = 0; i < n; i++) {
        const c = cells[i];
        const end = c.lensStart + c.lensCell;
        if (p <= end || i === n - 1) {
            if (p > end)
                return c.slotStart + c.slotCell + (p - end);
            const f = clamp((p - c.lensStart) / Math.max(1, c.lensCell), 0, 1);
            return c.slotStart + f * c.slotCell;
        }
    }
    return p;
}

