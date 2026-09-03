import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property bool nextButtonHovered: false

    /**
     * The greeting in the reader's own language first, then a few others as
     * plain literals. "Bonjour" is not an English string awaiting a
     * translation — running these through `tr()` asked every catalogue to
     * translate words that are already the point.
     */
    readonly property var greetings: {
        const own = Translation.tr("Hi there");
        const others = ["Olá", "Bonjour", "Hola", "こんにちは"];
        return [own, ...others.filter(greeting => greeting !== own)];
    }
    property int greetingIndex: 0

    // Ambient movement is intentionally translational/rotational only: it
    // keeps the outline shapes alive without turning them into a pulse effect.
    readonly property int driftDuration: Appearance.animation.elementMoveSlow.duration * 20
    readonly property real leftDriftDistance: Appearance.rounding.large * 2
    readonly property real rightDriftDistance: Appearance.rounding.normal * 2

    // Text that swaps itself every couple of seconds is motion, the same as
    // the shapes behind it, and it answers to the same preference.
    Timer {
        interval: 2200
        repeat: true
        running: root.visible && WelcomeMotion.motionEnabled
        onTriggered: root.greetingIndex = (root.greetingIndex + 1) % root.greetings.length
    }

    onGreetingsChanged: root.greetingIndex = 0

    // The first screen deliberately uses only outline shapes. It echoes the
    // Pixel welcome screen without adding a second filled card to the shell.
    MaterialShape {
        id: leftShape
        // Keep the decorative layer behind the page content itself.
        z: -1
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: -width * 0.32
        anchors.topMargin: -width * 0.20
        width: parent.width * 0.62
        height: width
        shape: MaterialShape.Shape.Cookie12Sided
        color: "transparent"
        // ShapeCanvas scales its normalized path before stroking. Convert a
        // small theme-sized line into the normalized width it expects.
        borderWidth: Math.max(Appearance.rounding.verysmall, Appearance.font.pixelSize.smaller / 4) / Math.max(width, 1)
        borderColor: Appearance.colors.colLayer1
        opacity: 0.78
        rotation: -12

        transform: Translate {
            id: leftDrift
        }

        SequentialAnimation {
            running: root.visible && WelcomeMotion.motionEnabled
            loops: Animation.Infinite

            ParallelAnimation {
                NumberAnimation {
                    target: leftDrift
                    property: "x"
                    to: root.leftDriftDistance
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: leftDrift
                    property: "y"
                    to: -root.leftDriftDistance / 2
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: leftShape
                    property: "rotation"
                    to: -4
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
            }

            ParallelAnimation {
                NumberAnimation {
                    target: leftDrift
                    property: "x"
                    to: -root.leftDriftDistance
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: leftDrift
                    property: "y"
                    to: root.leftDriftDistance
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: leftShape
                    property: "rotation"
                    to: -18
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
            }

            ParallelAnimation {
                NumberAnimation {
                    target: leftDrift
                    property: "x"
                    to: 0
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: leftDrift
                    property: "y"
                    to: 0
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: leftShape
                    property: "rotation"
                    to: -12
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    MaterialShape {
        id: rightShape
        // Keep the decorative layer behind the page content itself.
        z: -1
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -width * 0.32
        anchors.bottomMargin: -width * 0.28
        width: parent.width * 0.68
        height: width
        shape: MaterialShape.Shape.Circle
        color: "transparent"
        borderWidth: Math.max(Appearance.rounding.verysmall, Appearance.font.pixelSize.smaller / 4) / Math.max(width, 1)
        borderColor: Appearance.colors.colLayer1
        opacity: 0.65

        transform: Translate {
            id: rightDrift
        }

        SequentialAnimation {
            running: root.visible && WelcomeMotion.motionEnabled
            loops: Animation.Infinite

            ParallelAnimation {
                NumberAnimation {
                    target: rightDrift
                    property: "x"
                    to: -root.rightDriftDistance
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: rightDrift
                    property: "y"
                    to: root.rightDriftDistance / 2
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: rightShape
                    property: "rotation"
                    to: 8
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
            }

            ParallelAnimation {
                NumberAnimation {
                    target: rightDrift
                    property: "x"
                    to: root.rightDriftDistance
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: rightDrift
                    property: "y"
                    to: -root.rightDriftDistance
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: rightShape
                    property: "rotation"
                    to: -8
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
            }

            ParallelAnimation {
                NumberAnimation {
                    target: rightDrift
                    property: "x"
                    to: 0
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: rightDrift
                    property: "y"
                    to: 0
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: rightShape
                    property: "rotation"
                    to: 0
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.large
        anchors.rightMargin: Appearance.rounding.large
        anchors.topMargin: Appearance.rounding.small
        anchors.bottomMargin: Appearance.rounding.small
        spacing: Appearance.rounding.small

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            text: root.greetings[root.greetingIndex]
            color: Appearance.colors.colOnLayer0
            font.family: Appearance.font.family.title
            font.variableAxes: Appearance.font.variableAxes.title
            font.pixelSize: Appearance.font.pixelSize.hugeass * 2
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignHCenter
            animateChange: true
            animationDistanceY: Appearance.rounding.small
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("A few quick choices, then your desktop is ready.")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.large
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: true }
    }
}
