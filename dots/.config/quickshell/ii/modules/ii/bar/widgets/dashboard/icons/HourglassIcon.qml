pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Countdown timer, drawn as a filled hourglass with separately articulated
 * caps, rails and sand.
 *
 * Running drains the upper chamber grain by grain and then turns the glass to
 * restart the flow. Pause mechanically catches the sand, completion deposits
 * it in the lower chamber, and removal closes the frame around the waist.
 */
AnimatedIcon {
    id: root

    cueChannel: "countdown"
    stroke: 2.0

    property bool running: false
    property bool paused: false
    property bool finished: false
    property bool busy: false

    readonly property real dimmed: 0.3

    property real topCapShift: 0
    property real bottomCapShift: 0
    property real leftRailLean: 0
    property real rightRailLean: 0
    property real topSandAmount: 0.78
    property real bottomSandAmount: 0.22
    property real grainY: 11.7
    property real bodyTurn: 0

    function shouldFlow(): bool {
        return root.running && !root.paused && !root.finished;
    }

    function applyRest(): void {
        root.topCapShift = 0;
        root.bottomCapShift = 0;
        root.leftRailLean = 0;
        root.rightRailLean = 0;
        root.bodyTurn = 0;
        root.grainY = root.finished ? 16.8 : 11.7;

        if (root.finished) {
            root.topSandAmount = 0.08;
            root.bottomSandAmount = 0.92;
        } else if (root.paused) {
            root.topSandAmount = 0.52;
            root.bottomSandAmount = 0.48;
        } else {
            root.topSandAmount = 0.78;
            root.bottomSandAmount = 0.22;
        }

        glyph.opacity = (root.running || root.paused || root.finished) ? 1 : root.dimmed;
    }

    function stopAll(): void {
        startAnim.stop();
        flowAnim.stop();
        pauseAnim.stop();
        resumeAnim.stop();
        completeAnim.stop();
        removedAnim.stop();
    }

    function beginFlow(): void {
        root.busy = false;
        if (root.shouldFlow())
            flowAnim.start();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "start":
            glyph.opacity = 1;
            startAnim.start();
            break;
        case "pause":
            pauseAnim.start();
            break;
        case "resume":
            glyph.opacity = 1;
            resumeAnim.start();
            break;
        case "complete":
            glyph.opacity = 1;
            completeAnim.start();
            break;
        case "removed":
            glyph.opacity = 1;
            removedAnim.start();
            break;
        default:
            root.busy = false;
            break;
        }
    }

    function refreshRest(): void {
        if (root.busy)
            return;
        root.stopAll();
        root.applyRest();
        if (root.shouldFlow())
            flowAnim.start();
    }

    onRunningChanged: root.refreshRest()
    onPausedChanged: root.refreshRest()
    onFinishedChanged: root.refreshRest()
    Component.onCompleted: root.refreshRest()

    Item {
        id: glyph

        anchors.fill: parent
        transform: Rotation {
            origin.x: 12
            origin.y: 12
            angle: root.bodyTurn
        }

        Shape {
            id: topCap

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Translate { y: root.topCapShift }
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathSvg { path: "M 4.6 2.6 Q 4 2.6 4 3.35 V 4.35 Q 4 5.1 4.75 5.1 H 19.25 Q 20 5.1 20 4.35 V 3.35 Q 20 2.6 19.4 2.6 Z" }
            }
        }

        Shape {
            id: bottomCap

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Translate { y: root.bottomCapShift }
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathSvg { path: "M 4.75 18.9 Q 4 18.9 4 19.65 V 20.65 Q 4 21.4 4.6 21.4 H 19.4 Q 20 21.4 20 20.65 V 19.65 Q 20 18.9 19.25 18.9 Z" }
            }
        }

        Shape {
            id: leftRail

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Rotation {
                origin.x: 10.8
                origin.y: 12
                angle: root.leftRailLean
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathSvg { path: "M 5.8 4.75 H 8.05 C 8.15 7.8 9.25 10.15 11.15 11.25 V 12.75 C 9.25 13.85 8.15 16.2 8.05 19.25 H 5.8 C 5.95 16.05 7.2 13.55 9.15 12 C 7.2 10.45 5.95 7.95 5.8 4.75 Z" }
            }
        }

        Shape {
            id: rightRail

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Rotation {
                origin.x: 13.2
                origin.y: 12
                angle: root.rightRailLean
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathSvg { path: "M 18.2 4.75 H 15.95 C 15.85 7.8 14.75 10.15 12.85 11.25 V 12.75 C 14.75 13.85 15.85 16.2 15.95 19.25 H 18.2 C 18.05 16.05 16.8 13.55 14.85 12 C 16.8 10.45 18.05 7.95 18.2 4.75 Z" }
            }
        }

        Shape {
            id: topSand

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathSvg {
                    path: {
                        const amount = Math.max(0.05, Math.min(1, root.topSandAmount));
                        const surfaceY = 6.15 + (1 - amount) * 4.6;
                        return "M 7.85 " + String(surfaceY)
                            + " H 16.15 Q 15.65 9.15 12.65 11.55"
                            + " Q 12 12.05 11.35 11.55 Q 8.35 9.15 7.85 "
                            + String(surfaceY) + " Z";
                    }
                }
            }
        }

        Shape {
            id: bottomSand

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathSvg {
                    path: {
                        const amount = Math.max(0.05, Math.min(1, root.bottomSandAmount));
                        const apexY = 18.25 - amount * 5.4;
                        return "M 7.55 18.25 H 16.45 Q 15.4 15.6 12 "
                            + String(apexY) + " Q 8.6 15.6 7.55 18.25 Z";
                    }
                }
            }
        }

        Shape {
            id: fallingGrain

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.shouldFlow() ? 1 : root.dimmed
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathAngleArc {
                    centerX: 12
                    centerY: root.grainY
                    radiusX: 0.72
                    radiusY: 1.15
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
    }

    // ── Created: the frame opens and catches the first falling grain ───────
    SequentialAnimation {
        id: startAnim

        ParallelAnimation {
            NumberAnimation { target: glyph; property: "opacity"; to: 1; duration: 150 }
            NumberAnimation { target: root; property: "topCapShift"; from: 2.6; to: 0; duration: 430; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "bottomCapShift"; from: -2.6; to: 0; duration: 430; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "leftRailLean"; from: 14; to: 0; duration: 460; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "rightRailLean"; from: -14; to: 0; duration: 460; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "topSandAmount"; from: 0.18; to: 0.78; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bottomSandAmount"; from: 0.06; to: 0.22; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "grainY"; from: 10.9; to: 16.7; duration: 390; easing.type: Easing.InCubic }
        }
        ScriptAction { script: root.beginFlow() }
    }

    // ── Running: sand drains, then the filled glass turns and refills ───────
    SequentialAnimation {
        id: flowAnim
        loops: Animation.Infinite

        ParallelAnimation {
            NumberAnimation { target: root; property: "topSandAmount"; from: 0.78; to: 0.12; duration: 2600; easing.type: Easing.Linear }
            NumberAnimation { target: root; property: "bottomSandAmount"; from: 0.22; to: 0.88; duration: 2600; easing.type: Easing.Linear }
            SequentialAnimation {
                loops: 5
                NumberAnimation { target: root; property: "grainY"; from: 11.5; to: 16.9; duration: 520; easing.type: Easing.InCubic }
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "bodyTurn"; from: 0; to: 180; duration: 560; easing.type: Easing.OutBack }
            SequentialAnimation {
                NumberAnimation { target: root; property: "topCapShift"; to: 0.6; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "topCapShift"; to: 0; duration: 300; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                NumberAnimation { target: root; property: "bottomCapShift"; to: -0.6; duration: 180; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "bottomCapShift"; to: 0; duration: 300; easing.type: Easing.OutBack }
            }
        }
        ScriptAction {
            script: {
                root.bodyTurn = 0;
                root.topSandAmount = 0.78;
                root.bottomSandAmount = 0.22;
                root.grainY = 11.5;
            }
        }
        PauseAnimation { duration: 120 }
    }

    // ── Paused: the rails catch the chambers and the grain stops ───────────
    SequentialAnimation {
        id: pauseAnim

        ParallelAnimation {
            NumberAnimation { target: root; property: "bodyTurn"; to: 0; duration: 360; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "topSandAmount"; to: 0.52; duration: 360; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bottomSandAmount"; to: 0.48; duration: 360; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "grainY"; to: 12.1; duration: 180; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: root; property: "leftRailLean"; to: 4; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "leftRailLean"; to: 0; duration: 260; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                NumberAnimation { target: root; property: "rightRailLean"; to: -4; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "rightRailLean"; to: 0; duration: 260; easing.type: Easing.OutBack }
            }
        }
        ScriptAction {
            script: {
                root.applyRest();
                root.beginFlow();
            }
        }
    }

    // ── Resumed: turn once, exchange the chambers, restart the stream ──────
    SequentialAnimation {
        id: resumeAnim

        ParallelAnimation {
            NumberAnimation { target: root; property: "bodyTurn"; from: 0; to: 180; duration: 560; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "topSandAmount"; to: 0.18; duration: 460; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bottomSandAmount"; to: 0.82; duration: 460; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "grainY"; from: 11.5; to: 16.9; duration: 430; easing.type: Easing.InCubic }
        }
        ScriptAction {
            script: {
                root.bodyTurn = 0;
                root.topSandAmount = 0.78;
                root.bottomSandAmount = 0.22;
                root.grainY = 11.5;
                root.beginFlow();
            }
        }
    }

    // ── Finished: the last grain lands and rocks the lower chamber ─────────
    SequentialAnimation {
        id: completeAnim

        ParallelAnimation {
            NumberAnimation { target: root; property: "bodyTurn"; to: 7; duration: 180; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "topSandAmount"; to: 0.08; duration: 360; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "bottomSandAmount"; to: 0.92; duration: 420; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "grainY"; to: 16.9; duration: 300; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "bottomCapShift"; to: 0.75; duration: 210; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "bodyTurn"; to: 0; duration: 360; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "bottomCapShift"; to: 0; duration: 360; easing.type: Easing.OutBack }
        }
        ScriptAction {
            script: {
                root.applyRest();
                root.beginFlow();
            }
        }
    }

    // ── Removed: both filled ends close around the waist before hiding ─────
    SequentialAnimation {
        id: removedAnim

        ParallelAnimation {
            NumberAnimation { target: root; property: "topCapShift"; to: 4.6; duration: 260; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "bottomCapShift"; to: -4.6; duration: 260; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "leftRailLean"; to: 15; duration: 280; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "rightRailLean"; to: -15; duration: 280; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "topSandAmount"; to: 0.05; duration: 250; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "bottomSandAmount"; to: 0.05; duration: 250; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "grainY"; to: 12; duration: 180; easing.type: Easing.OutCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: glyph; property: "opacity"; to: root.dimmed; duration: 230 }
            NumberAnimation { target: root; property: "topCapShift"; to: 0; duration: 330; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "bottomCapShift"; to: 0; duration: 330; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "leftRailLean"; to: 0; duration: 340; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "rightRailLean"; to: 0; duration: 340; easing.type: Easing.OutBack }
        }
        ScriptAction {
            script: {
                root.applyRest();
                root.beginFlow();
            }
        }
    }
}
