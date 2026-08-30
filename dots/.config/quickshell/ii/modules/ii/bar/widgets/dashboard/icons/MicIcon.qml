pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Microphone, split into the capsule, the stand and the stem.
 *
 * Muting drops the capsule down into the cradle before the slash lands, so the
 * gesture is "the mic was put away", not "a line appeared on top of a mic".
 */
AnimatedIcon {
    id: root

    cueChannel: "mic"

    /** Muted at rest: the glyph stays dimmed under the slash. */
    property bool muted: false
    property bool busy: false
    property real slashProgress: 0
    property real capsuleDrop: 0
    property real standDrop: 0

    readonly property real dimmed: 0.4

    function applyRest(): void {
        const lit = root.muted ? root.dimmed : 1;
        root.capsuleDrop = root.muted ? 2.7 : 0;
        root.standDrop = 0;
        capsule.opacity = lit;
        stand.opacity = lit;
        root.slashProgress = root.muted ? 1 : 0;
    }

    function stopAll(): void {
        muteAnim.stop();
        unmuteAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
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

    onMutedChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: capsule
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: root.capsuleDrop }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg {
                path: "M 12 14.7 c 1.72 0 3.1 -1.38 3.1 -3.1 v -6.2 c 0 -1.72 -1.38 -3.1 -3.1 -3.1 s -3.1 1.38 -3.1 3.1 v 6.2 c 0 1.72 1.38 3.1 3.1 3.1 z"
            }
        }
    }

    Shape {
        id: stand
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: root.standDrop }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M 5.6 11.3 a 6.4 6.4 0 0 0 12.8 0" }
        }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 12
            startY: 17.7
            PathLine { x: 12; y: 21.2 }
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

    // ── Mute: the capsule drops into the cradle, then the slash draws ───────
    SequentialAnimation {
        id: muteAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 0;
                capsule.opacity = 1;
                stand.opacity = 1;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "capsuleDrop"; to: 2.7; duration: 300; easing.type: Easing.OutCubic }
            NumberAnimation { target: capsule; property: "opacity"; to: root.dimmed; duration: 340 }
            NumberAnimation { target: stand; property: "opacity"; to: root.dimmed; duration: 340 }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                NumberAnimation { target: root; property: "standDrop"; to: 0.8; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "standDrop"; to: 0; duration: 280; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                PauseAnimation { duration: 160 }
                NumberAnimation { target: root; property: "slashProgress"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── Unmute: the slash retracts, the capsule is lifted back out ──────────
    SequentialAnimation {
        id: unmuteAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 1;
                root.capsuleDrop = 2.7;
                capsule.opacity = root.dimmed;
                stand.opacity = root.dimmed;
            }
        }
        NumberAnimation { target: root; property: "slashProgress"; to: 0; duration: 250; easing.type: Easing.InCubic }
        ParallelAnimation {
            NumberAnimation { target: root; property: "capsuleDrop"; to: 0; duration: 440; easing.type: Easing.OutBack }
            NumberAnimation { target: capsule; property: "opacity"; to: 1; duration: 300 }
            NumberAnimation { target: stand; property: "opacity"; to: 1; duration: 300 }
        }
    }
}
