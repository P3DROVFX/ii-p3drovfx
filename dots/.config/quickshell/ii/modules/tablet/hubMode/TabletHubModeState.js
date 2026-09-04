.pragma library

// When the hub-mode surface is on screen, and why.
//
// Five conditions decide it and they do not compose the way reading them in order
// suggests: a preview overrides every one of the other four including the feature
// being switched off, the charging requirement is satisfied rather than met on a
// device with no battery, and "dismissed" is scoped to one idle period rather than
// being a preference. Written inline they were one long boolean that could only be
// checked by plugging a tablet in and waiting two minutes.
//
// `state` is a plain record:
//
//   { enable, requireCharging, batteryAvailable, pluggedIn, idle, dismissed,
//     pauseWhilePlaying, mediaPlaying, screenLocked, previewRequested }

function bool(value, fallback) {
    return value === undefined || value === null ? fallback : Boolean(value);
}

/// Whether the power precondition is met. No battery at all counts as satisfied: a
/// desktop-class device that reports no battery is always on mains.
function powerSatisfied(state) {
    var s = state || {};
    if (!bool(s.requireCharging, true))
        return true;
    if (!bool(s.batteryAvailable, false))
        return true;
    return bool(s.pluggedIn, false);
}

/// Everything except the idle timer: the feature is on, the power condition holds,
/// and the screen is not locked.
function armed(state) {
    var s = state || {};
    return bool(s.enable, false) && powerSatisfied(s) && !bool(s.screenLocked, false);
}

/// A preview the user asked for. Ignores `enable`, the cable and the idle timer —
/// asking for one is what someone does while deciding whether to switch it on — but
/// not the lock screen, which owns every layer above it anyway.
function previewing(state) {
    var s = state || {};
    return bool(s.previewRequested, false) && !bool(s.screenLocked, false);
}

/// Something is playing and taking the screen would interrupt watching it.
function mediaHolding(state) {
    var s = state || {};
    return bool(s.pauseWhilePlaying, true) && bool(s.mediaPlaying, false);
}

function shouldShow(state) {
    var s = state || {};
    if (previewing(s))
        return true;
    return armed(s) && bool(s.idle, false) && !bool(s.dismissed, false) && !mediaHolding(s);
}
