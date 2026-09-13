pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * System alarm, based on Material's `alarm` silhouette and articulated into
 * the clock body, two bells, two feet and the hands.
 *
 * A newly scheduled alarm opens the bells away from the body. While it rings,
 * the bells strike in opposition and the clock rocks on its feet. Stopping
 * damps every moving piece; removing an alarm folds the mechanism inward.
 * Opacity only supports appearance/disappearance — movement carries every cue.
 */
AnimatedIcon {
    id: root

    cueChannel: "alarm"
    stroke: 2.1

    property bool scheduled: false
    property bool ringing: false
    property bool busy: false

    readonly property real dimmed: 0.35
    readonly property real bodyFillOpacity: 0.72
    property real bodyRock: 0
    property real bodyLift: 0
    property real handJolt: 0

    component Bell: Shape {
        id: bell

        required property int direction
        property real bellSwing: 0
        property real lift: 0

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: [
            Rotation {
                origin.x: bell.direction < 0 ? 6.5 : 17.5
                origin.y: 6.4
                angle: bell.bellSwing
            },
            Translate { y: bell.lift }
        ]

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg {
                path: bell.direction < 0
                    ? "M 3.2 7.1 Q 2.45 6.3 2.5 5.15 Q 2.55 3.8 3.55 2.85 Q 4.5 1.95 5.85 2.05 Q 7.05 2.15 7.85 3.05 Z"
                    : "M 20.8 7.1 Q 21.55 6.3 21.5 5.15 Q 21.45 3.8 20.45 2.85 Q 19.5 1.95 18.15 2.05 Q 16.95 2.15 16.15 3.05 Z"
            }
        }
    }

    component Foot: Shape {
        id: foot

        required property int direction
        property real legDrop: 0

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: foot.legDrop }

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg {
                path: foot.direction < 0
                    ? "M 7.1 17.5 Q 7.8 18 8.45 18.75 L 6.15 21.8 Q 5.85 22.2 5.4 21.9 L 4.65 21.35 Z"
                    : "M 16.9 17.5 Q 16.2 18 15.55 18.75 L 17.85 21.8 Q 18.15 22.2 18.6 21.9 L 19.35 21.35 Z"
            }
        }
    }

    function applyRest(): void {
        root.bodyRock = 0;
        root.bodyLift = 0;
        root.handJolt = 0;
        leftBell.bellSwing = 0;
        rightBell.bellSwing = 0;
        leftBell.lift = 0;
        rightBell.lift = 0;
        leftFoot.legDrop = 0;
        rightFoot.legDrop = 0;
        glyph.opacity = (root.scheduled || root.ringing) ? 1 : root.dimmed;
    }

    function stopAll(): void {
        openAnim.stop();
        ringingAnim.stop();
        stoppedAnim.stop();
        removedAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "open":
            glyph.opacity = 1;
            openAnim.start();
            break;
        case "ringing":
            glyph.opacity = 1;
            ringingAnim.start();
            break;
        case "stopped":
            stoppedAnim.start();
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

    onScheduledChanged: {
        if (!root.busy)
            root.applyRest();
    }

    onRingingChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    Item {
        id: glyph

        anchors.fill: parent

        Bell { id: leftBell; direction: -1 }
        Bell { id: rightBell; direction: 1 }

        Item {
            id: bodyAssembly

            anchors.fill: parent
            transform: [
                Rotation {
                    origin.x: 12
                    origin.y: 13
                    angle: root.bodyRock
                },
                Translate { y: root.bodyLift }
            ]

            Foot { id: leftFoot; direction: -1 }
            Foot { id: rightFoot; direction: 1 }

            Shape {
                id: dial

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                // A translucent solid face keeps the icon filled while the
                // denser hands and hour marks remain legible in any theme.
                opacity: root.bodyFillOpacity
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.color
                    PathAngleArc {
                        centerX: 12
                        centerY: 13
                        radiusX: 7.4
                        radiusY: 7.4
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }

            Shape {
                id: faceMarks

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.color
                    PathSvg {
                        path: "M 11.45 6.4 H 12.55 V 8.2 H 11.45 Z M 17.1 12.45 H 18.9 V 13.55 H 17.1 Z M 11.45 17.8 H 12.55 V 19.6 H 11.45 Z M 5.1 12.45 H 6.9 V 13.55 H 5.1 Z"
                    }
                }
            }

            Item {
                id: hands

                anchors.fill: parent
                transform: Rotation {
                    origin.x: 12
                    origin.y: 13
                    angle: root.handJolt
                }

                Shape {
                    id: minuteHand

                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: root.color
                        fillColor: "transparent"
                        strokeWidth: root.stroke
                        capStyle: ShapePath.RoundCap
                        startX: 12
                        startY: 13
                        PathLine { x: 12; y: 8.5 }
                    }
                }

                Shape {
                    id: hourHand

                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: root.color
                        fillColor: "transparent"
                        strokeWidth: root.stroke
                        capStyle: ShapePath.RoundCap
                        startX: 12
                        startY: 13
                        PathLine { x: 15.25; y: 14.8 }
                    }
                }

                Shape {
                    id: handPin

                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: root.color
                        PathAngleArc {
                            centerX: 12
                            centerY: 13
                            radiusX: 1.2
                            radiusY: 1.2
                            startAngle: 0
                            sweepAngle: 360
                        }
                    }
                }
            }
        }
    }

    // ── Open: the alarm mechanism unfolds into place ───────────────────────
    ParallelAnimation {
        id: openAnim
        onStopped: root.busy = false

        NumberAnimation { target: glyph; property: "opacity"; to: 1; duration: 150 }
        SequentialAnimation {
            NumberAnimation { target: root; property: "bodyLift"; from: 2.4; to: -0.8; duration: 210; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bodyLift"; to: 0; duration: 270; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: root; property: "bodyRock"; from: -6; to: 3.5; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bodyRock"; to: 0; duration: 300; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: leftBell; property: "bellSwing"; from: 22; to: -5; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: leftBell; property: "bellSwing"; to: 0; duration: 300; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: rightBell; property: "bellSwing"; from: -22; to: 5; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: rightBell; property: "bellSwing"; to: 0; duration: 300; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: root; property: "handJolt"; from: -36; to: 8; duration: 280; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "handJolt"; to: 0; duration: 320; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: leftFoot; property: "legDrop"; from: -2; to: 0.7; duration: 230; easing.type: Easing.OutCubic }
            NumberAnimation { target: leftFoot; property: "legDrop"; to: 0; duration: 280; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: rightFoot; property: "legDrop"; from: -2; to: 0.7; duration: 230; easing.type: Easing.OutCubic }
            NumberAnimation { target: rightFoot; property: "legDrop"; to: 0; duration: 280; easing.type: Easing.OutBack }
        }
    }

    // ── Ringing: bells strike against a clock rocking on its feet ──────────
    ParallelAnimation {
        id: ringingAnim

        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation { target: root; property: "bodyRock"; to: -4.2; duration: 65; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bodyRock"; to: 4.2; duration: 95; easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "bodyRock"; to: -3.2; duration: 90; easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "bodyRock"; to: 0; duration: 70; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation { target: root; property: "bodyLift"; to: -0.7; duration: 80; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bodyLift"; to: 0.35; duration: 150; easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "bodyLift"; to: 0; duration: 90; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation { target: leftBell; property: "bellSwing"; to: -16; duration: 70; easing.type: Easing.OutCubic }
            NumberAnimation { target: leftBell; property: "bellSwing"; to: 10; duration: 100; easing.type: Easing.InOutCubic }
            NumberAnimation { target: leftBell; property: "bellSwing"; to: -7; duration: 90; easing.type: Easing.InOutCubic }
            NumberAnimation { target: leftBell; property: "bellSwing"; to: 0; duration: 60; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation { target: rightBell; property: "bellSwing"; to: 16; duration: 70; easing.type: Easing.OutCubic }
            NumberAnimation { target: rightBell; property: "bellSwing"; to: -10; duration: 100; easing.type: Easing.InOutCubic }
            NumberAnimation { target: rightBell; property: "bellSwing"; to: 7; duration: 90; easing.type: Easing.InOutCubic }
            NumberAnimation { target: rightBell; property: "bellSwing"; to: 0; duration: 60; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation { target: root; property: "handJolt"; to: -8; duration: 80; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "handJolt"; to: 10; duration: 120; easing.type: Easing.InOutCubic }
            NumberAnimation { target: root; property: "handJolt"; to: 0; duration: 120; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: leftFoot; property: "legDrop"; to: -0.8; duration: 80; easing.type: Easing.OutCubic }
                NumberAnimation { target: rightFoot; property: "legDrop"; to: 0.35; duration: 80; easing.type: Easing.OutCubic }
            }
            ParallelAnimation {
                NumberAnimation { target: leftFoot; property: "legDrop"; to: 0.35; duration: 150; easing.type: Easing.InOutCubic }
                NumberAnimation { target: rightFoot; property: "legDrop"; to: -0.8; duration: 150; easing.type: Easing.InOutCubic }
            }
            ParallelAnimation {
                NumberAnimation { target: leftFoot; property: "legDrop"; to: 0; duration: 90; easing.type: Easing.OutCubic }
                NumberAnimation { target: rightFoot; property: "legDrop"; to: 0; duration: 90; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── Stopped: all oscillation is mechanically damped ────────────────────
    ParallelAnimation {
        id: stoppedAnim
        onStopped: {
            root.busy = false;
            root.applyRest();
        }

        NumberAnimation { target: root; property: "bodyRock"; to: 0; duration: 380; easing.type: Easing.OutBack }
        NumberAnimation { target: root; property: "bodyLift"; to: 0; duration: 300; easing.type: Easing.OutBack }
        NumberAnimation { target: root; property: "handJolt"; to: 0; duration: 400; easing.type: Easing.OutBack }
        NumberAnimation { target: leftBell; property: "bellSwing"; to: 0; duration: 420; easing.type: Easing.OutBack }
        NumberAnimation { target: rightBell; property: "bellSwing"; to: 0; duration: 420; easing.type: Easing.OutBack }
        NumberAnimation { target: leftFoot; property: "legDrop"; to: 0; duration: 330; easing.type: Easing.OutBack }
        NumberAnimation { target: rightFoot; property: "legDrop"; to: 0; duration: 330; easing.type: Easing.OutBack }
    }

    // ── Removed: bells and feet fold inward, then the glyph settles ─────────
    SequentialAnimation {
        id: removedAnim
        onStopped: {
            root.busy = false;
            root.applyRest();
        }

        ParallelAnimation {
            NumberAnimation { target: root; property: "bodyRock"; to: -3; duration: 180; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "bodyLift"; to: 1.25; duration: 190; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "handJolt"; to: -28; duration: 210; easing.type: Easing.InCubic }
            NumberAnimation { target: leftBell; property: "bellSwing"; to: 18; duration: 210; easing.type: Easing.InCubic }
            NumberAnimation { target: rightBell; property: "bellSwing"; to: -18; duration: 210; easing.type: Easing.InCubic }
            NumberAnimation { target: leftFoot; property: "legDrop"; to: -1.7; duration: 200; easing.type: Easing.InCubic }
            NumberAnimation { target: rightFoot; property: "legDrop"; to: -1.7; duration: 200; easing.type: Easing.InCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "bodyRock"; to: 0; duration: 300; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "bodyLift"; to: 0; duration: 320; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "handJolt"; to: 0; duration: 330; easing.type: Easing.OutBack }
            NumberAnimation { target: leftBell; property: "bellSwing"; to: 0; duration: 340; easing.type: Easing.OutBack }
            NumberAnimation { target: rightBell; property: "bellSwing"; to: 0; duration: 340; easing.type: Easing.OutBack }
            NumberAnimation { target: leftFoot; property: "legDrop"; to: 0; duration: 320; easing.type: Easing.OutBack }
            NumberAnimation { target: rightFoot; property: "legDrop"; to: 0; duration: 320; easing.type: Easing.OutBack }
            NumberAnimation { target: glyph; property: "opacity"; to: (root.scheduled || root.ringing) ? 1 : root.dimmed; duration: 300 }
        }
    }
}
