pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

/**
 * Ethernet, drawn as the Material `lan` glyph in five parts: the host box on
 * top, the stem leaving it, the bus with its two legs, and the two client boxes.
 *
 * The link is one continuous trace: the stem grows out of the host and the bus
 * rides on its tip, spreading sideways and then down into the clients. Plugging
 * in draws that trace and the clients take the impact as it lands; unplugging
 * pulls it back into the host while the clients drift loose. The link is never
 * faded — it is drawn or withdrawn by its own endpoints.
 */
AnimatedIcon {
    id: root

    cueChannel: "ethernet"
    stroke: 2.0

    /** The cable carries a connection. False rests in the withdrawn pose. */
    property bool linked: true
    property bool busy: false
    readonly property real dimmed: 0.4

    // 0 = the stem is still inside the host, 1 = it reaches the bus row.
    property real stemProgress: 1
    // 0 = no bus, 0.55 = bus fully across, 1 = legs reach the clients.
    property real spread: 1
    property real hostLift: 0
    property real clientDrop: 0
    property real clientDrift: 0
    property real clientsOpacity: 1

    readonly property real busY: 8 + 4 * root.stemProgress
    readonly property real busReach: Math.min(root.spread / 0.55, 1) * 5
    readonly property real legLength: Math.max((root.spread - 0.55) / 0.45, 0) * Math.max(16 + root.clientDrop - root.busY, 0)

    function linkedPose(): void {
        root.stemProgress = 1;
        root.spread = 1;
        root.clientsOpacity = 1;
    }

    function withdrawnPose(): void {
        root.stemProgress = 0;
        root.spread = 0;
        root.clientsOpacity = root.dimmed;
    }

    function applyRest(): void {
        root.hostLift = 0;
        root.clientDrop = 0;
        root.clientDrift = 0;
        if (root.linked)
            root.linkedPose();
        else
            root.withdrawnPose();
    }

    function stopAll(): void {
        connectingAnim.stop();
        connectAnim.stop();
        disconnectAnim.stop();
    }

    function play(cue: string): void {
        // A cue that interrupts another continues from the pose reached;
        // otherwise it rebuilds its own first frame, because the rest bindings
        // may have applied the end state while the icon was hidden or swapped in.
        const continuing = root.busy;
        root.stopAll();
        root.busy = true;
        switch (cue) {
        case "connecting":
            root.hostLift = 0;
            root.clientDrop = 0;
            root.clientDrift = 0;
            root.withdrawnPose();
            connectingAnim.start();
            break;
        case "connected":
            if (!continuing)
                root.withdrawnPose();
            connectAnim.start();
            break;
        case "disconnected":
            if (!continuing)
                root.linkedPose();
            disconnectAnim.start();
            break;
        case "settle":
            root.busy = false;
            root.applyRest();
            break;
        default:
            root.busy = false;
            root.applyRest();
            break;
        }
    }

    onLinkedChanged: {
        if (!root.busy)
            root.applyRest();
    }

    Component.onCompleted: root.applyRest()

    // ── Parts ────────────────────────────────────────────────────────────────
    component Box: Shape {
        id: box
        property real boxX: 0
        property real boxY: 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            PathRectangle {
                x: box.boxX
                y: box.boxY
                width: 6
                height: 5
                radius: 1
            }
        }
    }

    Box {
        id: host
        boxX: 9
        boxY: 3 + root.hostLift
    }

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
            startY: 8 + root.hostLift
            PathLine { x: 12; y: root.busY }
        }
    }

    // Left leg → bus → right leg as one stroke, so the corners join cleanly.
    Shape {
        id: bus
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.stroke
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            startX: 12 - root.busReach
            startY: root.busY + root.legLength
            PathLine { x: 12 - root.busReach; y: root.busY }
            PathLine { x: 12 + root.busReach; y: root.busY }
            PathLine { x: 12 + root.busReach; y: root.busY + root.legLength }
        }
    }

    Box {
        id: leftClient
        boxX: 4 - root.clientDrift
        boxY: 16 + root.clientDrop
        opacity: root.clientsOpacity
    }

    Box {
        id: rightClient
        boxX: 14 + root.clientDrift
        boxY: 16 + root.clientDrop
        opacity: root.clientsOpacity
    }

    // ── Connecting: the link reaches for the clients and withdraws, again ───
    SequentialAnimation {
        id: connectingAnim
        loops: Animation.Infinite

        NumberAnimation { target: root; property: "stemProgress"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "spread"; from: 0; to: 1; duration: 380; easing.type: Easing.InOutCubic }
        ParallelAnimation {
            NumberAnimation { target: root; property: "clientDrop"; from: 0; to: 0.5; duration: 90; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "clientsOpacity"; to: 0.75; duration: 160 }
        }
        NumberAnimation { target: root; property: "clientDrop"; to: 0; duration: 240; easing.type: Easing.OutBack }
        PauseAnimation { duration: 140 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "spread"; to: 0; duration: 320; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "clientsOpacity"; to: root.dimmed; duration: 320 }
        }
        NumberAnimation { target: root; property: "stemProgress"; to: 0; duration: 150; easing.type: Easing.InCubic }
        PauseAnimation { duration: 280 }
    }

    // ── Connected: the trace leaves the host and lands on the clients ───────
    SequentialAnimation {
        id: connectAnim
        onStopped: root.busy = false

        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: root; property: "hostLift"; to: 0.7; duration: 110; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "hostLift"; to: 0; duration: 300; easing.type: Easing.OutBack }
            }
            SequentialAnimation {
                PauseAnimation { duration: 90 }
                NumberAnimation { target: root; property: "stemProgress"; to: 1; duration: 170; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "spread"; to: 1; duration: 330; easing.type: Easing.InOutCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 540 }
                ParallelAnimation {
                    NumberAnimation { target: root; property: "clientDrop"; to: 0.8; duration: 100; easing.type: Easing.OutCubic }
                    NumberAnimation { target: root; property: "clientsOpacity"; to: 1; duration: 180 }
                }
                NumberAnimation { target: root; property: "clientDrop"; to: 0; duration: 320; easing.type: Easing.OutBack }
            }
        }
    }

    // ── Disconnected: the trace withdraws into the host, clients drift loose ─
    SequentialAnimation {
        id: disconnectAnim
        onStopped: root.busy = false

        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation { target: root; property: "spread"; to: 0; duration: 300; easing.type: Easing.InCubic }
                NumberAnimation { target: root; property: "stemProgress"; to: 0; duration: 160; easing.type: Easing.InCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 60 }
                ParallelAnimation {
                    NumberAnimation { target: root; property: "clientDrift"; to: 0.9; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: root; property: "clientDrop"; to: 0.7; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: root; property: "clientsOpacity"; to: root.dimmed; duration: 300 }
                }
                // Ease back home, still dimmed: without it the drift would end
                // in a jump when the rest pose is applied.
                ParallelAnimation {
                    NumberAnimation { target: root; property: "clientDrift"; to: 0; duration: 340; easing.type: Easing.OutCubic }
                    NumberAnimation { target: root; property: "clientDrop"; to: 0; duration: 340; easing.type: Easing.OutCubic }
                }
            }
            SequentialAnimation {
                PauseAnimation { duration: 300 }
                NumberAnimation { target: root; property: "hostLift"; to: -0.7; duration: 140; easing.type: Easing.OutCubic }
                NumberAnimation { target: root; property: "hostLift"; to: 0; duration: 260; easing.type: Easing.OutBack }
            }
        }
    }
}
