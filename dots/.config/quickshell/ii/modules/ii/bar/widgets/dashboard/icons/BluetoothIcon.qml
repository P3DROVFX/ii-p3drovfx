pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Bluetooth, split into the stem, the two wings of the rune, and two scan dots.
 *
 * Scanning sends the dots travelling outward from the stem and back — the
 * reach of a search, not a blink. Pairing swings them out hard once and stops,
 * with the wings snapping open and shut behind them.
 */
AnimatedIcon {
    id: root

    cueChannel: "bluetooth"

    /** A device is connected: the two indicator dots stay parked on the sides,
        the way Material's bluetooth_connected draws them. */
    property bool connected: false
    /** The adapter is off: the glyph stays dimmed under the slash. */
    property bool poweredOff: false
    property bool busy: false

    readonly property real dotRestX: 3.1
    readonly property real dimmed: 0.4

    component Wing: Shape {
        id: wing
        property real vx: 17.5
        property real vy1: 8.5
        property real vy2: 15.5
        property real tipY: 3
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transformOrigin: Item.Center
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 12
            startY: wing.tipY
            PathLine { x: wing.vx; y: wing.vy1 }
            PathLine { x: 24 - wing.vx; y: wing.vy2 }
        }
    }

    component ScanDot: Shape {
        id: sd
        property real cx: 12
        property real cy: 12
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: 0
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathAngleArc {
                centerX: sd.cx
                centerY: sd.cy
                radiusX: 1.55
                radiusY: 1.55
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    function applyRest(): void {
        const lit = root.poweredOff ? root.dimmed : 1;
        upperWing.rotation = 0;
        lowerWing.rotation = 0;
        upperWing.opacity = lit;
        lowerWing.opacity = lit;
        stem.opacity = lit;
        dotLeft.cx = root.dotRestX;
        dotRight.cx = 24 - root.dotRestX;
        dotLeft.cy = 12;
        dotRight.cy = 12;
        const dots = (root.connected && !root.poweredOff) ? 1 : 0;
        dotLeft.opacity = dots;
        dotRight.opacity = dots;
        root.slashProgress = root.poweredOff ? 1 : 0;
    }

    function stopAll(): void {
        scanAnim.stop();
        connectAnim.stop();
        disconnectAnim.stop();
        disableAnim.stop();
        unslashAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.applyRest();
        root.busy = true;
        switch (cue) {
        case "scanning":
            scanAnim.start();
            break;
        case "connected":
            connectAnim.start();
            break;
        case "disconnected":
            disconnectAnim.start();
            break;
        case "disabled":
            disableAnim.start();
            break;
        case "enabled":
            unslashAnim.start();
            break;
        case "settle":
            // A scan simply ending is not an event; go back to rest silently.
            root.applyRest();
            root.busy = false;
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
    onPoweredOffChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: stem
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 12
            startY: 3
            PathLine { x: 12; y: 21 }
        }
    }

    Wing {
        id: upperWing
        tipY: 3
        vy1: 8.5
        vy2: 15.5
    }
    Wing {
        id: lowerWing
        tipY: 21
        vy1: 15.5
        vy2: 8.5
    }

    ScanDot {
        id: dotLeft
    }
    ScanDot {
        id: dotRight
    }

    // A slash that draws itself: the far endpoint travels, it does not fade in.
    property real slashProgress: 0
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.slashProgress > 0.02 ? 1 : 0
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: 4.6
            startY: 4.6
            PathLine {
                x: 4.6 + 14.8 * root.slashProgress
                y: 4.6 + 14.8 * root.slashProgress
            }
        }
    }

    // ── Scanning: the dots reach outward and come back, out of phase ────────
    ParallelAnimation {
        id: scanAnim

        SequentialAnimation {
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: dotRight; property: "cx"; from: 14.2; to: 20.6; duration: 620; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    NumberAnimation { target: dotRight; property: "opacity"; from: 0; to: 1; duration: 200 }
                    PauseAnimation { duration: 160 }
                    NumberAnimation { target: dotRight; property: "opacity"; to: 0; duration: 260 }
                }
            }
            PauseAnimation { duration: 360 }
        }

        SequentialAnimation {
            loops: Animation.Infinite
            PauseAnimation { duration: 200 }
            ParallelAnimation {
                NumberAnimation { target: dotLeft; property: "cx"; from: 9.8; to: 3.4; duration: 620; easing.type: Easing.OutCubic }
                SequentialAnimation {
                    NumberAnimation { target: dotLeft; property: "opacity"; from: 0; to: 1; duration: 200 }
                    PauseAnimation { duration: 160 }
                    NumberAnimation { target: dotLeft; property: "opacity"; to: 0; duration: 260 }
                }
            }
            PauseAnimation { duration: 160 }
        }

        // The wings breathe with the search, a couple of degrees, no more.
        SequentialAnimation {
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: upperWing; property: "rotation"; from: 0; to: 2.6; duration: 490; easing.type: Easing.InOutSine }
                NumberAnimation { target: lowerWing; property: "rotation"; from: 0; to: -2.6; duration: 490; easing.type: Easing.InOutSine }
            }
            ParallelAnimation {
                NumberAnimation { target: upperWing; property: "rotation"; to: 0; duration: 490; easing.type: Easing.InOutSine }
                NumberAnimation { target: lowerWing; property: "rotation"; to: 0; duration: 490; easing.type: Easing.InOutSine }
            }
        }
    }

    // ── Connected: one hard swing out, wings snap, everything stops ─────────
    SequentialAnimation {
        id: connectAnim
        onStopped: root.busy = false

        ParallelAnimation {
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { target: dotRight; property: "cx"; from: 12; to: 24 - root.dotRestX; duration: 420; easing.type: Easing.OutBack }
                    NumberAnimation { target: dotRight; property: "opacity"; from: 0; to: 1; duration: 200 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 70 }
                ParallelAnimation {
                    NumberAnimation { target: dotLeft; property: "cx"; from: 12; to: root.dotRestX; duration: 420; easing.type: Easing.OutBack }
                    NumberAnimation { target: dotLeft; property: "opacity"; from: 0; to: 1; duration: 200 }
                }
            }
            SequentialAnimation {
                NumberAnimation { target: upperWing; property: "rotation"; to: -6; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: upperWing; property: "rotation"; to: 0; duration: 440; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                NumberAnimation { target: lowerWing; property: "rotation"; to: 6; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: lowerWing; property: "rotation"; to: 0; duration: 440; easing.type: Easing.OutBack }
            }
        }
        ScriptAction { script: root.applyRest() }
    }

    // ── Disconnected: the wings let go and the dots fall away ───────────────
    SequentialAnimation {
        id: disconnectAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                dotLeft.cx = root.dotRestX;
                dotRight.cx = 24 - root.dotRestX;
                dotLeft.opacity = 1;
                dotRight.opacity = 1;
            }
        }
        ParallelAnimation {
            ParallelAnimation {
                NumberAnimation { target: dotLeft; property: "cy"; from: 12; to: 18.5; duration: 400; easing.type: Easing.InCubic }
                NumberAnimation { target: dotLeft; property: "opacity"; to: 0; duration: 360 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 70 }
                ParallelAnimation {
                    NumberAnimation { target: dotRight; property: "cy"; from: 12; to: 18.5; duration: 400; easing.type: Easing.InCubic }
                    NumberAnimation { target: dotRight; property: "opacity"; to: 0; duration: 360 }
                }
            }
            // A single nudge of the whole rune, kept small: the two wings must
            // never come apart, that reads as the glyph breaking.
            SequentialAnimation {
                NumberAnimation { target: upperWing; property: "rotation"; to: 4; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: upperWing; property: "rotation"; to: 0; duration: 420; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                NumberAnimation { target: lowerWing; property: "rotation"; to: 4; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: lowerWing; property: "rotation"; to: 0; duration: 420; easing.type: Easing.OutBack }
            }
        }
        ScriptAction { script: root.applyRest() }
    }

    // ── Turned off: the wings fold in and the slash draws across ────────────
    SequentialAnimation {
        id: disableAnim
        onStopped: root.busy = false

        ParallelAnimation {
            NumberAnimation { target: upperWing; property: "opacity"; to: root.dimmed; duration: 340 }
            NumberAnimation { target: lowerWing; property: "opacity"; to: root.dimmed; duration: 340 }
            NumberAnimation { target: stem; property: "opacity"; to: root.dimmed; duration: 340 }
            ParallelAnimation {
                NumberAnimation { target: dotLeft; property: "cx"; to: 12; duration: 260; easing.type: Easing.InCubic }
                NumberAnimation { target: dotRight; property: "cx"; to: 12; duration: 260; easing.type: Easing.InCubic }
                NumberAnimation { target: dotLeft; property: "opacity"; to: 0; duration: 220 }
                NumberAnimation { target: dotRight; property: "opacity"; to: 0; duration: 220 }
            }
            SequentialAnimation {
                PauseAnimation { duration: 100 }
                NumberAnimation { target: root; property: "slashProgress"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── Turned back on: the slash retracts, the wings unfold ────────────────
    SequentialAnimation {
        id: unslashAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                root.slashProgress = 1;
                upperWing.opacity = root.dimmed;
                lowerWing.opacity = root.dimmed;
                stem.opacity = root.dimmed;
            }
        }
        NumberAnimation { target: root; property: "slashProgress"; to: 0; duration: 260; easing.type: Easing.InCubic }
        ParallelAnimation {
            NumberAnimation { target: upperWing; property: "opacity"; to: 1; duration: 300 }
            NumberAnimation { target: lowerWing; property: "opacity"; to: 1; duration: 300 }
            NumberAnimation { target: stem; property: "opacity"; to: 1; duration: 300 }
            SequentialAnimation {
                NumberAnimation { target: upperWing; property: "rotation"; to: -4; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: upperWing; property: "rotation"; to: 0; duration: 380; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                NumberAnimation { target: lowerWing; property: "rotation"; to: 4; duration: 150; easing.type: Easing.OutCubic }
                NumberAnimation { target: lowerWing; property: "rotation"; to: 0; duration: 380; easing.type: Easing.OutBack }
            }
        }
        ScriptAction { script: root.applyRest() }
    }
}
