pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Game mode, following Material's `gamepad`: the D-pad cross, built as four
 * non-overlapping arms around a separate centre.
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
        readonly property real dx: [0, 1, 0, -1][arm.index]
        readonly property real dy: [-1, 0, 1, 0][arm.index]
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate {
            x: arm.dx * arm.push
            y: arm.dy * arm.push
        }
        ShapePath {
            // The silhouette is filled, never outlined.  Each arm stops at
            // the centre edge so dimmed alpha cannot accumulate there.
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg {
                path: [
                    "M 10.4 4.7 Q 10.4 4.2 10.9 4.2 H 13.1 Q 13.6 4.2 13.6 4.7 V 10.4 H 10.4 Z",
                    "M 13.6 10.4 H 19.3 Q 19.8 10.4 19.8 10.9 V 13.1 Q 19.8 13.6 19.3 13.6 H 13.6 Z",
                    "M 10.4 13.6 H 13.6 V 19.3 Q 13.6 19.8 13.1 19.8 H 10.9 Q 10.4 19.8 10.4 19.3 Z",
                    "M 4.7 10.4 H 10.4 V 13.6 H 4.7 Q 4.2 13.6 4.2 13.1 V 10.9 Q 4.2 10.4 4.7 10.4 Z"
                ][arm.index]
            }
        }
    }

    function armAt(index: int): Item {
        switch (index) {
        case 0: return upArm;
        case 1: return rightArm;
        case 2: return downArm;
        case 3: return leftArm;
        default: return null;
        }
    }

    function applyRest(): void {
        for (let i = 0; i < 4; i++) {
            const arm = root.armAt(i);
            if (!arm)
                continue;
            arm.push = 0;
            arm.opacity = root.active ? 1 : root.dimmed;
        }
        center.opacity = root.active ? 1 : root.dimmed;
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

    Component.onCompleted: Qt.callLater(root.applyRest)

    // These must be stable ids: declarative animation targets cannot observe
    // a later Repeater.itemAt() result after evaluating to null at construction.
    Arm { id: upArm; index: 0 }
    Arm { id: rightArm; index: 1 }
    Arm { id: downArm; index: 2 }
    Arm { id: leftArm; index: 3 }

    Shape {
        id: center

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg { path: "M 10.4 10.4 H 13.6 V 13.6 H 10.4 Z" }
        }
    }

    // ── On: a thumb walks the pad, clockwise from up ────────────────────────
    ParallelAnimation {
        id: onAnim
        onStopped: root.busy = false

        NumberAnimation { target: center; property: "opacity"; to: 1; duration: 200 }

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

    // ── Off: the arms pull into the centre and go quiet ─────────────────────
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
        NumberAnimation { target: center; property: "opacity"; to: root.dimmed; duration: 300 }
    }
}
