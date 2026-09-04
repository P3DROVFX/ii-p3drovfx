.pragma library

// Where the touch controls should be drawn, given three sources that disagree.
//
// The strip is a layer surface tracking a window it does not own, and there is no
// single authority on where that window is right now:
//
//   the finger    — during a drag, ahead of everything, and the only one that is
//                   allowed to lead;
//   the request   — what was last dispatched to the compositor and has not been
//                   confirmed yet;
//   the report    — `hyprctl clients`, authoritative but late, and refreshed only
//                   when something asks it to.
//
// Getting the precedence wrong is what made the strip jump: releasing a drag dropped
// straight back to the report, and Hyprland emits no event for `movewindowpixel`, so
// the report was still the position the window had *before* the drag started. The
// strip snapped back across the screen and stayed there until some unrelated event
// happened to refresh the client list.

/// The value to draw with, in the precedence above. Any of the three may be absent,
/// which is what a negative number means everywhere here — no window is ever at a
/// negative surface coordinate, since the surface is the monitor.
function effective(live, requested, reported) {
    if (live >= 0)
        return live;
    if (requested >= 0)
        return requested;
    return reported;
}

/// Whether the compositor's report has caught up with what was asked for.
///
/// Rounding accounts for the dispatch being integers; the tolerance is for a
/// compositor that honoured the request approximately — gaps, borders, a size floor.
function settled(reported, requested, tolerance) {
    if (requested === undefined || requested === null || requested < 0)
        return true;
    var slack = tolerance === undefined ? 2 : tolerance;
    return Math.abs(Number(reported) - Number(requested)) <= slack;
}

/// Whether every requested value in a pending geometry has been confirmed.
///
/// `pending` and `reported` are { x, y, width, height }; a negative or absent entry in
/// `pending` was never requested and cannot hold the whole thing open.
function geometrySettled(reported, pending, tolerance) {
    var p = pending || {};
    var r = reported || {};
    return settled(r.x, p.x, tolerance)
        && settled(r.y, p.y, tolerance)
        && settled(r.width, p.width, tolerance)
        && settled(r.height, p.height, tolerance);
}
