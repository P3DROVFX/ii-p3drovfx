import QtQuick
import QtQuick.Controls
import qs.modules.common

Flickable {
    id: root
    maximumFlickVelocity: 3500
    boundsBehavior: Flickable.DragOverBounds

    property real touchpadScrollFactor: Config?.options.interactions.scrolling.touchpadScrollFactor ?? 100
    property real mouseScrollFactor: Config?.options.interactions.scrolling.mouseScrollFactor ?? 50
    property real mouseScrollDeltaThreshold: Config?.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120
    // Accumulated scroll destination so wheel deltas stack while animating
    property real scrollTargetY: 0

    readonly property real minY: root.originY - root.topMargin
    readonly property real maxY: Math.max(minY, root.originY + root.contentHeight - root.height + root.bottomMargin)
    readonly property real maxBounceOvershoot: Math.min(60, Math.max(30, root.height * 0.12))

    // The Behavior below must smooth wheel jumps only. Left unguarded it also
    // intercepts the contentY that Flickable writes on every drag and flick
    // frame, which fights its own physics and makes long pages feel like they
    // stutter under the cursor.
    property bool _wheelScrolling: false

    ScrollBar.vertical: StyledScrollBar {}

    function triggerBounceRebound(targetBound) {
        bounceAnim.stop();
        bounceAnim.to = targetBound;
        root.scrollTargetY = targetBound;
        bounceAnim.start();
    }

    Timer {
        id: reboundTimer
        interval: 90
        repeat: false
        onTriggered: {
            if (root.dragging || root.flicking)
                return;
            if (root.contentY < root.minY) {
                root.triggerBounceRebound(root.minY);
            } else if (root.contentY > root.maxY) {
                root.triggerBounceRebound(root.maxY);
            }
        }
    }

    NumberAnimation {
        id: bounceAnim
        target: root
        property: "contentY"
        duration: Math.round(350 * Appearance.animMultiplier)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        onStopped: {
            root._wheelScrolling = false;
            root.scrollTargetY = root.contentY;
        }
    }

    // Do not overlay the content with a MouseArea: that would replace every
    // delegate's pointer cursor with the default arrow while scrolling is on.
    WheelHandler {
        enabled: root.interactive
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: wheelEvent => {
            const delta = wheelEvent.angleDelta.y / root.mouseScrollDeltaThreshold;
            // The angleDelta.y of a touchpad is usually small and continuous,
            // while that of a mouse wheel is typically in multiples of ±120.
            var scrollFactor = Math.abs(wheelEvent.angleDelta.y) >= root.mouseScrollDeltaThreshold ? root.mouseScrollFactor : root.touchpadScrollFactor;
            const step = delta * scrollFactor;

            bounceAnim.stop();

            const currentPos = (scrollAnim.running || bounceAnim.running) ? root.scrollTargetY : root.contentY;
            const rawTarget = currentPos - step;
            var targetY = rawTarget;
            var isOvershooting = false;

            if (rawTarget < root.minY) {
                isOvershooting = true;
                const currentOvershoot = Math.max(0, root.minY - currentPos);
                const resistance = Math.max(0.1, 0.45 * (1.0 - (currentOvershoot / root.maxBounceOvershoot)));
                const effectiveStep = (currentPos <= root.minY) ? (step * resistance) : ((step - (currentPos - root.minY)) * resistance);
                const newOvershoot = Math.min(root.maxBounceOvershoot, currentOvershoot + effectiveStep);
                targetY = root.minY - newOvershoot;
            } else if (rawTarget > root.maxY) {
                isOvershooting = true;
                const stepDown = -step;
                const currentOvershoot = Math.max(0, currentPos - root.maxY);
                const resistance = Math.max(0.1, 0.45 * (1.0 - (currentOvershoot / root.maxBounceOvershoot)));
                const effectiveStep = (currentPos >= root.maxY) ? (stepDown * resistance) : ((stepDown - (root.maxY - currentPos)) * resistance);
                const newOvershoot = Math.min(root.maxBounceOvershoot, currentOvershoot + effectiveStep);
                targetY = root.maxY + newOvershoot;
            }

            root.scrollTargetY = targetY;
            root._wheelScrolling = true;
            root.contentY = targetY;
            wheelEvent.accepted = true;

            if (isOvershooting || targetY < root.minY || targetY > root.maxY) {
                reboundTimer.restart();
            } else {
                reboundTimer.stop();
            }
        }
    }

    Behavior on contentY {
        enabled: root._wheelScrolling && !bounceAnim.running && !root.dragging && !root.flicking
        NumberAnimation {
            id: scrollAnim
            duration: Appearance.animation.scroll.duration
            easing.type: Appearance.animation.scroll.type
            easing.bezierCurve: Appearance.animation.scroll.bezierCurve
            onStopped: {
                if (root.contentY < root.minY || root.contentY > root.maxY) {
                    reboundTimer.restart();
                } else {
                    root._wheelScrolling = false;
                }
            }
        }
    }

    onDraggingChanged: {
        if (root.dragging) {
            bounceAnim.stop();
            reboundTimer.stop();
            root._wheelScrolling = false;
        }
    }

    // Keep target synced when not animating (e.g., drag/flick or programmatic changes)
    onContentYChanged: {
        if (!scrollAnim.running && !bounceAnim.running) {
            root.scrollTargetY = root.contentY;
        }
    }

}
