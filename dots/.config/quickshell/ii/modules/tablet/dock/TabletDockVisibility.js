.pragma library

// Which parts of the tablet taskbar are on screen right now.
//
// The rules are small but they interlock: the app row answers to four different
// preferences plus the shade, the navigation pill can outlive the app row, the
// search pill cannot, and the surface itself exists only while something inside it
// does. Written as QML bindings they were five expressions spread over forty lines
// of TabletDockWindow, and a change to one of them silently changed the others —
// which is how the row came to vanish the moment any window opened, with no way to
// tell a deliberate auto-hide from a broken binding.
//
// `state` is a plain record so the whole table can be exercised without a
// compositor:
//
//   { showAppRow, autoHideOnOccupiedWorkspace, keepNavigationVisible,
//     showNavigation, showSearchBar, showWorkspaceArrows,
//     pinned, anySidebarOpen, workspaceEmpty, configReady, screenLocked }

function bool(value, fallback) {
    return value === undefined || value === null ? fallback : Boolean(value);
}

/// The launcher row: pinned apps, running apps and the drawer button.
///
/// Pinning wins over everything except the row being switched off entirely — that is
/// what "pinned" means — and the shade covering the dock hides it either way.
function appsRevealed(state) {
    var s = state || {};
    if (!bool(s.showAppRow, true))
        return false;
    if (bool(s.pinned, false))
        return true;
    if (bool(s.anySidebarOpen, false))
        return false;
    // Off by default: the reference product's taskbar is persistent. Left in because
    // a bare home screen is a real preference, not because hiding is the norm.
    if (!bool(s.autoHideOnOccupiedWorkspace, false))
        return true;
    return bool(s.workspaceEmpty, true);
}

/// Back / Home / Recents. Outlives the app row when the user asks it to, because it
/// is navigation rather than launching — losing it strands a device with no keyboard.
function navigationRevealed(state) {
    var s = state || {};
    if (!bool(s.showNavigation, true))
        return false;
    return appsRevealed(s) || bool(s.keepNavigationVisible, true);
}

/// The search pill belongs to the launcher row and comes and goes with it.
function searchRevealed(state) {
    var s = state || {};
    return bool(s.showSearchBar, true) && appsRevealed(s);
}

/// The home-screen arrows follow the dock as a whole: moving between home screens is
/// useful exactly when something is open and the apps have got out of the way.
function workspaceArrowsRevealed(state) {
    var s = state || {};
    return bool(s.showWorkspaceArrows, true) && dockRevealed(s);
}

/// Whether the dock has anything to draw at all.
function dockRevealed(state) {
    return appsRevealed(state) || navigationRevealed(state);
}

/// Whether the layer surface should exist. Config not being loaded yet is not the
/// same as everything being switched off, so it is checked separately.
function surfaceVisible(state) {
    var s = state || {};
    return bool(s.configReady, false) && !bool(s.screenLocked, false) && dockRevealed(s);
}
