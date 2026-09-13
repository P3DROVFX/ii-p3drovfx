pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

/**
 * `bloom` variant of the Neural clock.
 *
 * Two Material shapes carrying the hours and the minutes, interlocked rather
 * than placed side by side. The hours sit in front and **burn a margin into the
 * minutes shape behind them**, so the pair reads as one object with depth
 * instead of two chips that happen to touch.
 *
 * Shapes are opaque, so they would occlude each other anyway; what the die-cut
 * adds is the gap. Doing it with a mask rather than by painting an oversized
 * copy of the front shape in the bar's colour is deliberate — the bar's
 * backdrop is a theme token that can be transparent, and a fake halo would show
 * as a hard blob the moment it is.
 */
Item {
    id: root

    property bool vertical: false
    property real thickness: 32

    property string hoursText: ""
    property string minutesText: ""

    property color colHours: "white"
    property color colOnHours: "black"
    property color colMinutes: "white"
    property color colOnMinutes: "black"

    readonly property real shapeSize: Math.round(root.thickness * 0.98)
    // Shallow on purpose: the digits sit centred in each shape, so a deeper
    // interlock starts eating the leading digit of the minutes rather than the
    // shape's empty flank.
    readonly property real overlap: Math.round(root.shapeSize * 0.22)
    readonly property real cutStroke: Math.max(2, Math.round(root.thickness * 0.07))
    readonly property real digitPixelSize: Math.round(root.shapeSize * 0.42)

    implicitWidth: root.vertical
        ? root.thickness
        : root.shapeSize * 2 - root.overlap
    implicitHeight: root.vertical
        ? root.shapeSize * 2 - root.overlap
        : root.thickness

    // The hours lead: left-to-right horizontally, top-to-bottom vertically.
    readonly property real hoursX: root.vertical ? Math.round((root.thickness - root.shapeSize) / 2) : 0
    readonly property real hoursY: root.vertical ? 0 : Math.round((root.thickness - root.shapeSize) / 2)
    readonly property real minutesX: root.vertical
        ? root.hoursX
        : root.shapeSize - root.overlap
    readonly property real minutesY: root.vertical
        ? root.shapeSize - root.overlap
        : root.hoursY

    DieCutRing {
        id: cutRing
        radius: root.cutStroke
    }

    // ── Behind: the minutes shape, before the hours are taken out of it ──────
    Item {
        id: minutesLayer
        anchors.fill: parent
        visible: false

        MaterialShape {
            x: root.minutesX
            y: root.minutesY
            implicitSize: root.shapeSize
            shape: MaterialShape.Shape.Cookie12Sided
            color: root.colMinutes

            StyledText {
                anchors.centerIn: parent
                text: root.minutesText
                font.family: Appearance.font.family.title
                font.pixelSize: root.digitPixelSize
                font.variableAxes: ({
                    "wght": 700
                })
                font.features: ({
                    "tnum": 1
                })
                font.letterSpacing: -0.6
                color: root.colOnMinutes
            }
        }
    }

    // ── Mask: the hours shape, dilated ───────────────────────────────────────
    Item {
        id: cutoutLayer
        anchors.fill: parent
        visible: false

        Repeater {
            model: cutRing.samples

            delegate: MaterialShape {
                id: cutSample
                required property var modelData
                x: root.hoursX + cutSample.modelData.dx
                y: root.hoursY + cutSample.modelData.dy
                implicitSize: root.shapeSize
                shape: MaterialShape.Shape.Sunny
                color: "black"
            }
        }
    }

    OpacityMask {
        anchors.fill: parent
        source: minutesLayer
        maskSource: cutoutLayer
        invert: true
    }

    // ── In front: the hours shape, untouched ─────────────────────────────────
    MaterialShape {
        x: root.hoursX
        y: root.hoursY
        implicitSize: root.shapeSize
        shape: MaterialShape.Shape.Sunny
        color: root.colHours

        StyledText {
            anchors.centerIn: parent
            text: root.hoursText
            font.family: Appearance.font.family.title
            font.pixelSize: root.digitPixelSize
            font.variableAxes: ({
                "wght": 800
            })
            font.features: ({
                "tnum": 1
            })
            font.letterSpacing: -0.6
            color: root.colOnHours
        }
    }
}
