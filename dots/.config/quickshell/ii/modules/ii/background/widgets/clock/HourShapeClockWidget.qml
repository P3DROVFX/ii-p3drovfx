pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Hour Shape (1x1): no card, the clock is its own silhouette. Every hour of
 * the dial has a shape of its own - a circle at twelve, a four-sided cookie at
 * one, up to a twelve-sided one at eleven - and the body morphs into the next
 * one when the hour turns. The hour fills it in heavy condensed type. The
 * minutes ride a moon on its rim, carried round by the minute (the one
 * rotation, and it carries the value); its face stays upright.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "clock_hour_shape"
    showCard: false

    // One shape per hour of the dial, rounder as the day climbs.
    readonly property list<string> hourShapes: ["Circle", "Cookie4Sided", "Clover4Leaf", "Pentagon", "Cookie6Sided", "Sunny", "Cookie7Sided", "Flower", "Clover8Leaf", "Cookie9Sided", "SoftBurst", "Cookie12Sided"]

    // -- Geometry (design units) --
    readonly property real bodySize: 180
    readonly property real moonSize: 72
    // The moon's centre sits just inside the body's rim, so it bites the edge.
    readonly property real orbitRadius: 84
    readonly property real hourSize: 100

    readonly property date now: DateTime.clock.date
    readonly property bool showMoon: root.options?.showMinutes ?? true

    HoverHandler {
        id: hover
        enabled: root.actionsEnabled
    }

    ShapeClockSurfaces {
        anchors.fill: parent

        MaterialShape {
            id: body
            anchors.centerIn: parent
            implicitSize: root.bodySize
            shapeString: root.hourShapes[root.now.getHours() % 12]
            color: WidgetColorScheme.accentColor
        }

        // The arm turns; only the moon at its tip shows.
        Item {
            id: arm
            visible: root.showMoon
            anchors.fill: parent
            rotation: root.now.getMinutes() * 6
            Behavior on rotation {
                enabled: !Appearance.reducedMotion
                RotationAnimation {
                    direction: RotationAnimation.Shortest
                    duration: Appearance.animation.elementMove.duration
                    easing.type: Appearance.animation.elementMove.type
                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                }
            }

            MaterialShape {
                id: moon
                x: arm.width / 2 - width / 2
                y: arm.height / 2 - root.orbitRadius - height / 2
                implicitSize: root.moonSize
                shapeString: hover.hovered ? "Cookie4Sided" : "Circle"
                color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
            }
        }
    }

    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 3
        text: DateTime.hours
        color: WidgetColorScheme.onAccentColor
        font.family: Appearance.font.family.main
        font.pixelSize: root.hourSize
        font.variableAxes: ({ "wght": 900, "wdth": 30, "ROND": 100, "opsz": 144 })
        renderType: Text.QtRendering
    }

    StyledText {
        visible: DateTime.use12HourClock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: root.bodySize / 2 - 26
        text: DateTime.meridiem.toUpperCase()
        color: WidgetColorScheme.onAccentColor
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.letterSpacing: 1.5
        font.variableAxes: ({ "wght": 700, "wdth": 125 })
    }

    // The moon's face: placed where the arm puts it, never turned.
    Text {
        visible: root.showMoon
        readonly property real angle: arm.rotation * Math.PI / 180
        x: root.designWidth / 2 + Math.sin(angle) * root.orbitRadius - width / 2
        y: root.designHeight / 2 - Math.cos(angle) * root.orbitRadius - height / 2
        text: DateTime.minutes
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 34
        font.variableAxes: ({ "wght": 800, "wdth": 75, "ROND": 100 })
        renderType: Text.QtRendering
    }
}
