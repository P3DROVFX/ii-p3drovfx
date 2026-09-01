import QtQuick
import qs.modules.common

/**
 * One row's arrival on a page that fills top-down.
 *
 * A `Repeater` has no equivalent of a ListView's `populate` transition, so a
 * delegate that wants to cascade has to animate itself. This is that
 * animation, written once: drop it inside the delegate and hand it the
 * delegate's index.
 *
 *     Rectangle {
 *         required property int index
 *         StaggeredEntrance { index: parent.index }
 *     }
 *
 * It runs only on creation. A Repeater rebuilds its delegates whenever its
 * model is replaced — which is exactly when a page is filled again — and
 * nothing else should be animating a row that is already on screen.
 *
 * Opacity and scale, not position: both are visual, so a row can enter from
 * inside a Layout without its neighbours being asked to move for it. This is
 * the same pair the attachment chips and the transcript already enter with.
 */
Item {
    id: root

    /** What enters. Defaults to whatever this sits inside. */
    property Item target: root.parent
    /** Place in the fill; decides how long this row waits. */
    property int index: 0
    /** Milliseconds between one row and the next. */
    property int step: 26
    /** Caps the wait for the last row of a long list. */
    property int maximumDelay: 320
    /** Set false to leave the row settled — a reduced-motion preference. */
    property bool active: !Config.options.sidebar.ai.reducedMotion
    /** How small a row starts. Near 1: this is entry, not a pop. */
    property real fromScale: 0.965

    readonly property int delay: Math.min(root.maximumDelay, Math.max(0, root.index) * root.step)

    // Occupies nothing: it is behaviour attached to a row, not part of it.
    width: 0
    height: 0
    visible: false

    Component.onCompleted: {
        if (!root.active || !root.target)
            return;
        root.target.opacity = 0;
        root.target.scale = root.fromScale;
        entrance.start();
    }

    SequentialAnimation {
        id: entrance

        PauseAnimation {
            duration: root.delay
        }

        ParallelAnimation {
            NumberAnimation {
                target: root.target
                property: "opacity"
                from: 0
                to: 1
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }

            // A bare fade after a wait reads as a dropped frame; settling into
            // size reads as the row arriving.
            NumberAnimation {
                target: root.target
                property: "scale"
                from: root.fromScale
                to: 1
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
            }
        }
    }
}
