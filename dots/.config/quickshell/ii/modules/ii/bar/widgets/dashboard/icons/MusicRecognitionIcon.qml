pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Identify Music, based on Material's `music_cast`: the note stays on the
 * right, while two filled broadcast sweeps travel diagonally toward the
 * lower-left. Keeping that orientation matters — mirroring the source glyph
 * makes it read as volume rather than recognition/casting.
 *
 * The head, stem/flag and both sweeps are independent items. Listening rocks
 * the stem mechanically around its head while each sweep travels along the
 * actual broadcast direction; a match lifts the note and lets the flag answer
 * a beat later.
 */
AnimatedIcon {
    id: root

    cueChannel: "songrec"

    property bool listening: false
    property bool busy: false

    readonly property real dimmed: 0.35
    property real noteBob: 0
    property real noteSway: 0
    property real flagKick: 0
    property real noteOpacity: dimmed

    component BroadcastWave: Shape {
        id: wave

        required property string pathData
        property real waveTravel: 0

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: 0
        transform: Translate {
            // Positive travel follows the glyph's broadcast direction.
            x: -wave.waveTravel * 0.72
            y: wave.waveTravel * 0.72
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg { path: wave.pathData }
        }
    }

    function applyRest(): void {
        root.noteBob = 0;
        root.noteSway = 0;
        root.flagKick = 0;
        root.noteOpacity = root.listening ? 1 : root.dimmed;
        nearWave.waveTravel = 0;
        farWave.waveTravel = 0;
        nearWave.opacity = root.listening ? 0.72 : 0;
        farWave.opacity = root.listening ? 0.72 : 0;
    }

    function stopAll(): void {
        listenAnim.stop();
        foundAnim.stop();
        offAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "listening":
            root.noteOpacity = 1;
            listenAnim.start();
            break;
        case "found":
            foundAnim.start();
            break;
        case "off":
            offAnim.start();
            break;
        default:
            root.busy = false;
            break;
        }
    }

    onListeningChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Material note, separated at the joint ──────────────────────────────
    Item {
        id: noteAssembly
        anchors.fill: parent
        transform: [
            Rotation {
                origin.x: 14
                origin.y: 16
                angle: root.noteSway
            },
            Translate {
                x: root.noteSway * 0.08
                y: root.noteBob
            }
        ]

        Shape {
            id: noteStem

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.noteOpacity
            transform: Rotation {
                origin.x: 14
                origin.y: 16
                angle: root.flagKick
            }

            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathSvg {
                    path: "M 16 16 V 5 Q 16 4 17 4 H 21 Q 22 4 22 5 V 6 Q 22 7 21 7 H 18 V 16 Z"
                }
            }
        }

        Shape {
            id: noteHead

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            opacity: root.noteOpacity

            ShapePath {
                strokeColor: "transparent"
                fillColor: root.color
                PathAngleArc {
                    centerX: 14
                    centerY: 16
                    radiusX: 4
                    radiusY: 4
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
    }

    // These paths are the two broadcast regions of Material `music_cast`,
    // normalized from its 960-unit font grid to this component's 24-unit grid.
    BroadcastWave {
        id: farWave
        pathData: "M 6.95 8.925 Q 5.75 10.125 5 11.663 Q 4.25 13.2 4.05 14.95 Q 4 15.375 3.713 15.688 Q 3.425 16 3 16 Q 2.575 16 2.288 15.675 Q 2 15.35 2.05 14.925 Q 2.25 12.75 3.163 10.863 Q 4.075 8.975 5.525 7.525 Q 6.975 6.075 8.863 5.163 Q 10.75 4.25 12.925 4.05 Q 13.35 4 13.675 4.288 Q 14 4.575 14 5 Q 14 5.425 13.688 5.713 Q 13.375 6 12.95 6.05 Q 11.2 6.25 9.675 6.988 Q 8.15 7.725 6.95 8.925 Z"
    }

    BroadcastWave {
        id: nearWave
        pathData: "M 9.775 11.75 Q 9.125 12.4 8.675 13.238 Q 8.225 14.075 8.075 15.025 Q 8 15.45 7.713 15.725 Q 7.425 16 7 16 Q 6.575 16 6.3 15.688 Q 6.025 15.375 6.075 14.95 Q 6.25 13.6 6.838 12.438 Q 7.425 11.275 8.35 10.35 Q 9.275 9.425 10.438 8.838 Q 11.6 8.25 12.95 8.075 Q 13.375 8.025 13.688 8.3 Q 14 8.575 14 9 Q 14 9.425 13.725 9.713 Q 13.45 10 13.025 10.075 Q 12.075 10.225 11.25 10.663 Q 10.425 11.1 9.775 11.75 Z"
    }

    // ── Listening: the two sweeps leave the note on one shared beat ────────
    ParallelAnimation {
        id: listenAnim

        SequentialAnimation {
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: nearWave; property: "waveTravel"; from: -2.2; to: 0.15; duration: 480; easing.type: Easing.OutCubic }
                NumberAnimation { target: nearWave; property: "opacity"; from: 0.18; to: 1; duration: 260; easing.type: Easing.OutCubic }
            }
            NumberAnimation { target: nearWave; property: "opacity"; to: 0.18; duration: 260; easing.type: Easing.InCubic }
            PauseAnimation { duration: 400 }
        }

        SequentialAnimation {
            loops: Animation.Infinite
            PauseAnimation { duration: 220 }
            ParallelAnimation {
                NumberAnimation { target: farWave; property: "waveTravel"; from: -2.55; to: 0.2; duration: 480; easing.type: Easing.OutCubic }
                NumberAnimation { target: farWave; property: "opacity"; from: 0.18; to: 1; duration: 260; easing.type: Easing.OutCubic }
            }
            NumberAnimation { target: farWave; property: "opacity"; to: 0.18; duration: 260; easing.type: Easing.InCubic }
            PauseAnimation { duration: 180 }
        }

        // Angular motion is the primary listening cue: the stem balances on
        // the note head while the two broadcasts answer on the same 1140 ms
        // rhythm. There is deliberately no scale or pulse here.
        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation { target: root; property: "noteSway"; to: -5.5; duration: 190; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "noteSway"; to: 3.2; duration: 290; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "noteSway"; to: 5; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "noteSway"; to: 0; duration: 320; easing.type: Easing.OutBack }
            PauseAnimation { duration: 180 }
        }
    }

    // ── Found: broadcasts land, then the note answers ──────────────────────
    ParallelAnimation {
        id: foundAnim
        onStopped: root.busy = false

        NumberAnimation { target: nearWave; property: "waveTravel"; to: 0; duration: 300; easing.type: Easing.OutCubic }
        NumberAnimation { target: farWave; property: "waveTravel"; to: 0; duration: 360; easing.type: Easing.OutCubic }
        NumberAnimation { target: nearWave; property: "opacity"; to: 1; duration: 200 }
        NumberAnimation { target: farWave; property: "opacity"; to: 1; duration: 240 }
        NumberAnimation { target: root; property: "noteOpacity"; to: 1; duration: 180 }
        NumberAnimation { target: root; property: "noteSway"; to: 0; duration: 220; easing.type: Easing.OutCubic }

        SequentialAnimation {
            NumberAnimation { target: root; property: "noteBob"; to: -1.8; duration: 170; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "noteBob"; to: 0; duration: 390; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            PauseAnimation { duration: 75 }
            NumberAnimation { target: root; property: "flagKick"; to: -7; duration: 135; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "flagKick"; to: 0; duration: 330; easing.type: Easing.OutBack }
        }
    }

    // ── Off: both sweeps return to the source before going quiet ───────────
    ParallelAnimation {
        id: offAnim
        onStopped: root.busy = false

        NumberAnimation { target: root; property: "noteSway"; to: 0; duration: 220; easing.type: Easing.OutCubic }

        ParallelAnimation {
            NumberAnimation { target: farWave; property: "waveTravel"; to: -1.7; duration: 340; easing.type: Easing.InCubic }
            NumberAnimation { target: farWave; property: "opacity"; to: 0; duration: 300 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 70 }
            ParallelAnimation {
                NumberAnimation { target: nearWave; property: "waveTravel"; to: -1.45; duration: 320; easing.type: Easing.InCubic }
                NumberAnimation { target: nearWave; property: "opacity"; to: 0; duration: 280 }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 110 }
            ParallelAnimation {
                NumberAnimation { target: root; property: "noteOpacity"; to: root.dimmed; duration: 280 }
                SequentialAnimation {
                    NumberAnimation { target: root; property: "noteBob"; to: 1.1; duration: 170; easing.type: Easing.OutCubic }
                    NumberAnimation { target: root; property: "noteBob"; to: 0; duration: 330; easing.type: Easing.OutBack }
                }
                SequentialAnimation {
                    NumberAnimation { target: root; property: "flagKick"; to: 4; duration: 150; easing.type: Easing.OutCubic }
                    NumberAnimation { target: root; property: "flagKick"; to: 0; duration: 310; easing.type: Easing.OutBack }
                }
            }
        }
    }
}
