pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Tailscale's own mark: a 3×3 grid of dots, four of them solid and the rest
 * held back. This is the one icon whose animation is primarily colour, because
 * that is what the brand mark itself is made of — a sweep lights the grid up
 * row by row, and each dot leans toward the centre as it takes the colour so
 * the sweep still moves something.
 */
AnimatedIcon {
    id: root

    cueChannel: "tailscale"

    property bool connected: false
    property bool busy: false

    readonly property real dotRadius: 2.55
    readonly property real dimmed: 0.32
    /** Grid indices that are solid in the mark: the middle row, plus the dot
        below its centre. */
    readonly property var solidDots: [3, 4, 5, 7]

    readonly property var columns: [5.5, 12, 18.5]
    readonly property var rows: [5.5, 12, 18.5]

    component Dot: Shape {
        id: dot
        required property int index
        property real lean: 0
        readonly property real homeX: root.columns[dot.index % 3]
        readonly property real homeY: root.rows[Math.floor(dot.index / 3)]
        readonly property bool solid: root.solidDots.indexOf(dot.index) >= 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.dimmed

        // The colour change is the sweep; the lean is what keeps it from being
        // a pure fade. Both live on the dot so the sweep can just poke it.
        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        function nudge(): void {
            nudgeAnim.restart();
        }

        SequentialAnimation {
            id: nudgeAnim
            NumberAnimation { target: dot; property: "lean"; from: 0; to: 0.12; duration: 130; easing.type: Easing.OutCubic }
            NumberAnimation { target: dot; property: "lean"; to: 0; duration: 260; easing.type: Easing.OutBack }
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathAngleArc {
                centerX: dot.homeX + (12 - dot.homeX) * dot.lean
                centerY: dot.homeY + (12 - dot.homeY) * dot.lean
                radiusX: root.dotRadius
                radiusY: root.dotRadius
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    function dotAt(index: int): Item {
        return dotRepeater.itemAt(index);
    }

    function applyRest(): void {
        for (let i = 0; i < 9; i++) {
            const dot = root.dotAt(i);
            if (!dot)
                continue;
            dot.lean = 0;
            dot.opacity = (root.connected && dot.solid) ? 1.0 : root.dimmed;
        }
    }

    function stopAll(): void {
        sweepAnim.stop();
        fadeAnim.stop();
    }

    function play(cue: string): void {
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "connected":
            sweepAnim.start();
            break;
        case "disconnected":
            fadeAnim.start();
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

    Component.onCompleted: Qt.callLater(root.applyRest)

    Repeater {
        id: dotRepeater
        model: 9
        delegate: Dot {
            required property int modelData
            index: modelData
        }
    }

    // ── Connected: the sweep runs the grid, dot by dot ──────────────────────
    SequentialAnimation {
        id: sweepAnim
        onStopped: root.busy = false

        ScriptAction {
            script: {
                for (let i = 0; i < 9; i++) {
                    const dot = root.dotAt(i);
                    if (dot) {
                        dot.opacity = root.dimmed;
                        dot.lean = 0;
                    }
                }
            }
        }
        // Nine short steps rather than nine parallel animations with pauses:
        // the sweep has to be strictly ordered to read as one pass.
        ScriptAction { script: sweepStep.restart() }
        PauseAnimation { duration: 9 * 55 + 260 }
    }

    property int sweepIndex: 0
    Timer {
        id: sweepStep
        interval: 55
        repeat: true
        onTriggered: {
            const dot = root.dotAt(root.sweepIndex);
            if (dot) {
                dot.nudge();
                dot.opacity = dot.solid ? 1.0 : root.dimmed;
            }
            root.sweepIndex += 1;
            if (root.sweepIndex >= 9) {
                root.sweepIndex = 0;
                sweepStep.stop();
            }
        }
    }

    // ── Disconnected: the grid goes quiet from the outside in ───────────────
    SequentialAnimation {
        id: fadeAnim
        onStopped: root.busy = false

        ScriptAction { script: fadeStep.restart() }
        PauseAnimation { duration: 9 * 45 + 200 }
        ScriptAction { script: root.applyRest() }
    }

    property int fadeIndex: 0
    Timer {
        id: fadeStep
        interval: 45
        repeat: true
        onTriggered: {
            const dot = root.dotAt(8 - root.fadeIndex);
            if (dot) {
                dot.nudge();
                dot.opacity = root.dimmed;
            }
            root.fadeIndex += 1;
            if (root.fadeIndex >= 9) {
                root.fadeIndex = 0;
                fadeStep.stop();
            }
        }
    }
}
