pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

/**
 * `stack` variant of the Expressive date widget, die-cut.
 *
 * The month and the weekday chip sit *on* the day numeral and burn a margin out
 * of it — the same trick the FlexClock desktop widget uses between its digits.
 * The numeral is rendered alone into one layer; the labels are rendered a second
 * time, in black, at a ring of small offsets, which dilates their silhouette by
 * `cutStroke`; an inverted `OpacityMask` subtracts that dilated silhouette from
 * the numeral. What is left is a clean gap around the labels, showing the bar
 * through, and the layering reads as one object rather than two that happen to
 * touch.
 *
 * This lives in its own file because the mask needs every element placed by
 * explicit `x`/`y` against measured text metrics; that does not survive being an
 * anchored sub-tree inside an inline `Component`.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32
    property real dayPixelSize: 29
    property real labelPixelSize: 11
    property real subLabelPixelSize: 10

    property string dayText: ""
    property string monthText: ""
    property string weekdayText: ""

    property color colDay: "white"
    property color colMonth: "white"
    property color colChip: "white"
    property color colOnChip: "black"

    // ── Metrics ───────────────────────────────────────────────────────────────
    readonly property real dayW: dayGlyph.implicitWidth
    readonly property real dayH: dayGlyph.implicitHeight
    readonly property real monthW: monthLabel.implicitWidth
    readonly property real monthH: monthLabel.implicitHeight
    readonly property real chipW: weekdayChip.implicitWidth
    readonly property real chipH: weekdayChip.implicitHeight
    readonly property real labelGap: 1
    readonly property real labelW: Math.max(root.monthW, root.chipW)
    readonly property real labelH: root.monthH + root.labelGap + root.chipH

    // Width of the gap burned around the labels. The gap is what sells the
    // effect, so it stays generous; the *overlap* is what has to stay small,
    // because a bar numeral is ~34px wide and the labels are not.
    readonly property real cutStroke: Math.max(2, Math.round(root.thickness * 0.085))

    // A text item's box is taller than its glyphs by the font's descent and
    // leading. Stacked vertically, a fixed overlap would spend itself on that
    // empty band and never reach the digits, so the vertical tuck cancels the
    // measured descent first and only then bites.
    readonly property real descent: Math.max(0, root.dayH - (dayGlyph.baselineOffset > 0
        ? dayGlyph.baselineOffset
        : root.dayH * 0.78))
    // The bite taken out of the digits is `tuck + cutStroke`, minus the box's
    // own side bearing. Horizontally that is spent on the last digit's right
    // flank, which survives it; vertically it is a band across *both* digits'
    // baselines, so there the tuck only cancels the descent and lets the stroke
    // alone do the cutting.
    readonly property real tuck: root.vertical
        ? root.descent + Math.round(root.thickness * 0.06)
        : Math.round(root.thickness * 0.09)

    implicitWidth: root.vertical ? root.thickness : root.dayW + root.labelW - root.tuck
    implicitHeight: root.vertical ? root.dayH + root.labelH - root.tuck : root.thickness

    readonly property real dayX: root.vertical ? Math.round((root.thickness - root.dayW) / 2) : 0
    readonly property real dayY: root.vertical ? 0 : Math.round((root.thickness - root.dayH) / 2)
    readonly property real labelY: root.vertical
        ? root.dayH - root.tuck
        : Math.round((root.thickness - root.labelH) / 2)
    readonly property real monthX: root.vertical
        ? Math.round((root.thickness - root.monthW) / 2)
        : root.dayW - root.tuck
    readonly property real chipX: root.vertical
        ? Math.round((root.thickness - root.chipW) / 2)
        : root.dayW - root.tuck
    readonly property real monthY: root.labelY
    readonly property real chipY: root.labelY + root.monthH + root.labelGap

    // One ring of samples plus the centre. Dilating by a ring rather than a
    // filled disc is enough as long as neighbouring samples land under a pixel
    // apart, which 16 of them do at any stroke this widget uses.
    readonly property var cutSamples: {
        const radius = root.cutStroke;
        const samples = [
            {
                dx: 0,
                dy: 0
            }
        ];
        const steps = 16;
        for (let i = 0; i < steps; i++) {
            const angle = i / steps * Math.PI * 2;
            samples.push({
                dx: Math.cos(angle) * radius,
                dy: Math.sin(angle) * radius
            });
        }
        return samples;
    }

    // ── Base layer: the numeral, before anything is taken out of it ───────────
    Item {
        id: numeralLayer
        anchors.fill: parent
        visible: false

        StyledText {
            id: dayGlyph
            x: root.dayX
            y: root.dayY
            text: root.dayText
            font.family: Appearance.font.family.title
            font.pixelSize: root.dayPixelSize
            font.variableAxes: ({
                "wght": 800
            })
            font.letterSpacing: -1.2
            font.features: ({
                "tnum": 1
            })
            color: root.colDay
        }
    }

    // ── Mask: the labels, dilated ─────────────────────────────────────────────
    Item {
        id: cutoutLayer
        anchors.fill: parent
        visible: false

        Repeater {
            model: root.cutSamples

            delegate: Item {
                id: cutSample
                required property var modelData
                anchors.fill: parent

                StyledText {
                    x: root.monthX + cutSample.modelData.dx
                    y: root.monthY + cutSample.modelData.dy
                    text: root.monthText
                    font: monthLabel.font
                    color: "black"
                }

                Rectangle {
                    x: root.chipX + cutSample.modelData.dx
                    y: root.chipY + cutSample.modelData.dy
                    width: root.chipW
                    height: root.chipH
                    radius: weekdayChip.radius
                    color: "black"
                }
            }
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: numeralLayer
        maskSource: cutoutLayer
        invert: true
    }

    // ── Top layer: the labels themselves, untouched ───────────────────────────
    StyledText {
        id: monthLabel
        x: root.monthX
        y: root.monthY
        text: root.monthText
        font.family: Appearance.font.family.title
        font.pixelSize: root.labelPixelSize
        font.variableAxes: ({
            "wght": 750
        })
        font.letterSpacing: 1.0
        color: root.colMonth
    }

    Rectangle {
        id: weekdayChip
        x: root.chipX
        y: root.chipY
        implicitWidth: chipLabel.implicitWidth + Math.round(root.thickness * 0.34)
        implicitHeight: Math.round(root.thickness * 0.44)
        radius: Appearance.rounding.full
        color: root.colChip

        StyledText {
            id: chipLabel
            anchors.centerIn: parent
            text: root.weekdayText
            font.family: Appearance.font.family.title
            font.pixelSize: root.subLabelPixelSize
            font.variableAxes: ({
                "wght": 700
            })
            font.letterSpacing: 0.8
            color: root.colOnChip
        }
    }
}
