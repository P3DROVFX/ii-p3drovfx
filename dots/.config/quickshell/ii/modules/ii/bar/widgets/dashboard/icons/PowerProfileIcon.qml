pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Power profile, following Material's `speed`: a dial with a needle.
 *
 * The three profiles are three points on one scale, so the icon is a scale and
 * the needle sweeps between them — power saver at the left stop, balanced
 * upright, performance at the right. The arc fills behind the needle, so the
 * two halves of the glyph move together and the reading is the same whether you
 * catch the angle or the amount.
 *
 * That is also why this is a dial and not a leaf swapping for a flame: swapping
 * glyphs is a cut, and the icons in this folder animate by moving a part of
 * themselves. A needle already knows how to travel between three values.
 */
AnimatedIcon {
    id: root

    cueChannel: "powerprofile"
    stroke: 2.0

    /** "saver" | "balanced" | "performance" */
    property string profile: "balanced"
    property bool busy: false

    readonly property real dimmed: 0.34

    // Dial geometry on the 24-grid. 0° is 3 o'clock and sweeps clockwise, so
    // 200° is the upper left, 270° the top and 340° the upper right.
    readonly property real pivotX: 12
    readonly property real pivotY: 15.4
    readonly property real dialRadius: 7.2
    readonly property real arcStart: 200
    readonly property real arcSweep: 140

    /** 0 = saver, 0.5 = balanced, 1 = performance. Drives needle and arc both. */
    property real level: 0.5

    function levelFor(name: string): real {
        if (name === "saver")
            return 0;
        if (name === "performance")
            return 1;
        return 0.5;
    }

    function applyRest(): void {
        root.level = root.levelFor(root.profile);
    }

    function stopAll(): void {
        sweepAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        const target = root.levelFor(cue);
        if (cue !== "saver" && cue !== "balanced" && cue !== "performance") {
            root.busy = false;
            return;
        }
        root.busy = true;
        sweepAnim.to = target;
        sweepAnim.start();
    }

    onProfileChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // The scale the needle reads against.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.dimmed

        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.pivotX
                centerY: root.pivotY
                radiusX: root.dialRadius
                radiusY: root.dialRadius
                startAngle: root.arcStart
                sweepAngle: root.arcSweep
            }
        }
    }

    // How far up the scale the current profile sits. Hidden rather than drawn
    // at zero sweep: a zero-length arc with a round cap still paints a dot at
    // the left stop, which reads as a mark that is not there.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.level > 0.02

        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.pivotX
                centerY: root.pivotY
                radiusX: root.dialRadius
                radiusY: root.dialRadius
                startAngle: root.arcStart
                sweepAngle: root.arcSweep * root.level
            }
        }
    }

    // The needle. Rotated about the pivot, so `rotation` reads as degrees off
    // vertical: -70 at the saver stop, +70 at performance.
    Item {
        anchors.fill: parent
        transform: Rotation {
            origin.x: root.pivotX
            origin.y: root.pivotY
            angle: -root.arcSweep / 2 + root.arcSweep * root.level
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: root.color
                fillColor: "transparent"
                strokeWidth: root.stroke
                capStyle: ShapePath.RoundCap
                startX: root.pivotX
                startY: root.pivotY

                PathLine {
                    x: root.pivotX
                    y: root.pivotY - root.dialRadius + 1.4
                }
            }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color

            PathAngleArc {
                centerX: root.pivotX
                centerY: root.pivotY
                radiusX: 1.5
                radiusY: 1.5
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    NumberAnimation {
        id: sweepAnim
        target: root
        property: "level"
        duration: 420
        // The needle arrives past its stop and settles back, the way a real one
        // does. This is the whole animation; nothing else needs to move.
        easing.type: Easing.OutBack
        easing.overshoot: 1.6
        onStopped: root.busy = false
    }
}
