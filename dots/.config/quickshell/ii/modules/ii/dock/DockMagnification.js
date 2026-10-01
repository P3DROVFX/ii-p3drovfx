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
