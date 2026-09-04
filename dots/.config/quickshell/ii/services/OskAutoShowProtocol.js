.pragma library

// The line protocol between the osk_autoshow daemon and the shell.
//
// One side is Rust, the other is QML, and the only thing joining them is the shape of
// a line of text. That seam is where this feature failed quietly for its whole life:
// the daemon reported `activate` on a machine where it could open no touchscreen, the
// shell waited for a `touch` line that was never coming, and neither end thought
// anything was wrong. The protocol is parsed here so both the parse and the "can
// anything actually trigger this" question can be checked without a touchscreen.
//
// See scripts/osk/README.md for the daemon's half of the contract.

/// Parses one line into { kind, ... }, or { kind: "unknown" }.
///
/// `x` and `y` are 0..1 screen coordinates, or -1 when the device has no absolute
/// position to report — which a relative pointer never does.
function parseLine(line) {
    var text = String(line === undefined || line === null ? "" : line).trim();
    if (text.length === 0)
        return { kind: "unknown" };

    var parts = text.split(/\s+/);
    switch (parts[0]) {
    case "activate":
        return { kind: "activate" };
    case "deactivate":
        return { kind: "deactivate" };
    case "key":
        return { kind: "key" };
    case "unavailable":
        return { kind: "unavailable" };
    case "denied":
        return { kind: "denied" };
    case "touch":
    case "pen":
    case "mouse":
        return {
            kind: "pointer",
            pointer: parts[0],
            x: numberOr(parts[1], -1),
            y: numberOr(parts[2], -1)
        };
    case "devices":
        return {
            kind: "devices",
            touch: intOr(parts[1], 0),
            pen: intOr(parts[2], 0),
            mouse: intOr(parts[3], 0)
        };
    default:
        return { kind: "unknown" };
    }
}

function numberOr(value, fallback) {
    var number = parseFloat(value);
    return isFinite(number) ? number : fallback;
}

function intOr(value, fallback) {
    var number = parseInt(value, 10);
    return isFinite(number) ? number : fallback;
}

/// Whether a given pointer kind is allowed to raise the keyboard.
///
/// Touch and pen default on; the mouse defaults off and should stay off wherever there
/// is a touchscreen. See Config.options.osk.autoShow.allowMouse for why it exists.
function pointerAllowed(kind, opts) {
    var o = opts || {};
    if (kind === "touch")
        return o.allowTouch === undefined ? true : Boolean(o.allowTouch);
    if (kind === "mouse")
        return o.allowMouse === undefined ? false : Boolean(o.allowMouse);
    if (kind === "pen")
        return o.allowPen === undefined ? true : Boolean(o.allowPen);
    return false;
}

/// Whether anything on this machine can fire the trigger, given what the daemon found
/// and which kinds the user left switched on. False here is the difference between
/// "broken" and "there is no touchscreen".
function anyTriggerDevice(inventory, opts) {
    var i = inventory || {};
    return ((i.touch || 0) > 0 && pointerAllowed("touch", opts))
        || ((i.pen || 0) > 0 && pointerAllowed("pen", opts))
        || ((i.mouse || 0) > 0 && pointerAllowed("mouse", opts));
}
