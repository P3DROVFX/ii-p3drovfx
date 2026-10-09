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

    /**
     * Whether this event comes from a mouse wheel. Records touchpad events.
     * `phase` is the WheelEvent's: Qt gives a scroll phase to finger (touchpad)
     * scrolls only, so a wheel is NoScrollPhase however finely it reports and
     * however the compositor's scroll_factor scales it (a high-res wheel at 0.1
     * sends 1.5° steps that the angle rule below takes for a touchpad).
     * Without a phase, a whole notch of angle is a wheel.
     */
    function isNotch(angle, settings, phase) {
        const now = Date.now();
        if (phase !== undefined) {
            if (phase !== Qt.NoScrollPhase)
                _lastTouchpadMs = now;
            // A sideways tilt leaves this axis at 0: no step to take
            return phase === Qt.NoScrollPhase && angle !== 0;
        }
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

    // The default touchpad speed setting (100% on the slider)
    readonly property real touchpadSpeedDefault: 450

    /**
     * Pixels one touchpad event moves: the finger's own distance, or, while faster
     * scrolling is on, touchpadScrollFactor px per notch's worth of angle (10 px of
     * finger). That is the gain fasterTouchpadScroll always had; the compositor's
     * touchpad scroll_factor shrinks the finger's distance before it gets here.
     */
    function touchpadStep(angle, pixel, settings) {
        const finger = pixel !== 0 ? pixel : angle / touchpadAnglePerPixel;
        const speed = settings?.fasterTouchpadScroll ? (settings?.touchpadScrollFactor ?? 450) * touchpadAnglePerPixel / 120 : 1;
        return finger * speed;
    }

    function step(angle, pixel, settings, phase) {
        return isNotch(angle, settings, phase) ? notchStep(angle, settings) : touchpadStep(angle, pixel, settings);
    }
}
