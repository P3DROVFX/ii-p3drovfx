pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Notification bell, split into the hood and the clapper.
 *
 * Both hang from the same pivot at the top of the bell, but the clapper starts
 * late and swings wider — that lag is the whole trick. A bell whose clapper
 * moves in lockstep with the hood reads as a rotating picture; one that trails
 * reads as a bell that was struck.
 */
AnimatedIcon {
    id: root

    cueChannel: "notification"

    /** Silenced at rest: the glyph stays dimmed under the slash. */
    property bool silent: false
    property bool busy: false
    property real slashProgress: 0
    readonly property real dimmed: 0.4
    property real hoodAngle: 0
    property real clapperAngle: 0
    property real clapperDrop: 0

    readonly property real pivotX: 12
    readonly property real pivotY: 4.4

    function applyRest(): void {
        const lit = root.silent ? root.dimmed : 1;
        root.hoodAngle = 0;
        root.clapperAngle = 0;
        root.clapperDrop = root.silent ? 3.2 : 0;
        clapper.opacity = root.silent ? 0 : 1;
        hood.opacity = lit;
        root.slashProgress = root.silent ? 1 : 0;
    }

    function stopAll(): void {
        arriveAnim.stop();
        silenceAnim.stop();
        unsilenceAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "arrive":
            root.slashProgress = 0;
            root.clapperDrop = 0;
            clapper.opacity = 1;
            hood.opacity = 1;
            arriveAnim.start();
            break;
        case "silence":
            silenceAnim.start();
            break;
        case "unsilence":
            unsilenceAnim.start();
            break;
        default:
            root.busy = false;
            break;
        }
    }

    onSilentChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: hood
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Rotation {
            origin.x: root.pivotX
            origin.y: root.pivotY
            angle: root.hoodAngle
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg {
                path: "M 18.6 16.6 v -5.6 c 0 -3.4 -2.2 -6.15 -5.35 -6.85 v -0.75 c 0 -0.72 -0.53 -1.3 -1.25 -1.3 s -1.25 0.58 -1.25 1.3 v 0.75 C 7.6 4.85 5.4 7.6 5.4 11 v 5.6 l -1.8 1.8 v 0.9 h 16.8 v -0.9 z"
            }
        }
    }

    Shape {
        id: clapper
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: [
            Rotation {
                origin.x: root.pivotX
                origin.y: root.pivotY
                angle: root.clapperAngle
            },
            Translate {
                y: root.clapperDrop
            }
        ]
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg { path: "M 12 22.2 c 1.21 0 2.2 -0.99 2.2 -2.2 h -4.4 c 0 1.21 0.99 2.2 2.2 2.2 z" }
        }
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
            startX: 4.2
            startY: 4.2
            PathLine {
                x: 4.2 + 15.6 * root.slashProgress
                y: 4.2 + 15.6 * root.slashProgress
            }
        }
    }

    // ── A notification arrives: struck, then damped ─────────────────────────
    ParallelAnimation {
        id: arriveAnim
        onStopped: root.busy = false

        SequentialAnimation {
            NumberAnimation { target: root; property: "hoodAngle"; to: 13; duration: 130; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "hoodAngle"; to: -9.5; duration: 190; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "hoodAngle"; to: 6; duration: 165; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "hoodAngle"; to: -3.4; duration: 145; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "hoodAngle"; to: 1.4; duration: 130; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "hoodAngle"; to: 0; duration: 160; easing.type: Easing.OutSine }
        }

        // The clapper trails the hood by a beat and swings a little wider.
        SequentialAnimation {
            PauseAnimation { duration: 75 }
            NumberAnimation { target: root; property: "clapperAngle"; to: 17.5; duration: 150; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "clapperAngle"; to: -12.5; duration: 200; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "clapperAngle"; to: 7.5; duration: 170; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "clapperAngle"; to: -4; duration: 150; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "clapperAngle"; to: 1.6; duration: 130; easing.type: Easing.InOutSine }
            NumberAnimation { target: root; property: "clapperAngle"; to: 0; duration: 170; easing.type: Easing.OutSine }
        }
    }

    // ── Silenced: the clapper falls out and the slash draws ─────────────────
    SequentialAnimation {
        id: silenceAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 0;
                hood.opacity = 1;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: hood; property: "opacity"; to: root.dimmed; duration: 340 }
            SequentialAnimation {
                NumberAnimation { target: root; property: "hoodAngle"; to: 6.5; duration: 130; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "hoodAngle"; to: 0; duration: 380; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                PauseAnimation { duration: 60 }
                ParallelAnimation {
                    NumberAnimation { target: root; property: "clapperDrop"; to: 3.2; duration: 320; easing.type: Easing.InCubic }
                    NumberAnimation { target: clapper; property: "opacity"; to: 0; duration: 300 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 170 }
                NumberAnimation { target: root; property: "slashProgress"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── Unsilenced: the slash retracts and the clapper is put back ──────────
    SequentialAnimation {
        id: unsilenceAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 1;
                root.clapperDrop = 3.2;
                clapper.opacity = 0;
                hood.opacity = root.dimmed;
            }
        }
        NumberAnimation { target: root; property: "slashProgress"; to: 0; duration: 250; easing.type: Easing.InCubic }
        ParallelAnimation {
            NumberAnimation { target: hood; property: "opacity"; to: 1; duration: 300 }
            NumberAnimation { target: clapper; property: "opacity"; to: 1; duration: 180 }
            NumberAnimation { target: root; property: "clapperDrop"; to: 0; duration: 420; easing.type: Easing.OutBack }
            SequentialAnimation {
                NumberAnimation { target: root; property: "hoodAngle"; to: -5; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "hoodAngle"; to: 0; duration: 360; easing.type: Easing.OutBack }
            }
        }
    }
}
