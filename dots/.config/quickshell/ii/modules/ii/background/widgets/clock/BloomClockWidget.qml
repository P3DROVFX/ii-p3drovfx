pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Bloom (1x1): like the Cookie clock, the clock is its own shape - one sunny
 * silhouette, no card. Inside, the time is stacked in two voices of the same
 * family: the hours tall, condensed and heavy in the accent, the minutes wide,
 * light and slanted under them. The shape morphs into a twelve-sided cookie
 * under the pointer. "Filled" paints the shape in the accent instead.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "clock_bloom"
    showCard: false

    // -- Geometry (design units) --
    readonly property real bodySize: 236
    readonly property real hourSize: 112
    readonly property real minuteSize: 76
    // Baseline-to-baseline pull between the lines, tighter than the font's own.
    readonly property real lineOverlap: 30

    readonly property bool filled: root.options?.filled ?? false
    readonly property color colBody: root.filled ? WidgetColorScheme.accentColor : WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
    readonly property color colHours: root.filled ? WidgetColorScheme.onAccentColor : WidgetColorScheme.accentColor
    readonly property color colMinutes: root.filled ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg

    HoverHandler {
        id: hover
        enabled: root.actionsEnabled
    }

    ShapeClockSurfaces {
        anchors.fill: parent

        MaterialShape {
            anchors.centerIn: parent
            implicitSize: root.bodySize
            shapeString: hover.hovered ? "Cookie12Sided" : "Sunny"
            color: root.colBody
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 2
        spacing: -root.lineOverlap

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.hours
            color: root.colHours
            font.family: Appearance.font.family.main
            font.pixelSize: root.hourSize
            font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100, "opsz": 144 })
            renderType: Text.QtRendering
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.minutes
            color: root.colMinutes
            font.family: Appearance.font.family.main
            font.pixelSize: root.minuteSize
            font.variableAxes: ({ "wght": 300, "wdth": 120, "slnt": -10, "ROND": 0, "opsz": 144 })
            renderType: Text.QtRendering
        }
    }

    StyledText {
        visible: DateTime.use12HourClock
        anchors.horizontalCenter: parent.horizontalCenter
        y: 20
        text: DateTime.meridiem.toUpperCase()
        color: root.colMinutes
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.letterSpacing: 1.5
        font.variableAxes: ({ "wght": 700, "wdth": 125 })
    }
}
