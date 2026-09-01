pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Volume, split into the speaker body and two sound waves.
 *
 * The geometry is lifted from the Material Symbols `volume_up` path rather than
 * estimated. Converted from its 0/-960 viewBox into this 24-grid, the glyph is:
 * cone x 3..12 y 4..20; near wave a *circular segment* — a disc of radius 4.41
 * about (12.09, 12) cut by the chord at x=14, so 2.5 wide by 7.95 tall; far
 * wave a crescent of the same family, radius 8 about (12.03, 12), 2.0 thick,
 * running from the same chord round to x=21.
 *
 * Both waves start at x=14 and nest into each other. Guessing at this produced
 * two arcs bunched on the right with a gap behind them, which reads as a ring
 * drawn around the icon instead of as sound leaving the cone.
 *
 * Louder pushes the waves out, quieter pulls them in, and the cone recoils
 * horizontally against them — the same give-and-take the Wi-Fi icon has when it
 * connects. Muting shrinks the waves back toward the cone and takes the whole
 * glyph down to a whisper, leaving only the slash at full strength.
 */
AnimatedIcon {
    id: root

    cueChannel: "volume"
    stroke: 2.3

    /** Waves lit at rest: 0 (muted), 1 (low), 2 (full). */
    property int waves: 2
    property bool busy: false
    property real slashProgress: 0

    readonly property real dimmed: 0.4

    /** The near wave: a filled circular segment, cut by the chord at x = 14. */
    component NearWave: Shape {
        id: nw
        property real centerX: 12.1
        property real rest: 4.4
        property real shrunk: 2.9
        property real radius: rest
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            // A filled path holding one arc closes on its own chord, which is
            // exactly the segment shape — and the radius stays animatable.
            PathAngleArc {
                centerX: nw.centerX
                centerY: 12
                radiusX: nw.radius
                radiusY: nw.radius
                startAngle: -64
                sweepAngle: 128
            }
        }
    }

    /** The far wave: the same crescent family, reaching from x = 14 to x = 21. */
    component FarWave: Shape {
        id: fw
        property real centerX: 12.0
        property real rest: 8.0
        property real shrunk: 5.4
        property real radius: rest
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: 2.0
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: fw.centerX
                centerY: 12
                radiusX: fw.radius
                radiusY: fw.radius
                startAngle: -74
                sweepAngle: 148
            }
        }
    }

    readonly property bool muted: root.waves === 0

    function applyRest(): void {
        body.x = 0;
        wave1.radius = root.muted ? wave1.shrunk : wave1.rest;
        wave2.radius = root.muted ? wave2.shrunk : wave2.rest;
        body.opacity = root.muted ? root.dimmed : 1;
        wave1.opacity = root.muted ? root.dimmed : (root.waves >= 1 ? 1 : 0);
        wave2.opacity = root.muted ? root.dimmed : (root.waves >= 2 ? 1 : 0);
        root.slashProgress = root.muted ? 1 : 0;
    }

    function stopAll(): void {
        upAnim.stop();
        downAnim.stop();
        muteAnim.stop();
        unmuteAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "up":
            upAnim.start();
            break;
        case "down":
            downAnim.start();
            break;
        case "mute":
            muteAnim.start();
            break;
        case "unmute":
            unmuteAnim.start();
            break;
        default:
            root.busy = false;
            break;
        }
    }

    onWavesChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: body
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: root.color
            strokeWidth: 1.0
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            // Material's own outline, inset by half the stroke that rounds it.
            PathSvg { path: "M 3.5 9.5 H 7.2 L 11.5 4.7 V 19.3 L 7.2 14.5 H 3.5 Z" }
        }
    }

    NearWave {
        id: wave1
    }
    FarWave {
        id: wave2
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.slashProgress > 0.02 ? 1 : 0
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 4.4
            startY: 4.4
            PathLine {
                x: 4.4 + 15.2 * root.slashProgress
                y: 4.4 + 15.2 * root.slashProgress
            }
        }
    }

    // ── Louder: the waves are pushed out and the cone recoils into them ─────
    SequentialAnimation {
        id: upAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 0;
                body.opacity = 1;
            }
        }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: body; property: "x"; to: -1.3; duration: 120; easing.type: Easing.OutCubic }
                NumberAnimation { target: body; property: "x"; to: 0; duration: 380; easing.type: Easing.OutBack }
            }
            ParallelAnimation {
                NumberAnimation { target: wave1; property: "radius"; from: wave1.rest - 1.9; to: wave1.rest; duration: 380; easing.type: Easing.OutBack }
                NumberAnimation { target: wave1; property: "opacity"; to: 1; duration: 180 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 100 }
                ParallelAnimation {
                    NumberAnimation { target: wave2; property: "radius"; from: wave2.rest - 2.0; to: wave2.rest; duration: 400; easing.type: Easing.OutBack }
                    NumberAnimation { target: wave2; property: "opacity"; to: root.waves >= 2 ? 1 : 0; duration: 200 }
                }
            }
        }
    }

    // ── Quieter: the waves are drawn back in and the cone follows them ──────
    SequentialAnimation {
        id: downAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 0;
                body.opacity = 1;
            }
        }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: body; property: "x"; to: 1.3; duration: 120; easing.type: Easing.OutCubic }
                NumberAnimation { target: body; property: "x"; to: 0; duration: 380; easing.type: Easing.OutBack }
            }
            ParallelAnimation {
                NumberAnimation { target: wave2; property: "radius"; from: wave2.rest + 2.0; to: wave2.rest; duration: 400; easing.type: Easing.OutBack }
                NumberAnimation { target: wave2; property: "opacity"; to: root.waves >= 2 ? 1 : 0; duration: 240 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 100 }
                ParallelAnimation {
                    NumberAnimation { target: wave1; property: "radius"; from: wave1.rest + 1.9; to: wave1.rest; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: wave1; property: "opacity"; to: root.waves >= 1 ? 1 : 0; duration: 240 }
                }
            }
        }
    }

    // ── Mute: the waves pull in, the glyph drops to a whisper, the slash lands
    SequentialAnimation {
        id: muteAnim
        onStopped: root.busy = false

        ScriptAction { script: root.slashProgress = 0 }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: body; property: "x"; to: 1.1; duration: 130; easing.type: Easing.OutCubic }
                NumberAnimation { target: body; property: "x"; to: 0; duration: 340; easing.type: Easing.OutBack }
            }
            NumberAnimation { target: wave2; property: "radius"; to: wave2.shrunk; duration: 360; easing.type: Easing.InCubic }
            SequentialAnimation {
                PauseAnimation { duration: 70 }
                NumberAnimation { target: wave1; property: "radius"; to: wave1.shrunk; duration: 360; easing.type: Easing.InCubic }
            }
            // Everything but the slash goes quiet.
            NumberAnimation { target: body; property: "opacity"; to: root.dimmed; duration: 340 }
            NumberAnimation { target: wave1; property: "opacity"; to: root.dimmed; duration: 340 }
            NumberAnimation { target: wave2; property: "opacity"; to: root.dimmed; duration: 340 }
            SequentialAnimation {
                PauseAnimation { duration: 170 }
                NumberAnimation { target: root; property: "slashProgress"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── Unmute: the slash retracts and the waves push back out ──────────────
    SequentialAnimation {
        id: unmuteAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 1;
                wave1.radius = wave1.shrunk;
                wave2.radius = wave2.shrunk;
                body.opacity = root.dimmed;
                wave1.opacity = root.dimmed;
                wave2.opacity = root.dimmed;
            }
        }
        NumberAnimation { target: root; property: "slashProgress"; to: 0; duration: 250; easing.type: Easing.InCubic }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: body; property: "x"; to: -1.1; duration: 120; easing.type: Easing.OutCubic }
                NumberAnimation { target: body; property: "x"; to: 0; duration: 360; easing.type: Easing.OutBack }
            }
            NumberAnimation { target: body; property: "opacity"; to: 1; duration: 280 }
            ParallelAnimation {
                NumberAnimation { target: wave1; property: "radius"; to: wave1.rest; duration: 400; easing.type: Easing.OutBack }
                NumberAnimation { target: wave1; property: "opacity"; to: 1; duration: 260 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 90 }
                ParallelAnimation {
                    NumberAnimation { target: wave2; property: "radius"; to: wave2.rest; duration: 420; easing.type: Easing.OutBack }
                    NumberAnimation { target: wave2; property: "opacity"; to: 1; duration: 260 }
                }
            }
        }
    }
}
