.pragma library

// Keys that wake the Always On Display. A modifier held on its own is not typing, and
// Super is the first half of the shortcut that toggles the AOD: waking on it would
// let the rest of the chord raise it again at once.
const IGNORED = [
    Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta,
    Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Hyper_L, Qt.Key_Hyper_R
];

function keyWakes(key) {
    return IGNORED.indexOf(key) === -1;
}

// ── Continuous mouse motion wake ─────────────────────────────────────────────
// Wakes the Always On Display (OLED saver) when the user actively moves the mouse
// continuously for at least 1 second (1000ms) with at least 80px of total travel,
// avoiding wake-up on accidental desk bumps or brief touches.
let _firstMoveTime = 0;
let _lastMoveTime = 0;
let _lastX = -1;
let _lastY = -1;
let _lastScreen = "";
let _totalDistance = 0;

const MOTION_GAP_THRESHOLD_MS = 300;
const MOTION_WAKE_DURATION_MS = 1000;
const MOTION_MIN_DISTANCE_PX = 80;

function resetMotion() {
    _firstMoveTime = 0;
    _lastMoveTime = 0;
    _lastX = -1;
    _lastY = -1;
    _lastScreen = "";
    _totalDistance = 0;
}

function registerMouseMove(screenName, x, y) {
    const now = Date.now();

    // Start a new motion streak if idle gap exceeded or first movement
    if (_lastMoveTime === 0 || (now - _lastMoveTime) > MOTION_GAP_THRESHOLD_MS) {
        _firstMoveTime = now;
        _lastMoveTime = now;
        _lastX = x;
        _lastY = y;
        _lastScreen = screenName;
        _totalDistance = 0;
        return false;
    }

    // Accumulate travel distance when moving within the same screen
    if (_lastScreen === screenName && _lastX >= 0 && _lastY >= 0) {
        const dx = x - _lastX;
        const dy = y - _lastY;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist >= 1.0) {
            _totalDistance += dist;
        }
    }

    _lastMoveTime = now;
    _lastX = x;
    _lastY = y;
    _lastScreen = screenName;

    // Check if motion has been maintained continuously for >= 1000ms with real movement
    if ((now - _firstMoveTime) >= MOTION_WAKE_DURATION_MS && _totalDistance >= MOTION_MIN_DISTANCE_PX) {
        resetMotion();
        return true;
    }

    return false;
}
