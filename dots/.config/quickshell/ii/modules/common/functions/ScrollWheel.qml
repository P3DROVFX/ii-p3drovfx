pragma Singleton
import Quickshell

/**
 * How far one wheel event moves a scroll surface, in pixels. The one rule
 * behind "Faster touchpad scrolling": StyledFlickable, StyledListView,
 * TouchpadScrollHandler and the dock all ask here, so no surface drifts.
 */
Singleton {
    // A mouse wheel's angleDelta comes in multiples of ±120, a touchpad's is
    // small and continuous. With faster scrolling off, a touchpad moves the
    // content exactly as far as Qt's own Flickable would: its pixelDelta.
    // `settings` carries fasterTouchpadScroll, mouseScrollDeltaThreshold,
    // mouseScrollFactor and touchpadScrollFactor, named as in the config.
    function step(angle, pixel, settings) {
        const threshold = settings?.mouseScrollDeltaThreshold ?? 120;
        if (Math.abs(angle) >= threshold)
            return angle / threshold * (settings?.mouseScrollFactor ?? 120);
        if (settings?.fasterTouchpadScroll ?? false)
            return angle / threshold * (settings?.touchpadScrollFactor ?? 450);
        return pixel !== 0 ? pixel : angle / 8;
    }
}
