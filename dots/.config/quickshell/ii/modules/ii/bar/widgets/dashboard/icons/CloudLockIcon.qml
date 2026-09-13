pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Cloudflare WARP, using the proportions of Material's `cloud_lock`: a broad
 * cloud occupies the canvas and the lock attaches at the lower-right instead
 * of floating below a small cloud.
 *
 * The cloud, shackle and lock body are independent. Connecting lowers the
 * shackle while the body receives it and the cloud shifts against that motion;
 * disconnecting lifts the shackle before the whole mark goes quiet.
 */
AnimatedIcon {
    id: root

    cueChannel: "warp"
    stroke: 2.0

    property bool connected: false
    property bool busy: false

    readonly property real dimmed: 0.4
    property real shackleLift: 0
    property real cloudDrift: 0
    property real lockPress: 0

    function applyRest(): void {
        root.shackleLift = root.connected ? 0 : 2.2;
        root.cloudDrift = 0;
        root.lockPress = 0;
        const lit = root.connected ? 1 : root.dimmed;
        cloud.opacity = lit;
        shackle.opacity = lit;
        lockBody.opacity = lit;
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

    // Material `cloud_lock` cloud, normalized from 960 to the 24-unit grid.
    // It deliberately ends around x=14 so the lock owns the lower-right space.
    Shape {
        id: cloud

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { x: root.cloudDrift }

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg {
                path: "M 6.5 20 Q 4.225 20 2.613 18.425 Q 1 16.85 1 14.575 Q 1 12.625 2.175 11.1 Q 3.35 9.575 5.25 9.15 Q 5.875 6.85 7.75 5.425 Q 9.625 4 12 4 Q 14.4 4 16.238 5.4 Q 18.075 6.8 18.725 9 Q 18.85 9.425 18.613 9.75 Q 18.375 10.075 18.025 10.175 Q 17.675 10.275 17.3 10.1 Q 16.925 9.925 16.75 9.425 Q 16.25 7.925 14.95 6.963 Q 13.65 6 12 6 Q 9.925 6 8.463 7.463 Q 7 8.925 7 11 H 6.5 Q 5.05 11 4.025 12.025 Q 3 13.05 3 14.5 Q 3 15.95 4.025 16.975 Q 5.05 18 6.5 18 H 13 Q 13.425 18 13.713 18.288 Q 14 18.575 14 19 Q 14 19.425 13.713 19.713 Q 13.425 20 13 20 Z"
            }
        }
    }

    Shape {
        id: shackle

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: -root.shackleLift + root.lockPress }

        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M 17 15 V 14 Q 17 12 19 12 Q 21 12 21 14 V 15" }
        }
    }

    Shape {
        id: lockBody

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: root.lockPress }

        ShapePath {
            strokeColor: root.color
            fillColor: root.color
            strokeWidth: 0.8
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: "M 17 15 H 21 Q 22 15 22 16 V 19 Q 22 20 21 20 H 17 Q 16 20 16 19 V 16 Q 16 15 17 15 Z"
            }
        }
    }

    SequentialAnimation {
        id: connectAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.shackleLift = 2.4;
                root.cloudDrift = 0;
                root.lockPress = 0;
                cloud.opacity = root.dimmed;
                shackle.opacity = root.dimmed;
                lockBody.opacity = root.dimmed;
            }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "shackleLift"; to: 0; duration: 400; easing.type: Easing.OutBack }
            NumberAnimation { target: cloud; property: "opacity"; to: 1; duration: 280 }
            NumberAnimation { target: shackle; property: "opacity"; to: 1; duration: 280 }
            NumberAnimation { target: lockBody; property: "opacity"; to: 1; duration: 280 }
            SequentialAnimation {
                NumberAnimation { target: root; property: "cloudDrift"; to: -0.9; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "cloudDrift"; to: 0; duration: 360; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                NumberAnimation { target: root; property: "lockPress"; to: 0.6; duration: 120; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "lockPress"; to: 0; duration: 300; easing.type: Easing.OutBack }
            }
        }
    }

    ParallelAnimation {
        id: disconnectAnim
        onStopped: root.busy = false

        NumberAnimation { target: root; property: "shackleLift"; to: 2.2; duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: cloud; property: "opacity"; to: root.dimmed; duration: 340 }
        NumberAnimation { target: shackle; property: "opacity"; to: root.dimmed; duration: 340 }
        NumberAnimation { target: lockBody; property: "opacity"; to: root.dimmed; duration: 340 }
        SequentialAnimation {
            NumberAnimation { target: root; property: "cloudDrift"; to: 0.9; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "cloudDrift"; to: 0; duration: 380; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            NumberAnimation { target: root; property: "lockPress"; to: -0.45; duration: 150; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "lockPress"; to: 0; duration: 350; easing.type: Easing.OutBack }
        }
    }
}
