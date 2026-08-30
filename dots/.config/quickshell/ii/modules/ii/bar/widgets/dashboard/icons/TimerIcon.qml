pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Pomodoro timer, following Material's `timer`: the crown bar, the dial, and
 * the hand.
 *
 * The hand is the only part that carries the state — it sweeps while the timer
 * runs and holds its angle when paused, so a glance says both "running" and
 * roughly "how far in".
 */
AnimatedIcon {
    id: root

    cueChannel: "pomodoro"
    stroke: 2.0

    property bool running: false
    /** A break lap rather than a focus lap. */
    property bool onBreak: false
    property bool busy: false

    readonly property real dialX: 12
    readonly property real dialY: 13.4
    readonly property real dimmed: 0.4

    property real handAngle: 0
    property real crownDrop: 0

    function applyRest(): void {
        root.handAngle = 0;
        root.crownDrop = 0;
        dial.opacity = 1;
        hand.opacity = root.onBreak ? root.dimmed : 1;
        crown.opacity = 1;
    }

    function stopAll(): void {
        startAnim.stop();
        sweepAnim.stop();
        pauseAnim.stop();
        completeAnim.stop();
        resetAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "start":
            startAnim.start();
            break;
        case "pause":
            pauseAnim.start();
            break;
        case "complete":
            completeAnim.start();
            break;
        case "reset":
            resetAnim.start();
            break;
        default:
            root.busy = false;
            break;
        }
    }

    onRunningChanged: {
        if (!root.busy)
            root.applyRest();
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
            startX: 9
            startY: 2.7
            PathLine { x: 15; y: 2.7 }
        }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 12
            startY: 2.7
            PathLine { x: 12; y: 5.4 }
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
                radiusX: 7.6
                radiusY: 7.6
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
            PathLine { x: root.dialX; y: 8.0 }
        }
    }

    // ── Started: the crown is pressed and the hand takes off ────────────────
    SequentialAnimation {
        id: startAnim
        onStopped: root.busy = false

        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: root; property: "crownDrop"; to: 1.2; duration: 110; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "crownDrop"; to: 0; duration: 320; easing.type: Easing.OutBack }
            }
            NumberAnimation { target: root; property: "handAngle"; from: 0; to: 360; duration: 780; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: root.handAngle = 0 }
    }

    SequentialAnimation {
        id: sweepAnim
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "handAngle"; from: 0; to: 360; duration: 4000 }
    }

    // ── Paused: the hand stalls and the dial goes quiet ─────────────────────
    ParallelAnimation {
        id: pauseAnim
        onStopped: root.busy = false

        SequentialAnimation {
            NumberAnimation { target: root; property: "handAngle"; to: root.handAngle + 26; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "handAngle"; to: root.handAngle + 18; duration: 380; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: dial; property: "opacity"; to: root.dimmed; duration: 260 }
        }
    }

    // ── Finished: the hand snaps home and the crown rings ───────────────────
    SequentialAnimation {
        id: completeAnim
        onStopped: root.busy = false

        ScriptAction { script: dial.opacity = 1 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "handAngle"; to: 360; duration: 420; easing.type: Easing.OutBack }
            SequentialAnimation {
                NumberAnimation { target: root; property: "crownDrop"; to: -1.4; duration: 130; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "crownDrop"; to: 0.8; duration: 150; easing.type: Easing.InOutSine }
                NumberAnimation { target: root; property: "crownDrop"; to: -0.5; duration: 130; easing.type: Easing.InOutSine }
                NumberAnimation { target: root; property: "crownDrop"; to: 0; duration: 180; easing.type: Easing.OutSine }
            }
        }
        ScriptAction { script: root.applyRest() }
    }

    // ── Reset: the hand walks back to twelve ────────────────────────────────
    SequentialAnimation {
        id: resetAnim
        onStopped: root.busy = false

        ParallelAnimation {
            NumberAnimation { target: root; property: "handAngle"; to: 0; duration: 460; easing.type: Easing.OutBack }
            NumberAnimation { target: dial; property: "opacity"; to: 1; duration: 300 }
        }
    }
}
