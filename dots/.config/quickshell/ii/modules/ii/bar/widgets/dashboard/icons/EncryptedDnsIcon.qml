pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Encrypted DNS, following Material's `encrypted` / `no_encryption`: a padlock
 * whose shackle is a separate part from its body.
 *
 * Switching on drops the shackle into the body — the icon locks itself rather
 * than swapping glyphs. While a switch is in flight the shackle rides up and
 * down, which is the honest picture of "still negotiating".
 */
AnimatedIcon {
    id: root

    cueChannel: "dns"
    stroke: 2.0

    property bool active: false
    property bool busy: false

    readonly property real dimmed: 0.4
    property real slashProgress: 0
    property real shackleLift: 0

    function applyRest(): void {
        root.shackleLift = root.active ? 0 : 2.6;
        root.slashProgress = root.active ? 0 : 1;
        const lit = root.active ? 1 : root.dimmed;
        shackle.opacity = lit;
        lockBody.opacity = lit;
    }

    function stopAll(): void {
        onAnim.stop();
        offAnim.stop();
        busyAnim.stop();
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
        case "switching":
            busyAnim.start();
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

    Shape {
        id: shackle
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: -root.shackleLift }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M 8.2 10.4 V 7.6 a 3.8 3.8 0 0 1 7.6 0 v 2.8" }
        }
    }

    Shape {
        id: lockBody
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M 6.6 10.6 h 10.8 a 1.8 1.8 0 0 1 1.8 1.8 v 6.6 a 1.8 1.8 0 0 1 -1.8 1.8 H 6.6 a 1.8 1.8 0 0 1 -1.8 -1.8 v -6.6 a 1.8 1.8 0 0 1 1.8 -1.8 z" }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathAngleArc {
                centerX: 12
                centerY: 15.7
                radiusX: 1.7
                radiusY: 1.7
                startAngle: 0
                sweepAngle: 360
            }
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

    SequentialAnimation {
        id: onAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 1;
                root.shackleLift = 2.6;
                shackle.opacity = root.dimmed;
                lockBody.opacity = root.dimmed;
            }
        }
        NumberAnimation { target: root; property: "slashProgress"; to: 0; duration: 240; easing.type: Easing.InCubic }
        ParallelAnimation {
            NumberAnimation { target: root; property: "shackleLift"; to: 0; duration: 380; easing.type: Easing.OutBack }
            NumberAnimation { target: shackle; property: "opacity"; to: 1; duration: 280 }
            NumberAnimation { target: lockBody; property: "opacity"; to: 1; duration: 280 }
        }
    }

    SequentialAnimation {
        id: offAnim
        onStopped: root.busy = false

        ScriptAction { script: root.slashProgress = 0 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "shackleLift"; to: 2.6; duration: 320; easing.type: Easing.OutCubic }
            NumberAnimation { target: shackle; property: "opacity"; to: root.dimmed; duration: 320 }
            NumberAnimation { target: lockBody; property: "opacity"; to: root.dimmed; duration: 320 }
            SequentialAnimation {
                PauseAnimation { duration: 150 }
                NumberAnimation { target: root; property: "slashProgress"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            }
        }
    }

    SequentialAnimation {
        id: busyAnim
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "shackleLift"; to: 2.4; duration: 340; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "shackleLift"; to: 0.4; duration: 340; easing.type: Easing.InOutSine }
    }
}
