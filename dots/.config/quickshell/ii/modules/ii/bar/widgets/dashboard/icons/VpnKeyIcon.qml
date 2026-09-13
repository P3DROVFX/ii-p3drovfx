pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * VPN key, split into the bow (the ring you hold) and the blade with its teeth.
 *
 * Connecting drives the key in and turns it; disconnecting turns it back and
 * pulls it out. The rotation pivots on the bow, so the blade sweeps — which is
 * what makes it read as a key being turned rather than an icon being spun.
 */
AnimatedIcon {
    id: root

    cueChannel: "vpn"
    stroke: 2.1

    property bool connected: false
    property bool busy: false

    readonly property real bowX: 6.6
    readonly property real bowY: 12
    readonly property real dimmed: 0.4

    property real keyShift: 0
    property real keyTurn: 0

    function applyRest(): void {
        root.keyShift = 0;
        root.keyTurn = 0;
        bow.opacity = root.connected ? 1 : root.dimmed;
        blade.opacity = root.connected ? 1 : root.dimmed;
    }

    function stopAll(): void {
        connectAnim.stop();
        disconnectAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "connected":
            connectAnim.start();
            break;
        case "disconnected":
            disconnectAnim.start();
            break;
        default:
            root.busy = false;
            break;
        }
    }

    onConnectedChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: bow
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: [
            Rotation { origin.x: root.bowX; origin.y: root.bowY; angle: root.keyTurn },
            Translate { x: root.keyShift }
        ]
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            PathAngleArc {
                centerX: root.bowX
                centerY: root.bowY
                radiusX: 3.7
                radiusY: 3.7
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    Shape {
        id: blade
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: [
            Rotation { origin.x: root.bowX; origin.y: root.bowY; angle: root.keyTurn },
            Translate { x: root.keyShift }
        ]
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 10.3
            startY: root.bowY
            PathLine { x: 20.6; y: root.bowY }
        }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 16.4
            startY: root.bowY
            PathLine { x: 16.4; y: root.bowY + 3.4 }
        }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 20.6
            startY: root.bowY
            PathLine { x: 20.6; y: root.bowY + 3.4 }
        }
    }

    // ── Connected: driven in, then turned ───────────────────────────────────
    SequentialAnimation {
        id: connectAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.keyShift = -4.6;
                root.keyTurn = 0;
                bow.opacity = root.dimmed;
                blade.opacity = root.dimmed;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "keyShift"; to: 0; duration: 340; easing.type: Easing.OutCubic }
            NumberAnimation { target: bow; property: "opacity"; to: 1; duration: 260 }
            NumberAnimation { target: blade; property: "opacity"; to: 1; duration: 260 }
        }
        NumberAnimation { target: root; property: "keyTurn"; to: -19; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "keyTurn"; to: 0; duration: 420; easing.type: Easing.OutBack }
    }

    // ── Disconnected: turned back and pulled out ────────────────────────────
    SequentialAnimation {
        id: disconnectAnim
        onStopped: root.busy = false

        NumberAnimation { target: root; property: "keyTurn"; to: 15; duration: 200; easing.type: Easing.OutCubic }
        ParallelAnimation {
            NumberAnimation { target: root; property: "keyTurn"; to: 0; duration: 380; easing.type: Easing.OutBack }
            SequentialAnimation {
                PauseAnimation { duration: 80 }
                ParallelAnimation {
                    NumberAnimation { target: root; property: "keyShift"; to: -4.2; duration: 320; easing.type: Easing.InCubic }
                    NumberAnimation { target: bow; property: "opacity"; to: root.dimmed; duration: 300 }
                    NumberAnimation { target: blade; property: "opacity"; to: root.dimmed; duration: 300 }
                }
                NumberAnimation { target: root; property: "keyShift"; to: 0; duration: 1; }
            }
        }
    }
}
