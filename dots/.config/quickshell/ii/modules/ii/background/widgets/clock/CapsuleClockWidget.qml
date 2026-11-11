pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Capsule (2x1): the Cookie clock's scalloped edge stretched into a wide
 * capsule, and the capsule is the clock - no card. The time runs on one line
 * in two voices (heavy condensed hours in the accent, light wide minutes),
 * with the date stacked small beside it. Under the pointer the scallops
 * deepen (the edge morphs; nothing turns).
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "clock_capsule"
    showCard: false
    designWidth: 492
    designHeight: 240

    // -- Geometry (design units) --
    readonly property real capsuleHeight: 196
    readonly property real figureSize: 150
    readonly property real padding: 40

    readonly property date now: DateTime.clock.date
    readonly property bool showDate: root.options?.showDate ?? true

    HoverHandler {
        id: hover
        enabled: root.actionsEnabled
    }

    // The scallops: how deep, and how many round the whole edge.
    property real amplitude: hover.hovered ? 7 : 4
    readonly property int bumps: 30
    Behavior on amplitude {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    ShapeClockSurfaces {
        id: surfaces
        anchors.centerIn: parent
        width: root.designWidth - 8
        height: root.capsuleHeight

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                fillColor: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
                pathHints: ShapePath.PathSolid & ShapePath.PathNonIntersecting

                // A stadium walked by arc length, each point pushed along its
                // normal by a sine whose period divides the perimeter, so the
                // waves close on themselves.
                PathPolyline {
                    path: {
                        const a = root.amplitude;
                        const w = surfaces.width - a * 2;
                        const h = surfaces.height - a * 2;
                        const r = h / 2;
                        const straight = w - h;
                        const perimeter = straight * 2 + Math.PI * h;
                        // Whole waves only, or the seam shows.
                        const waves = root.bumps;
                        const steps = 720;
                        const points = [];
                        for (let i = 0; i <= steps; i++) {
                            const s = i / steps * perimeter;
                            let x, y, nx, ny;
                            if (s < straight) {                         // top, left to right
                                x = r + s; y = 0; nx = 0; ny = -1;
                            } else if (s < straight + Math.PI * r) {    // right end
                                const t = (s - straight) / r - Math.PI / 2;
                                nx = Math.cos(t); ny = Math.sin(t);
                                x = w - r + nx * r; y = r + ny * r;
                            } else if (s < straight * 2 + Math.PI * r) { // bottom, right to left
                                x = w - r - (s - straight - Math.PI * r); y = h; nx = 0; ny = 1;
                            } else {                                     // left end
                                const t = (s - straight * 2 - Math.PI * r) / r + Math.PI / 2;
                                nx = Math.cos(t); ny = Math.sin(t);
                                x = r + nx * r; y = r + ny * r;
                            }
                            const wave = Math.cos(s / perimeter * waves * Math.PI * 2) * a;
                            points.push(Qt.point(a + x + nx * wave, a + y + ny * wave));
                        }
                        return points;
                    }
                }
            }
        }
    }

    Row {
        id: time
        x: root.padding
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        Text {
            anchors.baseline: minutes.baseline
            text: DateTime.hours
            color: WidgetColorScheme.accentColor
            font.family: Appearance.font.family.main
            font.pixelSize: root.figureSize
            font.variableAxes: ({ "wght": 760, "wdth": 40, "ROND": 100, "opsz": 144 })
            renderType: Text.QtRendering
        }
        Text {
            id: minutes
            text: DateTime.minutes
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: root.figureSize
            font.variableAxes: ({ "wght": 300, "wdth": 110, "ROND": 0, "opsz": 144 })
            renderType: Text.QtRendering
        }
    }

    Column {
        visible: root.showDate
        anchors.right: parent.right
        anchors.rightMargin: root.padding + 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: -2

        StyledText {
            anchors.right: parent.right
            text: Qt.locale().toString(root.now, "ddd").replace(".", "").toUpperCase()
            color: WidgetColorScheme.accentColor
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.letterSpacing: 1.5
            font.variableAxes: ({ "wght": 800, "wdth": 120 })
        }
        Text {
            anchors.right: parent.right
            text: String(root.now.getDate())
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 40
            font.variableAxes: ({ "wght": 700, "wdth": 60, "ROND": 100 })
            renderType: Text.QtRendering
        }
        StyledText {
            anchors.right: parent.right
            text: Qt.locale().toString(root.now, "MMM").replace(".", "").toUpperCase()
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.letterSpacing: 1.5
            font.variableAxes: ({ "wght": 600, "wdth": 120 })
        }
    }

    StyledText {
        visible: DateTime.use12HourClock
        x: time.x + time.width + 8
        y: time.y + 34
        text: DateTime.meridiem.toUpperCase()
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.letterSpacing: 1.5
        font.variableAxes: ({ "wght": 700, "wdth": 125 })
    }
}
