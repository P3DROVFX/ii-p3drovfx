import QtQuick
import qs.services
import qs.modules.common

/**
 * The enter and exit every ii context menu card plays: the card grows out of
 * the corner it opened from while it fades in, and leaves as one piece.
 *
 * Two scalars, driven by explicit animations rather than Behaviors: the exit
 * must say when it is DONE (`exitFinished`, the host unmaps then), and a
 * re-open mid-exit turns around from wherever the card is.
 *
 * Comfortable is the motion the menus always had (0.85 -> 1 on
 * elementMoveEnter, fade on elementMoveFast, out on elementMoveExit).
 * Compact is a smaller card and moves like one: a shorter grow from 0.92 on
 * the popup clock, a quicker fade, a 150 ms exit that barely shrinks.
 *
 * The host binds `opacity: motion.reveal`, `scale: motion.scale` and
 * `transformOrigin` itself, and plays enter/exit on its own events.
 */
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property bool compact: ContextMenus.compact
    property bool closing: false
    signal exitFinished()

    property real grow: 0
    property real reveal: 0
    readonly property real scaleFrom: root.compact ? 0.92 : 0.85
    readonly property real scale: root.scaleFrom + (1 - root.scaleFrom) * root.grow
    readonly property bool _motion: !Appearance.reducedMotion

    readonly property int growDuration: root.compact ? Appearance.animation.popupEnter.duration
        : Appearance.animation.elementMoveEnter.duration
    readonly property int fadeDuration: root.compact ? Appearance.animation.popupExit.duration
        : Appearance.animation.elementMoveFast.duration
    readonly property int exitDuration: root.compact ? Appearance.animation.popupExit.duration
        : Appearance.animation.elementMoveExit.duration
    readonly property real exitGrow: root.compact ? 0.6 : 0.5

    ParallelAnimation {
        id: enterMotion
        NumberAnimation {
            target: root
            property: "grow"
            to: 1
            duration: root._motion ? root.growDuration : 0
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "reveal"
            to: 1
            duration: root._motion ? root.fadeDuration : 0
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    ParallelAnimation {
        id: exitMotion
        NumberAnimation {
            target: root
            property: "grow"
            to: root.exitGrow
            duration: root._motion ? root.exitDuration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        NumberAnimation {
            target: root
            property: "reveal"
            to: 0
            duration: root._motion ? root.exitDuration : 0
            easing.type: Appearance.animation.elementMoveExit.type
            easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        }
        // One more frame before the unmap, so the surface's last committed
        // buffer is the transparent one and never a half-faded card.
        onFinished: unmapDelay.restart()
    }
    Timer {
        id: unmapDelay
        interval: 32
        onTriggered: { if (root.closing) root.exitFinished(); }
    }

    function playEnter(fromStart: bool): void {
        exitMotion.stop();
        unmapDelay.stop();
        if (fromStart) {
            root.grow = 0;
            root.reveal = 0;
        }
        enterMotion.restart();
    }
    function playExit(): void {
        enterMotion.stop();
        exitMotion.restart();
    }
    // Back to hidden at once, for a host that unloaded its surface.
    function stop(): void {
        enterMotion.stop();
        exitMotion.stop();
        unmapDelay.stop();
        root.grow = 0;
        root.reveal = 0;
    }

    onClosingChanged: {
        if (root.closing)
            root.playExit();
        else if (root.reveal > 0)
            root.playEnter(false);
    }
}
