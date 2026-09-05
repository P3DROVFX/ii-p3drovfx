pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * One character of a running clock, rolled over like an odometer.
 *
 * The record indicator used to say "this is live" with a dot that breathed.
 * Nothing about a dot changes when a second passes, so that animation had to
 * invent its own rhythm — which is what makes a pulse read as decoration. Here
 * the movement belongs to the only thing that actually changes: the digit moves
 * when it is replaced, and stands perfectly still the rest of the time. A paused
 * recording is therefore motionless, for free.
 *
 * Two glyphs, not one. `StyledText.animateChange` would do this in a single
 * label, but it fades the old text out *before* fading the new one in, so the
 * cell is empty for a moment — at one change per second that reads as a blink,
 * not as a roll. Here the outgoing and incoming digits travel together and the
 * cell always has ink in it.
 */
Item {
    id: root

    property string value: "0"
    property real pixelSize: 14
    property color colText: "white"
    property int weight: 700
    property real letterSpacing: 0
    property string fontFamily: Appearance.font.family.title
    property bool animate: true

    // The separator is not a number and never rolls: it would be movement with
    // nothing behind it.
    readonly property bool isDigit: root.value.length === 1 && root.value >= "0" && root.value <= "9"

    // Every digit is measured as a zero, so one cell width serves all ten and
    // the row cannot re-flow mid-second. `tnum` is what makes that exact.
    implicitWidth: root.isDigit ? zeroMetrics.implicitWidth : incoming.implicitWidth
    implicitHeight: zeroMetrics.implicitHeight

    // Far enough to read as a roll, short enough that the outgoing digit has
    // faded well before it would reach the neighbouring row.
    readonly property real travel: Math.max(3, Math.round(root.pixelSize * 0.5))
    readonly property int rollDuration: Math.round(220 * Appearance.animMultiplier)

    property string previousValue: ""
    Component.onCompleted: root.previousValue = root.value

    onValueChanged: {
        const previous = root.previousValue;
        root.previousValue = root.value;
        if (!root.animate || !root.isDigit || previous === "")
            return;
        outgoing.text = previous;
        roll.restart();
    }

    StyledText {
        id: zeroMetrics
        visible: false
        text: "0"
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.letterSpacing: root.letterSpacing
        font.variableAxes: ({
            "wght": root.weight
        })
        font.features: ({
            "tnum": 1
        })
    }

    // The digit on its way out. Idle at zero opacity, so a cell that never
    // changes never paints it.
    StyledText {
        id: outgoing
        x: Math.round((root.width - width) / 2)
        opacity: 0
        color: root.colText
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.letterSpacing: root.letterSpacing
        font.variableAxes: ({
            "wght": root.weight
        })
        font.features: ({
            "tnum": 1
        })
    }

    StyledText {
        id: incoming
        x: Math.round((root.width - width) / 2)
        text: root.value
        color: root.colText
        font.family: root.fontFamily
        font.pixelSize: root.pixelSize
        font.letterSpacing: root.letterSpacing
        font.variableAxes: ({
            "wght": root.weight
        })
        font.features: ({
            "tnum": 1
        })
    }

    // Every `from` is written out: the roll has to be identical whether or not
    // the previous one had finished.
    ParallelAnimation {
        id: roll

        NumberAnimation {
            target: outgoing
            property: "y"
            from: 0
            to: -root.travel
            duration: root.rollDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: outgoing
            property: "opacity"
            from: 1
            to: 0
            duration: root.rollDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: incoming
            property: "y"
            from: root.travel
            to: 0
            duration: root.rollDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: incoming
            property: "opacity"
            from: 0
            to: 1
            duration: root.rollDuration
            easing.type: Easing.OutCubic
        }
    }
}
