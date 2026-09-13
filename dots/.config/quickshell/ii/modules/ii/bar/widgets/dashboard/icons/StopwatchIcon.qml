pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Stopwatch: the timer's dial plus the side knob you press to lap it.
 *
 * The knob is a real part, so lapping presses it and the hand ticks forward —
 * two moving pieces reporting one action.
 */
AnimatedIcon {
    id: root

    cueChannel: "stopwatch"
    stroke: 2.0

    property bool running: false
    property bool busy: false

    readonly property real dialX: 12
    readonly property real dialY: 13.6
    readonly property real dimmed: 0.4

    property real handAngle: 0
    property real crownDrop: 0
    property real knobPress: 0

    function applyRest(): void {
        root.handAngle = 0;
        root.crownDrop = 0;
        root.knobPress = 0;
        dial.opacity = 1;
        hand.opacity = 1;
    }

    function stopAll(): void {
        startAnim.stop();
        stopAnim.stop();
        lapAnim.stop();
        resetAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "start":
            startAnim.start();
            break;
        case "stop":
            stopAnim.start();
            break;
        case "lap":
            lapAnim.start();
            break;
        case "reset":
            resetAnim.start();
            break;
        default:
            root.busy = false;
            break;
        }
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: crown
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: root.crownDrop }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 9.4
            startY: 2.8
            PathLine { x: 14.6; y: 2.8 }
        }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 12
            startY: 2.8
            PathLine { x: 12; y: 5.8 }
        }
    }

    Shape {
        id: knob
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { x: -root.knobPress * 0.7; y: root.knobPress * 0.7 }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 17.9
            startY: 6.6
            PathLine { x: 20.1; y: 4.4 }
        }
    }

    Shape {
        id: dial
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            PathAngleArc {
                centerX: root.dialX
                centerY: root.dialY
                radiusX: 7.4
                radiusY: 7.4
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    Shape {
        id: hand
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Rotation {
            origin.x: root.dialX
            origin.y: root.dialY
            angle: root.handAngle
        }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: root.dialX
            startY: root.dialY
            PathLine { x: root.dialX; y: 8.4 }
        }
    }

    // ── Started: crown pressed, hand away ───────────────────────────────────
    SequentialAnimation {
        id: startAnim
        onStopped: root.busy = false

        ScriptAction { script: dial.opacity = 1 }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: root; property: "crownDrop"; to: 1.3; duration: 110; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "crownDrop"; to: 0; duration: 320; easing.type: Easing.OutBack }
            }
            NumberAnimation { target: root; property: "handAngle"; from: 0; to: 300; duration: 720; easing.type: Easing.OutCubic }
        }
    }

    // ── Stopped: the knob is pressed and the hand halts ─────────────────────
    ParallelAnimation {
        id: stopAnim
        onStopped: root.busy = false

        SequentialAnimation {
            NumberAnimation { target: root; property: "knobPress"; to: 1.5; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "knobPress"; to: 0; duration: 300; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: root; property: "handAngle"; to: root.handAngle + 14; duration: 170; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "handAngle"; to: root.handAngle + 8; duration: 340; easing.type: Easing.OutBack }
        }
        NumberAnimation { target: dial; property: "opacity"; to: root.dimmed; duration: 280 }
    }

    // ── Lap: a press and one tick forward ───────────────────────────────────
    ParallelAnimation {
        id: lapAnim
        onStopped: root.busy = false

        SequentialAnimation {
            NumberAnimation { target: root; property: "knobPress"; to: 1.5; duration: 90; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "knobPress"; to: 0; duration: 260; easing.type: Easing.OutBack }
        }
        NumberAnimation { target: root; property: "handAngle"; to: root.handAngle + 60; duration: 380; easing.type: Easing.OutBack }
    }

    // ── Reset: everything walks home ────────────────────────────────────────
    ParallelAnimation {
        id: resetAnim
        onStopped: root.busy = false

        NumberAnimation { target: root; property: "handAngle"; to: 0; duration: 460; easing.type: Easing.OutBack }
        NumberAnimation { target: dial; property: "opacity"; to: 1; duration: 300 }
        SequentialAnimation {
            NumberAnimation { target: root; property: "crownDrop"; to: 1.1; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "crownDrop"; to: 0; duration: 300; easing.type: Easing.OutBack }
        }
    }
}
