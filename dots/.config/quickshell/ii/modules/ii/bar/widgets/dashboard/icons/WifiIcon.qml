pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Wi-Fi, drawn as four separate parts: the dot and three arcs.
 *
 * Every cue moves the arcs along their own radius — outward is "signal leaving
 * the antenna", inward is "signal arriving". The stagger between them is what
 * makes the movement read as one gesture instead of three.
 */
AnimatedIcon {
    id: root

    cueChannel: "wifi"
    stroke: 2.0

    /** How many arcs are lit at rest: 0 (none) to 3 (full strength). */
    property int bars: 3
    readonly property real dimmed: 0.22
    /** Never fully gone: an unlit arc stays as a ghost of the full fan. */
    readonly property real ghost: 0.14
    property bool busy: false

    component SignalArc: Shape {
        id: arc
        property real rest: 8
        property real radius: rest
        property real lift: 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: 12
                centerY: 19.8 + arc.lift
                radiusX: arc.radius
                radiusY: arc.radius
                startAngle: -136
                sweepAngle: 92
            }
        }
    }

    function restOpacity(index: int): real {
        if (root.bars >= index)
            return 1.0;
        return root.bars <= 0 ? root.ghost : root.dimmed;
    }

    function applyRest(): void {
        arc1.radius = arc1.rest;
        arc2.radius = arc2.rest;
        arc3.radius = arc3.rest;
        arc1.lift = 0;
        arc2.lift = 0;
        arc3.lift = 0;
        dot.lift = 0;
        arc1.opacity = root.restOpacity(1);
        arc2.opacity = root.restOpacity(2);
        arc3.opacity = root.restOpacity(3);
        dot.opacity = 1.0;
    }

    function stopAll(): void {
        searchAnim.stop();
        connectAnim.stop();
        disconnectAnim.stop();
        disableAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.applyRest();
        root.busy = true;
        switch (cue) {
        case "searching":
            searchAnim.start();
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
        default:
            root.busy = false;
            break;
        }
    }

    onBarsChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    Shape {
        id: dot
        property real lift: 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathAngleArc {
                centerX: 12
                centerY: 19.8 + dot.lift
                radiusX: 1.9
                radiusY: 1.9
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    SignalArc {
        id: arc1
        rest: 4.9
    }
    SignalArc {
        id: arc2
        rest: 9.45
    }
    SignalArc {
        id: arc3
        rest: 14.0
    }

    // ── Searching: repeat the connected landing under the opacity wave ───
    ParallelAnimation {
        id: searchAnim

        SequentialAnimation {
            loops: Animation.Infinite
            ParallelAnimation {
                NumberAnimation { target: arc1; property: "radius"; from: arc1.rest - 2.8; to: arc1.rest; duration: 400; easing.type: Easing.OutBack }
                SequentialAnimation {
                    NumberAnimation { target: arc1; property: "lift"; from: 0; to: -0.55; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc1; property: "lift"; to: 0; duration: 300; easing.type: Easing.OutBack }
                }
                NumberAnimation { target: arc1; property: "opacity"; from: root.dimmed; to: 1.0; duration: 240 }
            }
            NumberAnimation { target: arc1; property: "opacity"; to: root.dimmed; duration: 300 }
            PauseAnimation { duration: 520 }
        }

        SequentialAnimation {
            loops: Animation.Infinite
            PauseAnimation { duration: 170 }
            ParallelAnimation {
                NumberAnimation { target: arc2; property: "radius"; from: arc2.rest - 3.0; to: arc2.rest; duration: 400; easing.type: Easing.OutBack }
                SequentialAnimation {
                    NumberAnimation { target: arc2; property: "lift"; from: 0; to: -0.8; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc2; property: "lift"; to: 0; duration: 300; easing.type: Easing.OutBack }
                }
                NumberAnimation { target: arc2; property: "opacity"; from: root.dimmed; to: 1.0; duration: 240 }
            }
            NumberAnimation { target: arc2; property: "opacity"; to: root.dimmed; duration: 300 }
            PauseAnimation { duration: 350 }
        }

        SequentialAnimation {
            loops: Animation.Infinite
            PauseAnimation { duration: 340 }
            ParallelAnimation {
                NumberAnimation { target: arc3; property: "radius"; from: arc3.rest - 3.2; to: arc3.rest; duration: 400; easing.type: Easing.OutBack }
                SequentialAnimation {
                    NumberAnimation { target: arc3; property: "lift"; from: 0; to: -1.05; duration: 160; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc3; property: "lift"; to: 0; duration: 300; easing.type: Easing.OutBack }
                }
                NumberAnimation { target: arc3; property: "opacity"; from: root.dimmed; to: 1.0; duration: 240 }
            }
            NumberAnimation { target: arc3; property: "opacity"; to: root.dimmed; duration: 300 }
            PauseAnimation { duration: 180 }
        }

        SequentialAnimation {
            loops: Animation.Infinite
            NumberAnimation { target: dot; property: "lift"; to: 1.2; duration: 110; easing.type: Easing.OutCubic }
            NumberAnimation { target: dot; property: "lift"; to: 0; duration: 300; easing.type: Easing.OutBack }
            PauseAnimation { duration: 870 }
        }
    }

    // ── Connected: the arcs arrive and land, inner first ────────────────────
    SequentialAnimation {
        id: connectAnim
        onStopped: root.busy = false

        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: dot; property: "lift"; to: 1.2; duration: 110; easing.type: Easing.OutCubic }
                NumberAnimation { target: dot; property: "lift"; to: 0; duration: 300; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                PauseAnimation { duration: 60 }
                ParallelAnimation {
                    NumberAnimation { target: arc1; property: "radius"; from: arc1.rest - 2.8; to: arc1.rest; duration: 400; easing.type: Easing.OutBack }
                    NumberAnimation { target: arc1; property: "opacity"; to: 1.0; duration: 200 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 135 }
                ParallelAnimation {
                    NumberAnimation { target: arc2; property: "radius"; from: arc2.rest - 3.0; to: arc2.rest; duration: 400; easing.type: Easing.OutBack }
                    NumberAnimation { target: arc2; property: "opacity"; to: root.restOpacity(2); duration: 200 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 210 }
                ParallelAnimation {
                    NumberAnimation { target: arc3; property: "radius"; from: arc3.rest - 3.2; to: arc3.rest; duration: 400; easing.type: Easing.OutBack }
                    NumberAnimation { target: arc3; property: "opacity"; to: root.restOpacity(3); duration: 200 }
                }
            }
        }
    }

    // ── Disconnected: the arcs let go and drift off, outer first ────────────
    SequentialAnimation {
        id: disconnectAnim
        onStopped: root.busy = false

        ParallelAnimation {
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { target: arc3; property: "radius"; to: arc3.rest + 3.4; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc3; property: "lift"; to: -1.6; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc3; property: "opacity"; to: root.ghost; duration: 380 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 80 }
                ParallelAnimation {
                    NumberAnimation { target: arc2; property: "radius"; to: arc2.rest + 3.0; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc2; property: "lift"; to: -1.2; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc2; property: "opacity"; to: root.ghost; duration: 380 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 160 }
                ParallelAnimation {
                    NumberAnimation { target: arc1; property: "radius"; to: arc1.rest + 2.4; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc1; property: "opacity"; to: root.dimmed; duration: 380 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                NumberAnimation { target: dot; property: "lift"; to: 1.4; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: dot; property: "lift"; to: 0; duration: 320; easing.type: Easing.OutBack }
            }
        }
        // Settle: the arcs ease back to where they live, still ghosted. Without
        // this second phase the first one ended in a teleport.
        ParallelAnimation {
            NumberAnimation { target: arc3; property: "radius"; to: arc3.rest; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: arc3; property: "lift"; to: 0; duration: 420; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 60 }
                ParallelAnimation {
                    NumberAnimation { target: arc2; property: "radius"; to: arc2.rest; duration: 420; easing.type: Easing.OutCubic }
                    NumberAnimation { target: arc2; property: "lift"; to: 0; duration: 420; easing.type: Easing.OutCubic }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 120 }
                NumberAnimation { target: arc1; property: "radius"; to: arc1.rest; duration: 420; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── Turned off: the arcs collapse back into the dot ─────────────────────
    SequentialAnimation {
        id: disableAnim
        onStopped: root.busy = false

        ParallelAnimation {
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { target: arc3; property: "radius"; to: arc3.rest; duration: 340; easing.type: Easing.InCubic }
                    NumberAnimation { target: arc3; property: "opacity"; to: root.ghost; duration: 300 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 70 }
                ParallelAnimation {
                    NumberAnimation { target: arc2; property: "radius"; to: arc2.rest; duration: 340; easing.type: Easing.InCubic }
                    NumberAnimation { target: arc2; property: "opacity"; to: root.ghost; duration: 300 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 140 }
                ParallelAnimation {
                    NumberAnimation { target: arc1; property: "radius"; to: arc1.rest; duration: 340; easing.type: Easing.InCubic }
                    NumberAnimation { target: arc1; property: "opacity"; to: root.ghost; duration: 300 }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                NumberAnimation { target: dot; property: "lift"; to: -0.9; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: dot; property: "lift"; to: 0; duration: 260; easing.type: Easing.OutBack }
            }
        }
    }
}
