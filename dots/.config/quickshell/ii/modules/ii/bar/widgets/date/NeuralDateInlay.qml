pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

/**
 * `inlay` variant of the Neural date widget.
 *
 * A solid plate with the day number **punched straight through it**: the bar
 * shows through the digits, and the punch carries a margin that also eats the
 * month word where the two collide, so the overlap resolves itself instead of
 * needing to be avoided.
 *
 * It is the inverse of the Expressive `stack`, which cuts small labels *out of*
 * a bare numeral. Here the numeral is the hole and the plate is the ink. Same
 * machinery — one layer rendered alone, a second rendered in black at a ring of
 * offsets to dilate it, and an inverted `OpacityMask` subtracting one from the
 * other — pointed the other way round.
 *
 * Own file for the same reason as `ExpressiveDateStack`: the mask has to replay
 * the numeral at 16 offsets, which needs explicit `x`/`y`, not anchors.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32

    property string dayText: ""
    property string monthText: ""

    property color colPlate: "white"
    property color colOnPlate: "black"

    // The numeral is a hole, so it has to be large: every pixel the punch is
    // dilated by is eaten out of the counters of `0`, `6`, `8` and `9`, and a
    // small numeral runs out of counter before the plate runs out of ink.
    readonly property real dayPixelSize: Math.round(root.thickness * (root.vertical ? 0.64 : 0.84))
    readonly property real monthPixelSize: Math.max(9, Math.round(root.thickness * (root.vertical ? 0.32 : 0.38)))
    readonly property real padding: Math.round(root.thickness * (root.vertical ? 0.15 : 0.22))

    readonly property real dayW: dayMetrics.implicitWidth
    readonly property real dayH: dayMetrics.implicitHeight
    readonly property real monthW: monthLabel.implicitWidth
    readonly property real monthH: monthLabel.implicitHeight

    // Clearance the punch burns around itself, and the reason `stack`'s value
    // cannot be reused: there the dilation only has to miss a numeral's outer
    // edge, here it grows *inwards* too and closes the digits it is cutting.
    // One pixel is enough to keep the month word off the numeral's flank.
    readonly property real cutStroke: Math.max(1, Math.round(root.thickness * 0.035))

    // Vertically the month sits under the numeral's box, most of which is the
    // font's descent and leading rather than ink, so the tuck cancels that
    // measured band before it can bite anything. Horizontally the boxes only
    // meet at their side bearings, so a flat fraction is enough.
    readonly property real descent: Math.max(0, root.dayH - (dayMetrics.baselineOffset > 0
        ? dayMetrics.baselineOffset
        : root.dayH * 0.78))
    readonly property real tuck: root.vertical
        ? root.descent
        : Math.round(root.thickness * 0.07)

    implicitWidth: root.vertical
        ? root.thickness
        : root.padding * 2 + root.dayW + root.monthW - root.tuck
    implicitHeight: root.vertical
        ? root.padding * 2 + root.dayH + root.monthH - root.tuck
        : root.thickness

    readonly property real dayX: root.vertical ? Math.round((root.thickness - root.dayW) / 2) : root.padding
    readonly property real dayY: root.vertical ? root.padding : Math.round((root.thickness - root.dayH) / 2)
    readonly property real monthX: root.vertical
        ? Math.round((root.thickness - root.monthW) / 2)
        : root.padding + root.dayW - root.tuck
    // Horizontally the month sits on the numeral's own baseline. Centring it
    // instead leaves the two reading as separate objects that happen to touch.
    readonly property real monthY: root.vertical
        ? root.dayY + root.dayH - root.tuck
        : root.dayY + (dayMetrics.baselineOffset > 0 && monthLabel.baselineOffset > 0
            ? dayMetrics.baselineOffset - monthLabel.baselineOffset
            : Math.round((root.dayH - root.monthH) / 2))

    // A block, not a pill: `rounding.full` here would read as the badge variant
    // wearing a different colour, and the punched digits need flat run of ink
    // around them to sit in.
    readonly property real plateRadius: Math.min(Appearance.rounding.normal, Math.round(root.thickness * 0.34))

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

    // Measured, never drawn — the visible numeral is the hole, so there is no
    // painted copy of it to take metrics from.
    StyledText {
        id: dayMetrics
        visible: false
        text: root.dayText
        font.family: Appearance.font.family.title
        font.pixelSize: root.dayPixelSize
        font.variableAxes: ({
            "wght": 800
        })
        // Near-zero tracking on purpose: the punch is dilated, so each digit
        // grows towards its neighbour. The tight `-1.0` the painted variants
        // use welds `3` and `0` into one hole here.
        font.letterSpacing: -0.2
        font.features: ({
            "tnum": 1
        })
    }

    // ── The ink: plate plus month word ───────────────────────────────────────
    Item {
        id: plateLayer
        anchors.fill: parent
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: root.plateRadius
            color: root.colPlate
        }

        StyledText {
            id: monthLabel
            x: root.monthX
            y: root.monthY
            text: root.monthText
            font.family: Appearance.font.family.title
            font.pixelSize: root.monthPixelSize
            font.variableAxes: ({
                "wght": 700
            })
            font.letterSpacing: 0.6
            color: root.colOnPlate
        }
    }

    // ── The punch: the numeral, dilated ──────────────────────────────────────
    Item {
        id: punchLayer
        anchors.fill: parent
        visible: false

        Repeater {
            model: root.cutSamples

            delegate: StyledText {
                id: punchSample
                required property var modelData
                x: root.dayX + punchSample.modelData.dx
                y: root.dayY + punchSample.modelData.dy
                text: root.dayText
                font: dayMetrics.font
                color: "black"
            }
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: plateLayer
        maskSource: punchLayer
        invert: true
    }
}
