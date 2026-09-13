pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Caffeine (idle inhibitor), split into the cup, its handle, the coffee inside
 * and the saucer under it.
 *
 * Turning it on fills the cup — the surface of the liquid travels up — while
 * the cup itself lifts a little and settles back onto the saucer. Turning it
 * off drains it the same way.
 */
AnimatedIcon {
    id: root

    cueChannel: "caffeine"
    stroke: 2.0

    /** Filled at rest. */
    property bool active: false
    property bool busy: false

    readonly property real brimY: 8.6
    readonly property real floorY: 16.2
    readonly property real dimmed: 0.4

    /** Surface of the coffee: floorY is empty, brimY is full. */
    property real liquidTop: floorY
    property real cupLift: 0

    function applyRest(): void {
        root.liquidTop = root.active ? root.brimY : root.floorY;
        root.cupLift = 0;
        cup.opacity = 1;
        handle.opacity = 1;
        saucer.opacity = root.active ? 1 : root.dimmed;
    }

    function stopAll(): void {
        fillAnim.stop();
        drainAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "on":
            fillAnim.start();
            break;
        case "off":
            drainAnim.start();
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

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: liquid
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: root.cupLift }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            startX: 6.7
            startY: root.liquidTop
            PathLine { x: 14.5; y: root.liquidTop }
            PathLine { x: 14.5; y: root.floorY }
            PathLine { x: 6.7; y: root.floorY }
            PathLine { x: 6.7; y: root.liquidTop }
        }
    }

    Shape {
        id: cup
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: root.cupLift }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: "M 5.4 7.4 H 15.8 V 15.2 a 2.2 2.2 0 0 1 -2.2 2.2 H 7.6 a 2.2 2.2 0 0 1 -2.2 -2.2 Z" }
        }
    }

    Shape {
        id: handle
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Translate { y: root.cupLift }
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            PathSvg { path: "M 15.8 9.2 h 1.9 a 2.6 2.6 0 0 1 0 5.2 h -1.9" }
        }
    }

    Shape {
        id: saucer
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 3.6
            startY: 20.4
            PathLine { x: 20.4; y: 20.4 }
        }
    }

    // ── On: the cup is lifted, poured into, and set back down ───────────────
    ParallelAnimation {
        id: fillAnim
        onStopped: root.busy = false

        SequentialAnimation {
            NumberAnimation { target: root; property: "cupLift"; to: -1.5; duration: 180; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 120 }
            NumberAnimation { target: root; property: "cupLift"; to: 0; duration: 420; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation { target: root; property: "liquidTop"; from: root.floorY; to: root.brimY; duration: 520; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 200 }
            NumberAnimation { target: saucer; property: "opacity"; to: 1; duration: 300 }
        }
    }

    // ── Off: it drains, and the cup comes to rest ───────────────────────────
    ParallelAnimation {
        id: drainAnim
        onStopped: root.busy = false

        SequentialAnimation {
            NumberAnimation { target: root; property: "cupLift"; to: 1.1; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "cupLift"; to: 0; duration: 400; easing.type: Easing.OutBack }
        }
        NumberAnimation { target: root; property: "liquidTop"; to: root.floorY; duration: 440; easing.type: Easing.InCubic }
        NumberAnimation { target: saucer; property: "opacity"; to: root.dimmed; duration: 340 }
    }
}
