import QtQuick
import qs.modules.common

/**
 * The scrolling settings for a plain Flickable, ListView or GridView: "Faster
 * touchpad scrolling" and "Same wheel step in every list". Declare it inside the
 * view and point `flickable` at it. With both settings off the handler is
 * disabled and the view keeps Qt's own wheel handling.
 * For a ScrollView, declare it inside the content item and point `flickable`
 * at the ScrollView's contentItem. StyledFlickable and StyledListView carry
 * their own handler; don't add this to them.
 */
WheelHandler {
    id: root

    required property Flickable flickable
    readonly property bool featureEnabled: Config.options?.interactions?.scrolling?.fasterTouchpadScroll ?? false
    readonly property bool uniformMouseWheel: Config.options?.interactions?.scrolling?.uniformMouseWheel ?? false
    property real touchpadScrollFactor: Config.options?.interactions?.scrolling?.touchpadScrollFactor ?? 450
    property real mouseScrollFactor: Config.options?.interactions?.scrolling?.mouseScrollFactor ?? 120
    property real mouseScrollDeltaThreshold: Config.options?.interactions?.scrolling?.mouseScrollDeltaThreshold ?? 120

    /**
     * The wheel moved a flickable. Unlike a drag, this raises no
     * movementStarted, so a view that pauses auto-scrolling once the reader
     * takes over has to listen here as well.
     */
    signal scrolled()

    // Where the wheel has asked the animated flickable to go, so deltas stack
    // while the animation runs
    property real scrollTargetY: 0

    readonly property real minY: flickable ? root.lowerBound(flickable) : 0
    readonly property real maxY: flickable ? root.upperBound(flickable) : 0

    enabled: (featureEnabled || uniformMouseWheel) && flickable !== null && flickable.interactive && maxY - minY > 1
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    // Only the flickable moves; the handler's own parent stays put
    target: null

    function lowerBound(f) {
        return f.originY - f.topMargin;
    }

    function upperBound(f) {
        return Math.max(root.lowerBound(f), f.originY + f.contentHeight - f.height + f.bottomMargin);
    }

    // Rejecting a wheel event from a WheelHandler does not hand it back to Qt:
    // neither this flickable nor an enclosing one would scroll. So the edge
    // hand-off Qt normally does is done here, by moving the nearest enclosing
    // vertical scroller instead.
    function enclosingScroller(f) {
        for (let p = f.parent; p; p = p.parent) {
            if (p.contentY === undefined || p.flickableDirection === undefined)
                continue;
            if (p.interactive && p.flickableDirection !== Flickable.HorizontalFlick
                    && root.upperBound(p) - root.lowerBound(p) > 1)
                return p;
        }
        return null;
    }

    // The angleDelta.y of a touchpad is small and continuous, a mouse wheel's
    // comes in multiples of ±120. Same rule as StyledFlickable.wheelStep(): with
    // faster scrolling off, a touchpad moves as far as Qt's own Flickable would.
    function wheelStep(event) {
        const angle = event.angleDelta.y;
        if (Math.abs(angle) >= root.mouseScrollDeltaThreshold)
            return angle / root.mouseScrollDeltaThreshold * root.mouseScrollFactor;
        if (root.featureEnabled)
            return angle / root.mouseScrollDeltaThreshold * root.touchpadScrollFactor;
        return event.pixelDelta.y !== 0 ? event.pixelDelta.y : angle / 8;
    }

    // Horizontal-only deltas never get here: WheelHandler.orientation is
    // vertical, so Qt routes those as usual.
    onWheel: event => {
        const step = root.wheelStep(event);
        event.accepted = true;

        for (let f = root.flickable; f; f = root.enclosingScroller(f)) {
            const animating = scrollAnim.running && scrollAnim.target === f;
            const base = animating ? root.scrollTargetY : f.contentY;
            const targetY = Math.max(root.lowerBound(f), Math.min(root.upperBound(f), base - step));
            if (Math.abs(targetY - base) < 0.5)
                continue;
            scrollAnim.stop();
            root.scrollTargetY = targetY;
            scrollAnim.target = f;
            scrollAnim.to = targetY;
            scrollAnim.start();
            root.scrolled();
            return;
        }
    }

    property NumberAnimation _scrollAnim: NumberAnimation {
        id: scrollAnim
        property: "contentY"
        duration: Appearance.animation.scroll.duration
        easing.type: Appearance.animation.scroll.type
        easing.bezierCurve: Appearance.animation.scroll.bezierCurve
    }

    // A drag or flick owns contentY from its first frame
    property Connections _movement: Connections {
        target: scrollAnim.target
        ignoreUnknownSignals: true
        function onMovementStarted() {
            scrollAnim.stop();
        }
    }
}
