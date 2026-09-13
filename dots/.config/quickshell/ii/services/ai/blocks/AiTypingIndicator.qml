pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The model is writing.
 *
 * Three shapes riding a wave from left to right — the same gesture every chat
 * app uses for "someone is typing" — with a line beside them that says what is
 * being waited for. It replaces a spinner and a fixed caption: a spinner says
 * "busy", and this says "an answer is coming", which is the thing the reader
 * actually wants to know.
 *
 * The wave runs only while `active`. Nothing here loops in the background.
 */
Item {
    id: root

    /** Set while an answer is on its way. Everything stops when it is false. */
    property bool active: true
    /** Set while the model is still reasoning, which changes what is said. */
    property bool reasoning: false

    /**
     * Three different shapes rather than three dots: at this size the wave is
     * what carries the meaning, and the variety is what makes it look like
     * this shell instead of every other chat app.
     */
    readonly property var dotShapes: [
        MaterialShape.Shape.Circle,
        MaterialShape.Shape.Clover4Leaf,
        MaterialShape.Shape.Sunny
    ]

    readonly property real dotSize: Math.round(Appearance.font.pixelSize.small * 0.8)
    readonly property real dotSpacing: Math.round(root.dotSize * 0.75)
    /** How far a dot rises at the top of the wave. */
    readonly property real dotLift: Math.round(root.dotSize * 0.85)
    /** One dot's rise and fall; the three are offset by a third of it. */
    readonly property int waveDuration: Math.round(Appearance.animation.elementMoveSlow.duration * 1.6)

    readonly property var writingLines: [
        Translation.tr("Generating your answer"),
        Translation.tr("Working on it"),
        Translation.tr("Putting it together"),
        Translation.tr("Writing that up"),
        Translation.tr("Getting to it")
    ]
    readonly property var reasoningLines: [
        Translation.tr("Thinking it through"),
        Translation.tr("Working out the answer"),
        Translation.tr("Reasoning about it")
    ]

    property int lineIndex: 0
    readonly property var lines: root.reasoning ? root.reasoningLines : root.writingLines
    readonly property string line: root.lines[root.lineIndex % root.lines.length] ?? ""

    implicitWidth: indicatorRow.implicitWidth
    implicitHeight: Math.max(indicatorRow.implicitHeight, root.dotSize + root.dotLift)

    // A line that never changes stops being read after the first second. This
    // one moves on while the wait lasts, and starts somewhere different each
    // time so a slow answer does not always open with the same sentence.
    Component.onCompleted: root.lineIndex = Math.floor(Math.random() * root.writingLines.length)

    Timer {
        running: root.active
        repeat: true
        interval: Math.round(Appearance.animation.elementMoveSlow.duration * 12)
        onTriggered: root.lineIndex = (root.lineIndex + 1) % Math.max(1, root.lines.length)
    }

    RowLayout {
        id: indicatorRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Appearance.rounding.unsharpenmore

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.dotSize + root.dotLift
            spacing: root.dotSpacing

            Repeater {
                model: 3

                delegate: Item {
                    id: dotSlot
                    required property int index

                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.dotSize
                    implicitHeight: root.dotSize + root.dotLift

                    MaterialShape {
                        id: dot
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        implicitSize: root.dotSize
                        shape: root.dotShapes[dotSlot.index % root.dotShapes.length]
                        color: Appearance.colors.colSubtext

                        transform: Translate {
                            id: dotLift
                            y: 0
                        }

                        // The stagger is what makes three dots read as one
                        // wave instead of three things blinking.
                        SequentialAnimation {
                            running: root.active
                            loops: Animation.Infinite

                            PauseAnimation {
                                duration: Math.round(root.waveDuration / 3) * dotSlot.index
                            }

                            NumberAnimation {
                                target: dotLift
                                property: "y"
                                from: 0
                                to: -root.dotLift
                                duration: Math.round(root.waveDuration / 2)
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                            }

                            NumberAnimation {
                                target: dotLift
                                property: "y"
                                to: 0
                                duration: Math.round(root.waveDuration / 2)
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                            }

                            // The rest of the cycle belongs to the other two
                            // dots, so the wave travels instead of pulsing.
                            PauseAnimation {
                                duration: Math.round(root.waveDuration / 3) * (2 - dotSlot.index)
                            }

                            onRunningChanged: {
                                if (!running)
                                    dotLift.y = 0;
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: root.line
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            // The swap slides rather than cuts, which is what keeps a changing
            // caption from reading as a glitch.
            animateChange: true
        }
    }
}
