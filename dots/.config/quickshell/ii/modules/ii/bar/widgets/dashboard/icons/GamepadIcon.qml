pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Game mode, following Material's `gamepad`: four pentagon arms whose points
 * meet at the centre with a gap between each. There is no centre block; that
 * is what keeps the pad from reading as a plus sign.
 *
 * Turning it on presses the arms outward in sequence — up, right, down, left —
 * the way a thumb walks a D-pad. Nothing pulses; the arms travel.
 */
AnimatedIcon {
    id: root

    cueChannel: "gamemode"

    property bool active: false
    property bool busy: false

    readonly property real dimmed: 0.35

    component Arm: Shape {
        id: arm
        required property int index
        property real push: 0
        opacity: root.active ? 1 : root.dimmed
        readonly property real dx: [0, 1, 0, -1][arm.index]
        readonly property real dy: [-1, 0, 1, 0][arm.index]
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate {
            x: arm.dx * arm.push
            y: arm.dy * arm.push
        }
        ShapePath {
            // The silhouette is filled, never outlined.  Geometry is the
            // glyph's 960 grid scaled to 24; the arms never touch, so dimmed
            // alpha cannot accumulate, even while the off cue pulls them in.
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg {
                path: [
                    "M 9.6 3.5 Q 9.6 3 10.1 3 H 13.9 Q 14.4 3 14.4 3.5 V 7.95 L 12 10.35 L 9.6 7.95 Z",
                    "M 16.05 9.6 H 20.5 Q 21 9.6 21 10.1 V 13.9 Q 21 14.4 20.5 14.4 H 16.05 L 13.65 12 Z",
                    "M 12 13.65 L 14.4 16.05 V 20.5 Q 14.4 21 13.9 21 H 10.1 Q 9.6 21 9.6 20.5 V 16.05 Z",
                    "M 3.5 9.6 H 7.95 L 10.35 12 L 7.95 14.4 H 3.5 Q 3 14.4 3 13.9 V 10.1 Q 3 9.6 3.5 9.6 Z"
                ][arm.index]
            }
        }
    }

    function applyRest(): void {
        upArm.push = 0;
        upArm.opacity = root.active ? 1 : root.dimmed;
        rightArm.push = 0;
        rightArm.opacity = root.active ? 1 : root.dimmed;
        downArm.push = 0;
        downArm.opacity = root.active ? 1 : root.dimmed;
        leftArm.push = 0;
        leftArm.opacity = root.active ? 1 : root.dimmed;
    }

    function stopAll(): void {
        onAnim.stop();
        offAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "on":
            onAnim.start();
            break;
        case "off":
            offAnim.start();
            break;
        default:
            root.busy = false;
            break;
        }
    }

    onActiveChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // These must be stable ids: declarative animation targets cannot observe
    // a later Repeater.itemAt() result after evaluating to null at construction.
    Arm { id: upArm; index: 0 }
    Arm { id: rightArm; index: 1 }
    Arm { id: downArm; index: 2 }
    Arm { id: leftArm; index: 3 }

    // ── On: a thumb walks the pad, clockwise from up ────────────────────────
    ParallelAnimation {
        id: onAnim
        onStopped: root.busy = false

        SequentialAnimation {
            PauseAnimation { duration: 0 }
            ParallelAnimation {
                NumberAnimation { target: upArm; property: "push"; from: 0; to: 1.5; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: upArm; property: "opacity"; to: 1; duration: 200 }
            }
            NumberAnimation { target: upArm; property: "push"; to: 0; duration: 340; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            ParallelAnimation {
                NumberAnimation { target: rightArm; property: "push"; from: 0; to: 1.5; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: rightArm; property: "opacity"; to: 1; duration: 200 }
            }
            NumberAnimation { target: rightArm; property: "push"; to: 0; duration: 340; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            ParallelAnimation {
                NumberAnimation { target: downArm; property: "push"; from: 0; to: 1.5; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: downArm; property: "opacity"; to: 1; duration: 200 }
            }
            NumberAnimation { target: downArm; property: "push"; to: 0; duration: 340; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            PauseAnimation { duration: 270 }
            ParallelAnimation {
                NumberAnimation { target: leftArm; property: "push"; from: 0; to: 1.5; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: leftArm; property: "opacity"; to: 1; duration: 200 }
            }
            NumberAnimation { target: leftArm; property: "push"; to: 0; duration: 340; easing.type: Easing.OutBack }
        }
    }

    // ── Off: the arms pull toward the centre and go quiet ─────────────────────
    ParallelAnimation {
        id: offAnim
        onStopped: root.busy = false

        SequentialAnimation {
            NumberAnimation { target: upArm; property: "push"; to: -1.2; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: upArm; property: "push"; to: 0; duration: 360; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: rightArm; property: "push"; to: -1.2; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: rightArm; property: "push"; to: 0; duration: 360; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: downArm; property: "push"; to: -1.2; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: downArm; property: "push"; to: 0; duration: 360; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: leftArm; property: "push"; to: -1.2; duration: 220; easing.type: Easing.OutCubic }
            NumberAnimation { target: leftArm; property: "push"; to: 0; duration: 360; easing.type: Easing.OutBack }
        }
        NumberAnimation { target: upArm; property: "opacity"; to: root.dimmed; duration: 300 }
        NumberAnimation { target: rightArm; property: "opacity"; to: root.dimmed; duration: 300 }
        NumberAnimation { target: downArm; property: "opacity"; to: root.dimmed; duration: 300 }
        NumberAnimation { target: leftArm; property: "opacity"; to: root.dimmed; duration: 300 }
    }
}
