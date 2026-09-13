pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

/**
 * `seam` variant of the Relief clock — the quiet one.
 *
 * A single hairline runs the length of the widget, and the numerals **cut it**
 * as they cross. No plate, no fill, no second colour behind the type: the whole
 * design is one rule and the gaps the digits burn in it.
 *
 * The rule always follows the bar's long axis, which is what makes it read the
 * same in both orientations — horizontally it passes through the middle of the
 * time, vertically it threads down between each pair of digits.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32

    property string hoursText: ""
    property string minutesText: ""
    property string meridiemText: ""

    property color colRule: "white"
    property color colDigits: "white"

    readonly property real digitPixelSize: Math.round(root.thickness * (root.vertical ? 0.5 : 0.62))
    readonly property real meridiemPixelSize: Math.max(8, Math.round(root.thickness * 0.24))
    readonly property real ruleWeight: Math.max(2, Math.round(root.thickness * 0.075))
    // Tight. A wide gap here eats the short segments of rule that survive
    // between digits, and the line stops reading as a line at all — it becomes
    // a few stray dashes.
    readonly property real cutStroke: Math.max(2, Math.round(root.thickness * 0.055))
    // How far the rule runs past the time on each side. This is what makes it a
    // line passing behind the numbers instead of an underscore belonging to
    // them, so it has to be long enough to be unmistakable.
    readonly property real overshoot: Math.round(root.thickness * 0.5)
    readonly property real gap: Math.round(root.thickness * 0.34)

    readonly property real hoursW: hoursLabel.implicitWidth
    readonly property real hoursH: hoursLabel.implicitHeight
    readonly property real minutesW: minutesLabel.implicitWidth
    readonly property real minutesH: minutesLabel.implicitHeight
    readonly property real meridiemW: root.meridiemText === "" ? 0 : meridiemLabel.implicitWidth + root.gap

    // Text boxes carry the font's leading above and below the ink, so stacking
    // them at their full height leaves a hole in the column. This pulls them
    // back into each other by that band and no further.
    readonly property real stackGap: -Math.round(root.hoursH * 0.2)

    readonly property real contentLength: root.vertical
        ? root.hoursH + root.stackGap + root.minutesH
        : root.hoursW + root.gap + root.minutesW + root.meridiemW

    implicitWidth: root.vertical ? root.thickness : root.contentLength + root.overshoot * 2
    implicitHeight: root.vertical ? root.contentLength + root.overshoot * 2 : root.thickness

    readonly property real hoursX: root.vertical
        ? Math.round((root.thickness - root.hoursW) / 2)
        : root.overshoot
    readonly property real hoursY: root.vertical
        ? root.overshoot
        : Math.round((root.thickness - root.hoursH) / 2)
    readonly property real minutesX: root.vertical
        ? Math.round((root.thickness - root.minutesW) / 2)
        : root.overshoot + root.hoursW + root.gap
    readonly property real minutesY: root.vertical
        ? root.hoursY + root.hoursH + root.stackGap
        : root.hoursY
    readonly property real meridiemX: root.overshoot + root.hoursW + root.gap + root.minutesW + root.gap
    readonly property real meridiemY: root.hoursY + root.hoursH - meridiemLabel.implicitHeight
        - Math.round(root.thickness * 0.08)

    DieCutRing {
        id: cutRing
        radius: root.cutStroke
    }

    // ── The rule, before the numerals are taken out of it ────────────────────
    Item {
        id: ruleLayer
        anchors.fill: parent
        visible: false

        Rectangle {
            x: root.vertical ? Math.round((root.width - root.ruleWeight) / 2) : 0
            y: root.vertical ? 0 : Math.round((root.height - root.ruleWeight) / 2)
            width: root.vertical ? root.ruleWeight : root.width
            height: root.vertical ? root.height : root.ruleWeight
            radius: Appearance.rounding.full
            color: root.colRule
        }
    }

    // ── Mask: every glyph, dilated ───────────────────────────────────────────
    Item {
        id: cutoutLayer
        anchors.fill: parent
        visible: false

        Repeater {
            model: cutRing.samples

            delegate: Item {
                id: cutSample
                required property var modelData
                anchors.fill: parent

                StyledText {
                    x: root.hoursX + cutSample.modelData.dx
                    y: root.hoursY + cutSample.modelData.dy
                    text: root.hoursText
                    font: hoursLabel.font
                    color: "black"
                }

                StyledText {
                    x: root.minutesX + cutSample.modelData.dx
                    y: root.minutesY + cutSample.modelData.dy
                    text: root.minutesText
                    font: minutesLabel.font
                    color: "black"
                }

                StyledText {
                    visible: root.meridiemText !== "" && !root.vertical
                    x: root.meridiemX + cutSample.modelData.dx
                    y: root.meridiemY + cutSample.modelData.dy
                    text: root.meridiemText
                    font: meridiemLabel.font
                    color: "black"
                }
            }
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: ruleLayer
        maskSource: cutoutLayer
        invert: true
    }

    // ── The numerals themselves ──────────────────────────────────────────────
    StyledText {
        id: hoursLabel
        x: root.hoursX
        y: root.hoursY
        text: root.hoursText
        font.family: Appearance.font.family.title
        font.pixelSize: root.digitPixelSize
        font.variableAxes: ({
            "wght": 700
        })
        font.letterSpacing: -0.2
        font.features: ({
            "tnum": 1
        })
        color: root.colDigits
    }

    StyledText {
        id: minutesLabel
        x: root.minutesX
        y: root.minutesY
        text: root.minutesText
        font.family: Appearance.font.family.title
        font.pixelSize: root.digitPixelSize
        font.variableAxes: ({
            "wght": 400
        })
        font.letterSpacing: -0.2
        font.features: ({
            "tnum": 1
        })
        color: root.colDigits
    }

    StyledText {
        id: meridiemLabel
        visible: root.meridiemText !== "" && !root.vertical
        x: root.meridiemX
        y: root.meridiemY
        text: root.meridiemText
        font.family: Appearance.font.family.title
        font.pixelSize: root.meridiemPixelSize
        font.variableAxes: ({
            "wght": 600
        })
        font.letterSpacing: 0.8
        color: root.colDigits
    }
}
