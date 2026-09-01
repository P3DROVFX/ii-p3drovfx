pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

/**
 * `outline` variant of the Relief clock — hollow numerals.
 *
 * The minutes are drawn by **subtracting a glyph from its own grown copy**: the
 * ring of offsets paints a dilated silhouette, then an inverted mask takes the
 * exact glyph back out of it, and what survives is the rule around the letter
 * and nothing inside. That is a real outline, not a stroked font weight and not
 * a `border` — the interior is genuinely transparent.
 *
 * Which is why the minutes overlap the solid hours here rather than sitting
 * beside them: the hours read straight *through* the hollow digits, and the
 * outline's own ring is what separates the two where they cross.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32

    property string hoursText: ""
    property string minutesText: ""

    property color colSolid: "white"
    property color colHollow: "white"

    readonly property real digitPixelSize: Math.round(root.thickness * (root.vertical ? 0.46 : 0.64))
    // The outline's own weight. Thinner than the other die-cuts, because here
    // the stroke *is* the drawing rather than a clearance around one — and it
    // has to stay proportional to the glyph, or a smaller numeral turns back
    // into a solid blob.
    readonly property real cutStroke: Math.max(1.2, root.thickness * 0.042)

    readonly property real pairW: hoursMetrics.implicitWidth
    readonly property real pairH: hoursMetrics.implicitHeight

    readonly property real descent: Math.max(0, root.pairH - (hoursMetrics.baselineOffset > 0
        ? hoursMetrics.baselineOffset
        : root.pairH * 0.78))
    // In vertical the two halves stagger sideways, but the bar is only
    // `thickness` wide. The shift is whatever room is left after the wider
    // half — never a fraction of it, which is what pushed the minutes clean
    // off the edge of the bar.
    readonly property real shiftX: root.vertical
        ? Math.max(0, Math.min(Math.round(root.pairW * 0.34), root.thickness - root.pairW))
        : 0
    readonly property real overlapX: Math.round(root.pairW * 0.18)
    readonly property real overlapY: root.vertical
        ? root.descent + Math.round(root.thickness * 0.06)
        : 0

    implicitWidth: root.vertical
        ? root.thickness
        : root.pairW * 2 - root.overlapX
    implicitHeight: root.vertical
        ? root.pairH * 2 - root.overlapY
        : root.thickness

    readonly property real hoursX: root.vertical
        ? Math.max(0, Math.round((root.thickness - (root.pairW + root.shiftX)) / 2))
        : 0
    readonly property real hoursY: root.vertical ? 0 : Math.round((root.thickness - root.pairH) / 2)
    readonly property real minutesX: root.vertical
        ? root.hoursX + root.shiftX
        : root.pairW - root.overlapX
    readonly property real minutesY: root.vertical
        ? root.pairH - root.overlapY
        : root.hoursY

    DieCutRing {
        id: cutRing
        radius: root.cutStroke
    }

    StyledText {
        id: hoursMetrics
        visible: false
        text: root.hoursText
        font.family: Appearance.font.family.title
        font.pixelSize: root.digitPixelSize
        font.variableAxes: ({
            "wght": 800
        })
        font.letterSpacing: -0.4
        font.features: ({
            "tnum": 1
        })
    }

    // Solid hours, declared first so the hollow minutes lie over them.
    StyledText {
        x: root.hoursX
        y: root.hoursY
        text: root.hoursText
        font: hoursMetrics.font
        color: root.colSolid
    }

    // ── The grown copy: what the outline is cut from ─────────────────────────
    Item {
        id: grownLayer
        anchors.fill: parent
        visible: false

        Repeater {
            model: cutRing.samples

            delegate: StyledText {
                id: grownSample
                required property var modelData
                x: root.minutesX + grownSample.modelData.dx
                y: root.minutesY + grownSample.modelData.dy
                text: root.minutesText
                font: hoursMetrics.font
                color: root.colHollow
            }
        }
    }

    // ── The exact glyph, taken back out of it ────────────────────────────────
    Item {
        id: coreLayer
        anchors.fill: parent
        visible: false

        StyledText {
            x: root.minutesX
            y: root.minutesY
            text: root.minutesText
            font: hoursMetrics.font
            color: "black"
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: grownLayer
        maskSource: coreLayer
        invert: true
    }
}
