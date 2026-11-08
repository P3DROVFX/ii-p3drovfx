import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets

// Goal banner for the bar sports widget. A panel slides in from the bar's
// screen edge over the widget, a "GOOAALL" marquee runs through it, then the
// scoring crest, score and scorer take over before the panel slides back out.
// The host keeps this in a Loader that is only active while a goal plays.
Item {
    id: root
    clip: true

    property var goal: null
    property bool vertical: false
    // Bottom (horizontal) or right (vertical) bar: enter from the far edge.
    property bool fromFarEdge: false

    signal finished()

    readonly property color colPanel: Appearance.colors.colPrimary
    readonly property color colOnPanel: Appearance.colors.colOnPrimary
    readonly property color colAccent: Appearance.colors.colTertiary
    readonly property color colCrest: Appearance.colors.colPrimaryContainer

    readonly property real inset: 4
    readonly property real thickness: (vertical ? width : height) - inset * 2
    readonly property real length: (vertical ? height : width) - inset * 2
    readonly property real edgeStart: (fromFarEdge ? 1 : -1) * (thickness + inset * 2)

    readonly property string scorerText: {
        const name = String(goal?.scorer ?? "");
        if (name === "")
            return String(goal?.teamName ?? "");
        return goal?.ownGoal ? `${name} (OG)` : (goal?.penalty ? `${name} (P)` : name);
    }
    readonly property string detailText: {
        // Without a scorer the first line is already the team.
        if (String(goal?.scorer ?? "") === "")
            return String(goal?.league ?? "");
        const minute = String(goal?.minute ?? "");
        const team = String(goal?.teamName ?? "");
        return minute !== "" ? `${minute} · ${team}` : team;
    }
    readonly property string scoreText: `${goal?.homeScore ?? "0"} - ${goal?.awayScore ?? "0"}`

    // Animated state. `phase`: 0 entering, 1 marquee, 2 info, 3 leaving.
    property int phase: 0
    property real edgeOffset: edgeStart
    property real marqueeX: 0
    property real marqueeOpacity: 1
    property real sweep: 0
    property real shout: 1
    property real infoProgress: 0

    function play() {
        timeline.stop();
        shoutLoop.stop();
        timeline.start();
    }

    onGoalChanged: if (goal) play()
    Component.onCompleted: if (goal) play()

    SequentialAnimation {
        id: timeline
        ScriptAction {
            script: {
                root.phase = 0;
                root.edgeOffset = root.edgeStart;
                root.marqueeX = marqueeBox.width * 0.55;
                root.marqueeOpacity = 1;
                root.sweep = 0;
                root.infoProgress = 0;
            }
        }
        NumberAnimation { target: root; property: "edgeOffset"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        ScriptAction { script: { root.phase = 1; shoutLoop.start(); } }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "marqueeX"
                to: Math.min(0, marqueeBox.width - marqueeRow.implicitWidth)
                duration: 2900
                easing.type: Easing.Linear
            }
            SequentialAnimation {
                loops: 3
                NumberAnimation { target: root; property: "sweep"; from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
            }
        }
        ScriptAction { script: { root.phase = 2; shoutLoop.stop(); root.shout = 1; } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "marqueeOpacity"; to: 0; duration: 220; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "infoProgress"; to: 1; duration: 520; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 3800 }
        ScriptAction { script: root.phase = 3 }
        NumberAnimation { target: root; property: "edgeOffset"; to: root.edgeStart; duration: 320; easing.type: Easing.InCubic }
        ScriptAction { script: root.finished() }
    }

    // The words "shout": they pump in alternation while the marquee runs.
    SequentialAnimation {
        id: shoutLoop
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "shout"; to: 1.14; duration: 170; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shout"; to: 1; duration: 170; easing.type: Easing.InQuad }
    }

    // The mask is sampled in the panel's own space, so it only needs its size.
    Rectangle {
        id: panelMask
        width: panel.width
        height: panel.height
        radius: Math.min(width, height) / 2
        visible: false
        layer.enabled: true
    }

    Item {
        id: panel
        x: root.inset
        y: root.inset
        width: root.vertical ? root.thickness : root.length
        height: root.vertical ? root.length : root.thickness
        transform: Translate {
            x: root.vertical ? root.edgeOffset : 0
            y: root.vertical ? 0 : root.edgeOffset
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: panelMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        Rectangle {
            anchors.fill: parent
            color: root.colPanel
        }

        // Everything below is laid out along the long axis; in a vertical bar
        // the box is turned so text runs bottom to top.
        Item {
            id: axisBox
            anchors.centerIn: parent
            width: root.length
            height: root.thickness
            rotation: root.vertical ? -90 : 0

            // Light streaks sweeping across, behind the words.
            Repeater {
                model: 3
                delegate: Rectangle {
                    required property int index
                    width: root.thickness * (index === 1 ? 0.9 : 0.45)
                    height: root.thickness * 3
                    anchors.verticalCenter: parent.verticalCenter
                    rotation: 24
                    x: -width * 2 + (axisBox.width + width * 4) * root.sweep + index * root.thickness * 0.9
                    color: index === 1 ? root.colAccent : root.colOnPanel
                    opacity: root.phase === 1 ? (index === 1 ? 0.85 : 0.22) : 0
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                }
            }

            Item {
                id: marqueeBox
                anchors.fill: parent
                anchors.leftMargin: root.thickness * 0.3
                anchors.rightMargin: root.thickness * 0.3
                opacity: root.marqueeOpacity
                visible: opacity > 0

                Row {
                    id: marqueeRow
                    x: root.marqueeX
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.thickness * 0.45

                    Repeater {
                        model: 5
                        delegate: StyledText {
                            required property int index
                            text: "GOOAALL!"
                            // Every other word is a ghost echo of the shout.
                            color: root.colOnPanel
                            opacity: index % 2 === 0 ? 1 : 0.4
                            font.pixelSize: Math.round(root.thickness * 0.56)
                            font.variableAxes: ({ "wght": 1000, "wdth": 125, "slnt": -10, "ROND": 0 })
                            scale: index % 2 === 0 ? root.shout : 2.14 - root.shout
                        }
                    }
                }
            }
        }

        // Crest, score and scorer.
        Item {
            id: info
            anchors.fill: parent
            opacity: root.infoProgress
            visible: opacity > 0
            transform: Translate {
                x: root.vertical ? 0 : (1 - root.infoProgress) * 28
                y: root.vertical ? (1 - root.infoProgress) * 28 : 0
            }

            readonly property real crestSize: root.thickness - 6

            Rectangle {
                id: crest
                width: info.crestSize
                height: info.crestSize
                radius: width / 2
                color: root.colCrest
                x: root.vertical ? (parent.width - width) / 2 : 3
                y: root.vertical ? 3 : (parent.height - height) / 2
                scale: 0.4 + 0.6 * root.infoProgress

                StyledImage {
                    anchors.centerIn: parent
                    width: parent.width * 0.72
                    height: width
                    source: root.goal?.teamLogo ?? ""
                    fillMode: Image.PreserveAspectFit
                    cache: false
                }
            }

            StyledText {
                id: score
                text: root.scoreText
                color: root.colOnPanel
                font.pixelSize: root.vertical ? Math.round(root.thickness * 0.34) : Math.round(root.thickness * 0.5)
                font.variableAxes: ({ "wght": 900, "wdth": root.vertical ? 75 : 100, "ROND": 0 })
                x: root.vertical ? (parent.width - width) / 2 : crest.x + crest.width + 8
                y: root.vertical ? crest.y + crest.height + 6 : (parent.height - height) / 2
            }

            // Scorer and minute; turned along the bar when it is vertical.
            Item {
                id: scorerBox
                readonly property real start: root.vertical ? score.y + score.height + 8 : score.x + score.width + 10
                readonly property real span: Math.max(0, (root.vertical ? parent.height : parent.width) - start - root.thickness * 0.35)
                width: span
                height: root.thickness
                rotation: root.vertical ? -90 : 0
                x: root.vertical ? (parent.width - width) / 2 : start
                y: root.vertical ? start + span / 2 - height / 2 : 0

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: root.vertical ? 0 : -1

                    StyledText {
                        width: parent.width
                        text: root.scorerText
                        elide: Text.ElideRight
                        horizontalAlignment: root.vertical ? Text.AlignRight : Text.AlignLeft
                        color: root.colOnPanel
                        font.pixelSize: Math.round(root.thickness * 0.34)
                        font.variableAxes: ({ "wght": 800, "wdth": 100, "ROND": 0 })
                    }

                    StyledText {
                        width: parent.width
                        text: root.detailText
                        elide: Text.ElideRight
                        horizontalAlignment: root.vertical ? Text.AlignRight : Text.AlignLeft
                        color: root.colOnPanel
                        opacity: 0.8
                        font.pixelSize: Math.round(root.thickness * 0.26)
                        font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 0 })
                    }
                }
            }
        }
    }
}
