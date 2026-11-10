pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Hotspot, drawn as the Material `wifi_tethering` glyph in three parts: the
 * source dot and two broadcast rings open at the bottom.
 *
 * Each ring keeps its opening centred under the dot while it changes radius
 * and sweep, so starting the hotspot reads as the rings unfurling out of the
 * source, inner first, and stopping it folds them back into it, outer first.
 */
AnimatedIcon {
    id: root

    cueChannel: "hotspot"
    stroke: 2.0

    /** The access point is up. False rests in the folded pose. */
    property bool active: true
    property bool busy: false
    /** Never fully gone: a folded ring stays as a ghost. */
    readonly property real ghost: 0.14

    readonly property real centerY: 13

    component Ring: Shape {
        id: ring
        property real rest: 5
        property real restSweep: 262
        property real foldedRadius: 3.4
        property real radius: rest
        property real sweep: restSweep
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: 12
                centerY: root.centerY
                radiusX: ring.radius
                radiusY: ring.radius
                // Centred on the top, so the opening stays under the dot.
                startAngle: 270 - ring.sweep / 2
                sweepAngle: ring.sweep
            }
        }
    }

    function activePose(): void {
        inner.radius = inner.rest;
        outer.radius = outer.rest;
        inner.sweep = inner.restSweep;
        outer.sweep = outer.restSweep;
        inner.opacity = 1;
        outer.opacity = 1;
    }

    function foldedPose(): void {
        inner.radius = inner.foldedRadius;
        outer.radius = outer.foldedRadius;
        inner.sweep = 100;
        outer.sweep = 120;
        inner.opacity = root.ghost;
        outer.opacity = root.ghost;
    }

    function applyRest(): void {
        dot.lift = 0;
        if (root.active)
            root.activePose();
        else
            root.foldedPose();
    }

    function stopAll(): void {
        startAnim.stop();
        stopAnim.stop();
    }

    function play(cue: string): void {
        // Interrupting continues from the pose reached; a fresh cue rebuilds
        // its first frame (see EthernetIcon for why).
        const continuing = root.busy;
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "started":
            if (!continuing)
                root.foldedPose();
            startAnim.start();
            break;
        case "stopped":
            if (!continuing)
                root.activePose();
            stopAnim.start();
            break;
        case "settle":
            root.busy = false;
            root.applyRest();
            break;
        default:
            root.busy = false;
            root.applyRest();
            break;
        }
    }

    onActiveChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: dot
        property real lift: 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathAngleArc {
                centerX: 12
                centerY: root.centerY + dot.lift
                radiusX: 2
                radiusY: 2
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    Ring {
        id: inner
        rest: 5
        restSweep: 262
        foldedRadius: 3.4
    }
    Ring {
        id: outer
        rest: 9
        restSweep: 264
        foldedRadius: 6.2
    }

    // ── Started: the source pushes and the rings unfurl, inner first ────────
    SequentialAnimation {
        id: startAnim
        onStopped: root.busy = false

        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: dot; property: "lift"; to: 0.9; duration: 100; easing.type: Easing.OutCubic }
                NumberAnimation { target: dot; property: "lift"; to: 0; duration: 300; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                PauseAnimation { duration: 60 }
                ParallelAnimation {
                    NumberAnimation { target: inner; property: "radius"; to: inner.rest; duration: 420; easing.type: Easing.OutBack }
                    NumberAnimation { target: inner; property: "sweep"; to: inner.restSweep; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: inner; property: "opacity"; to: 1; duration: 200 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 170 }
                ParallelAnimation {
                    NumberAnimation { target: outer; property: "radius"; to: outer.rest; duration: 460; easing.type: Easing.OutBack }
                    NumberAnimation { target: outer; property: "sweep"; to: outer.restSweep; duration: 460; easing.type: Easing.OutCubic }
                    NumberAnimation { target: outer; property: "opacity"; to: 1; duration: 220 }
                }
            }
        }
    }

    // ── Stopped: the rings fold back into the source, outer first ───────────
    SequentialAnimation {
        id: stopAnim
        onStopped: root.busy = false

        ParallelAnimation {
            ParallelAnimation {
                NumberAnimation { target: outer; property: "radius"; to: outer.foldedRadius; duration: 340; easing.type: Easing.InCubic }
                NumberAnimation { target: outer; property: "sweep"; to: 120; duration: 340; easing.type: Easing.InCubic }
                NumberAnimation { target: outer; property: "opacity"; to: root.ghost; duration: 320 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 90 }
                ParallelAnimation {
                    NumberAnimation { target: inner; property: "radius"; to: inner.foldedRadius; duration: 320; easing.type: Easing.InCubic }
                    NumberAnimation { target: inner; property: "sweep"; to: 100; duration: 320; easing.type: Easing.InCubic }
                    NumberAnimation { target: inner; property: "opacity"; to: root.ghost; duration: 300 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 280 }
                NumberAnimation { target: dot; property: "lift"; to: -0.8; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: dot; property: "lift"; to: 0; duration: 260; easing.type: Easing.OutBack }
            }
        }
    }
}
