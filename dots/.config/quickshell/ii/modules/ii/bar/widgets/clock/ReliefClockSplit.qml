pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

/**
 * `split` variant of the Relief clock — the FlexClock composition, compressed
 * to bar height.
 *
 * Hours and minutes are set at the same size and pushed into each other, offset
 * on both axes so the pair reads diagonally. The minutes sit in front and burn a
 * margin out of the hours, which is what lets the overlap go far enough to be a
 * composition rather than two numbers that touch.
 *
 * The offsets differ per orientation for the reason the whole bar does: with 32
 * px of height the diagonal has to be mostly horizontal, while a 44 px-wide
 * vertical bar can stack the two halves properly.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32

    property string hoursText: ""
    property string minutesText: ""

    property color colHours: "white"
    property color colMinutes: "white"

    // Two number pairs, not one: the pair that fits a bar on its own is already
    // too big once a second one is stacked against it. Sized against the other
    // Relief variants rather than against the bar height.
    readonly property real digitPixelSize: Math.round(root.thickness * (root.vertical ? 0.46 : 0.64))
    readonly property real cutStroke: Math.max(1.5, Math.round(root.thickness * 0.055))

    readonly property real pairW: hoursMetrics.implicitWidth
    readonly property real pairH: hoursMetrics.implicitHeight

    // How far the minutes climb into the hours. Horizontally that is a real
    // bite out of the last digit; vertically it first has to spend the font's
    // descent, which is empty, before it reaches any ink.
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
    readonly property real overlapX: Math.round(root.pairW * 0.26)
    readonly property real overlapY: root.vertical
        ? root.descent + Math.round(root.thickness * 0.08)
        : Math.round(root.pairH * 0.16)

    implicitWidth: root.vertical
        ? root.thickness
        : root.pairW * 2 - root.overlapX
    implicitHeight: root.vertical
        ? root.pairH * 2 - root.overlapY
        : root.thickness

    readonly property real hoursX: root.vertical
        ? Math.max(0, Math.round((root.thickness - (root.pairW + root.shiftX)) / 2))
        : 0
    readonly property real hoursY: root.vertical
        ? 0
        : Math.round((root.thickness - root.pairH) / 2) - Math.round(root.overlapY / 2)
    readonly property real minutesX: root.vertical
        ? root.hoursX + root.shiftX
        : root.pairW - root.overlapX
    readonly property real minutesY: root.vertical
        ? root.pairH - root.overlapY
        : root.hoursY + root.overlapY

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
        // Near-zero tracking: the mask copy of the minutes is dilated, so tight
        // tracking would weld the two halves into one silhouette.
        font.letterSpacing: -0.4
        font.features: ({
            "tnum": 1
        })
    }

    // ── Behind: the hours ────────────────────────────────────────────────────
    Item {
        id: hoursLayer
        anchors.fill: parent
        visible: false

        StyledText {
            x: root.hoursX
            y: root.hoursY
            text: root.hoursText
            font: hoursMetrics.font
            color: root.colHours
        }
    }

    // ── Mask: the minutes, dilated ───────────────────────────────────────────
    Item {
        id: cutoutLayer
        anchors.fill: parent
        visible: false

        Repeater {
            model: cutRing.samples

            delegate: StyledText {
                id: cutSample
                required property var modelData
                x: root.minutesX + cutSample.modelData.dx
                y: root.minutesY + cutSample.modelData.dy
                text: root.minutesText
                font: hoursMetrics.font
                color: "black"
            }
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: hoursLayer
        maskSource: cutoutLayer
        invert: true
    }

    // ── In front: the minutes ────────────────────────────────────────────────
    StyledText {
        x: root.minutesX
        y: root.minutesY
        text: root.minutesText
        font: hoursMetrics.font
        color: root.colMinutes
    }
}
