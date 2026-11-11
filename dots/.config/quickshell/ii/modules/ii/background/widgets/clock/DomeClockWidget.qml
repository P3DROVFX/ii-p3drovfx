pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Dome (2x1): the clock is a half dial of the day, and the dial is the
 * silhouette - no card. Midnight sits at the left foot, noon at the top,
 * midnight again at the right; one thick hand turns with the hour of the day
 * (the rotation carries the value) from a pill at the pivot that holds the
 * time in the expressive digits. The hours already lived are marked in full,
 * the ones ahead are dimmed.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "clock_dome"
    showCard: false
    designWidth: 492
    designHeight: 240

    // -- Geometry (design units) --
    readonly property real domeRadius: 240
    readonly property real footRadius: Appearance.rounding.scale === 0 ? 0 : Appearance.rounding.large
    readonly property real pillWidth: 172
    readonly property real pillHeight: 78
    readonly property real pillBottom: 14
    readonly property point pivot: Qt.point(root.designWidth / 2, root.designHeight - root.pillBottom - root.pillHeight / 2)
    readonly property real markRadius: 158
    readonly property real handLength: 138
    readonly property real handWidth: 20

    readonly property date now: DateTime.clock.date
    readonly property real dayProgress: (root.now.getHours() + root.now.getMinutes() / 60) / 24
    readonly property bool showDate: root.options?.showDate ?? true

    HoverHandler {
        id: hover
        enabled: root.actionsEnabled
    }

    ShapeClockSurfaces {
        anchors.fill: parent

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                id: dome
                readonly property real w: root.designWidth
                readonly property real h: root.designHeight
                readonly property real cx: w / 2
                readonly property real fr: root.footRadius
                // Where the dome's arc meets the foot's rounding.
                readonly property real arcFootY: h - fr
                readonly property real arcFootDx: Math.sqrt(root.domeRadius * root.domeRadius - fr * fr)

                strokeWidth: 0
                fillColor: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
                startX: cx - arcFootDx + fr
                startY: h

                PathLine { x: dome.cx + dome.arcFootDx - dome.fr; y: dome.h }
                PathQuad {
                    controlX: dome.cx + dome.arcFootDx; controlY: dome.h
                    x: dome.cx + dome.arcFootDx; y: dome.arcFootY
                }
                PathArc {
                    x: dome.cx - dome.arcFootDx; y: dome.arcFootY
                    radiusX: root.domeRadius; radiusY: root.domeRadius
                    direction: PathArc.Counterclockwise
                }
                PathQuad {
                    controlX: dome.cx - dome.arcFootDx; controlY: dome.h
                    x: dome.cx - dome.arcFootDx + dome.fr; y: dome.h
                }
            }
        }
    }

    // ── Hour marks: 25 stops from midnight to midnight ──
    Repeater {
        model: 25
        delegate: Item {
            id: mark
            required property int index
            readonly property bool labelled: index === 6 || index === 12 || index === 18
            readonly property bool lived: index / 24 <= root.dayProgress
            readonly property real angle: (-90 + index * 7.5) * Math.PI / 180
            x: root.pivot.x + Math.sin(angle) * root.markRadius - width / 2
            y: root.pivot.y - Math.cos(angle) * root.markRadius - height / 2
            width: 30
            height: 30

            Rectangle {
                visible: !mark.labelled
                anchors.centerIn: parent
                width: mark.index % 3 === 0 ? 8 : 5
                height: width
                radius: width / 2
                color: mark.lived ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
                opacity: mark.lived ? 1 : 0.45
            }
            Text {
                visible: mark.labelled
                anchors.centerIn: parent
                text: String(mark.index)
                color: mark.lived ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
                opacity: mark.lived ? 1 : 0.6
                font.family: Appearance.font.family.main
                font.pixelSize: 20
                font.variableAxes: ({ "wght": 700, "wdth": 80, "ROND": 100 })
                renderType: Text.QtRendering
            }
        }
    }

    // ── The hand ──
    Item {
        id: arm
        x: root.pivot.x
        y: root.pivot.y
        rotation: -90 + root.dayProgress * 180
        Behavior on rotation {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        Rectangle {
            x: -width / 2
            y: -root.handLength
            width: root.handWidth
            height: root.handLength + root.handWidth
            radius: width / 2
            color: WidgetColorScheme.accentColor
        }
    }

    // ── The pivot: the time on a pill that squares off under the pointer ──
    Rectangle {
        x: root.pivot.x - width / 2
        y: root.pivot.y - height / 2
        width: root.pillWidth
        height: root.pillHeight
        radius: hover.hovered ? Math.min(height * 0.3, Appearance.rounding.verylarge) : root.pill(height)
        color: WidgetColorScheme.accentColor
        Behavior on radius {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Row {
            anchors.centerIn: parent
            spacing: 2

            Text {
                anchors.baseline: minutesText.baseline
                text: DateTime.hours
                color: WidgetColorScheme.onAccentColor
                font.family: Appearance.font.family.main
                font.pixelSize: 64
                font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100, "opsz": 144 })
                renderType: Text.QtRendering
            }
            Text {
                anchors.baseline: minutesText.baseline
                text: ":"
                color: WidgetColorScheme.onAccentColor
                opacity: 0.6
                font.family: Appearance.font.family.main
                font.pixelSize: 52
                font.variableAxes: ({ "wght": 500, "wdth": 40, "ROND": 100 })
                renderType: Text.QtRendering
            }
            Text {
                id: minutesText
                text: DateTime.minutes
                color: WidgetColorScheme.onAccentColor
                font.family: Appearance.font.family.main
                font.pixelSize: 64
                font.variableAxes: ({ "wght": 560, "wdth": 40, "ROND": 100, "opsz": 144 })
                renderType: Text.QtRendering
            }
            StyledText {
                visible: DateTime.use12HourClock
                anchors.baseline: minutesText.baseline
                leftPadding: 4
                text: DateTime.meridiem.toUpperCase()
                color: WidgetColorScheme.onAccentColor
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.variableAxes: ({ "wght": 700, "wdth": 120 })
            }
        }
    }

    // ── The date, one word in each foot ──
    Repeater {
        model: root.showDate ? [
            { text: Qt.locale().toString(root.now, "ddd").replace(".", "").toUpperCase(), left: true },
            { text: Qt.locale().toString(root.now, "d MMM").replace(".", "").toUpperCase(), left: false }
        ] : []
        delegate: StyledText {
            required property var modelData
            x: modelData.left ? 44 : root.designWidth - 44 - width
            y: root.designHeight - 38 - height / 2
            text: modelData.text
            color: modelData.left ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            font.letterSpacing: 1.5
            font.variableAxes: ({ "wght": 800, "wdth": 120 })
        }
    }
}
