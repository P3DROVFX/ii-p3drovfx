pragma Singleton
import Quickshell

/**
 * How far one wheel event moves a scroll surface, in pixels. The one rule
 * behind "Faster touchpad scrolling": StyledFlickable, StyledListView,
 * TouchpadScrollHandler and the dock all ask here, so no surface drifts.
 */
Singleton {
    // Qt reports a finger's angleDelta as 12 per pixel (qtbase
    // qwaylandinputdevice.cpp, `delta * -12`) and a wheel notch as 120. A touchpad
    // moving 10 px therefore already reads as a notch, and used to scroll 12 times
    // the finger at that threshold. Notches are told apart by their value instead.
    readonly property real touchpadAnglePerPixel: 12
    // A finger's angle is a whole notch by chance (about one event in 250). Any
    // touchpad event this recent makes a whole-notch event a touchpad event too.
    readonly property int touchpadWindowMs: 250
    property real _lastTouchpadMs: 0

    /** Whether this event is a mouse-wheel notch. Records touchpad events. */
    function isNotch(angle, settings) {
        const now = Date.now();
        if (angle % 120 !== 0) {
            _lastTouchpadMs = now;
            return false;
        }
        if (Math.abs(angle) < (settings?.mouseScrollDeltaThreshold ?? 120))
            return false;
        return now - _lastTouchpadMs >= touchpadWindowMs;
    }

    /** Pixels one mouse-wheel notch moves: mouseScrollFactor per notch. */
    function notchStep(angle, settings) {
        const threshold = settings?.mouseScrollDeltaThreshold ?? 120;
        return angle / threshold * (settings?.mouseScrollFactor ?? 120);
    }

    // The touchpad speed setting that means the finger's own speed (100%)
    readonly property real touchpadSpeedOne: 225

    /**
     * Pixels one touchpad event moves: the finger's own distance, scaled by the touchpad
     * speed setting while faster scrolling is on.
     */
    function touchpadStep(angle, pixel, settings) {
        const finger = pixel !== 0 ? pixel : angle / touchpadAnglePerPixel;
        const speed = settings?.fasterTouchpadScroll ? (settings?.touchpadScrollFactor ?? 450) / touchpadSpeedOne : 1;
        return finger * speed;
    }

    function step(angle, pixel, settings) {
        return isNotch(angle, settings) ? notchStep(angle, settings) : touchpadStep(angle, pixel, settings);
    }
}
