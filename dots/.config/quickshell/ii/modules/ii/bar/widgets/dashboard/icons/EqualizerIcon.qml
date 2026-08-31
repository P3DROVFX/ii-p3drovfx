pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * EasyEffects, following Material's `graphic_eq`: five independently moving
 * bars.
 *
 * Turning it on sends a short vertical ripple through the row while the bars
 * grow from the centre outward; turning it off makes the centres cross in the
 * opposite rhythm as the bars collapse. Both endpoints and centres move —
 * there is no fade standing in for it.
 */
AnimatedIcon {
    id: root

    cueChannel: "easyeffects"
    stroke: 2.2

    property bool active: false
    property bool busy: false

    readonly property real dimmed: 0.35
    readonly property var columns: [3.7, 7.85, 12, 16.15, 20.3]
    readonly property var restHalf: [2.5, 5.1, 8.0, 5.1, 2.5]
    readonly property real quiet: 1.1

    component Bar: Shape {
        id: bar
        required property int index
        property real half: 1.1
        property real offset: 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            startX: root.columns[bar.index]
            startY: 12 + bar.offset - bar.half
            PathLine {
                x: root.columns[bar.index]
                y: 12 + bar.offset + bar.half
            }
        }
    }

    function barAt(index: int): Item {
        switch (index) {
        case 0: return bar0;
        case 1: return bar1;
        case 2: return bar2;
        case 3: return bar3;
        case 4: return bar4;
        default: return null;
        }
    }

    function applyRest(): void {
        for (let i = 0; i < 5; i++) {
            const bar = root.barAt(i);
            if (!bar)
                continue;
            bar.half = root.active ? root.restHalf[i] : root.quiet;
            bar.offset = 0;
            bar.opacity = root.active ? 1 : root.dimmed;
        }
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

    // Stable ids are intentional. A NumberAnimation target evaluated through
    // Repeater.itemAt() sees null while the delegates are being constructed
    // and never gains a reactive dependency that could update it later.
    Bar { id: bar0; index: 0 }
    Bar { id: bar1; index: 1 }
    Bar { id: bar2; index: 2 }
    Bar { id: bar3; index: 3 }
    Bar { id: bar4; index: 4 }

    // ── On: the bars rise, middle first ─────────────────────────────────────
    //
    // Written out per bar rather than through a Repeater: a Repeater needs an
    // Item parent and cannot live inside an animation group.
    ParallelAnimation {
        id: onAnim
        onStopped: root.busy = false

        SequentialAnimation {
            PauseAnimation { duration: 160 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar0
                    property: "half"
                    from: root.quiet
                    to: root.restHalf[0]
                    duration: 420
                    easing.type: Easing.OutBack
                }
                NumberAnimation {
                    target: bar0
                    property: "opacity"
                    to: 1
                    duration: 220
                }
                SequentialAnimation {
                    NumberAnimation { target: bar0; property: "offset"; to: 2.1; duration: 155; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar0; property: "offset"; to: -0.9; duration: 145; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: bar0; property: "offset"; to: 0; duration: 210; easing.type: Easing.OutBack }
                }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: 80 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar1
                    property: "half"
                    from: root.quiet
                    to: root.restHalf[1]
                    duration: 420
                    easing.type: Easing.OutBack
                }
                NumberAnimation {
                    target: bar1
                    property: "opacity"
                    to: 1
                    duration: 220
                }
                SequentialAnimation {
                    NumberAnimation { target: bar1; property: "offset"; to: -1.8; duration: 150; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar1; property: "offset"; to: 1.1; duration: 150; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: bar1; property: "offset"; to: 0; duration: 205; easing.type: Easing.OutBack }
                }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: 0 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar2
                    property: "half"
                    from: root.quiet
                    to: root.restHalf[2]
                    duration: 420
                    easing.type: Easing.OutBack
                }
                NumberAnimation {
                    target: bar2
                    property: "opacity"
                    to: 1
                    duration: 220
                }
                SequentialAnimation {
                    NumberAnimation { target: bar2; property: "offset"; to: 1.5; duration: 145; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar2; property: "offset"; to: -1.3; duration: 155; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: bar2; property: "offset"; to: 0; duration: 200; easing.type: Easing.OutBack }
                }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: 80 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar3
                    property: "half"
                    from: root.quiet
                    to: root.restHalf[3]
                    duration: 420
                    easing.type: Easing.OutBack
                }
                NumberAnimation {
                    target: bar3
                    property: "opacity"
                    to: 1
                    duration: 220
                }
                SequentialAnimation {
                    NumberAnimation { target: bar3; property: "offset"; to: -1.8; duration: 150; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar3; property: "offset"; to: 1.1; duration: 150; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: bar3; property: "offset"; to: 0; duration: 205; easing.type: Easing.OutBack }
                }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: 160 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar4
                    property: "half"
                    from: root.quiet
                    to: root.restHalf[4]
                    duration: 420
                    easing.type: Easing.OutBack
                }
                NumberAnimation {
                    target: bar4
                    property: "opacity"
                    to: 1
                    duration: 220
                }
                SequentialAnimation {
                    NumberAnimation { target: bar4; property: "offset"; to: 2.1; duration: 155; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar4; property: "offset"; to: -0.9; duration: 145; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: bar4; property: "offset"; to: 0; duration: 210; easing.type: Easing.OutBack }
                }
            }
        }
    }

    // ── Off: they fall, outermost first ─────────────────────────────────────
    ParallelAnimation {
        id: offAnim
        onStopped: root.busy = false

        SequentialAnimation {
            PauseAnimation { duration: 0 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar0
                    property: "half"
                    to: root.quiet
                    duration: 340
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: bar0
                    property: "opacity"
                    to: root.dimmed
                    duration: 300
                }
                SequentialAnimation {
                    NumberAnimation { target: bar0; property: "offset"; to: -1.8; duration: 145; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar0; property: "offset"; to: 0; duration: 255; easing.type: Easing.OutBack }
                }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: 70 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar1
                    property: "half"
                    to: root.quiet
                    duration: 340
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: bar1
                    property: "opacity"
                    to: root.dimmed
                    duration: 300
                }
                SequentialAnimation {
                    NumberAnimation { target: bar1; property: "offset"; to: 1.5; duration: 145; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar1; property: "offset"; to: 0; duration: 255; easing.type: Easing.OutBack }
                }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: 140 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar2
                    property: "half"
                    to: root.quiet
                    duration: 340
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: bar2
                    property: "opacity"
                    to: root.dimmed
                    duration: 300
                }
                SequentialAnimation {
                    NumberAnimation { target: bar2; property: "offset"; to: -1.35; duration: 145; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar2; property: "offset"; to: 0; duration: 255; easing.type: Easing.OutBack }
                }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: 70 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar3
                    property: "half"
                    to: root.quiet
                    duration: 340
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: bar3
                    property: "opacity"
                    to: root.dimmed
                    duration: 300
                }
                SequentialAnimation {
                    NumberAnimation { target: bar3; property: "offset"; to: 1.5; duration: 145; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar3; property: "offset"; to: 0; duration: 255; easing.type: Easing.OutBack }
                }
            }
        }

        SequentialAnimation {
            PauseAnimation { duration: 0 }
            ParallelAnimation {
                NumberAnimation {
                    target: bar4
                    property: "half"
                    to: root.quiet
                    duration: 340
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    target: bar4
                    property: "opacity"
                    to: root.dimmed
                    duration: 300
                }
                SequentialAnimation {
                    NumberAnimation { target: bar4; property: "offset"; to: -1.8; duration: 145; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bar4; property: "offset"; to: 0; duration: 255; easing.type: Easing.OutBack }
                }
            }
        }
    }
}
