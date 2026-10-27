pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Screen Time (1x1): today's screen time as a pie of the apps that took it.
 * The ring is cut into the four biggest apps' shares, each in its own colour
 * with its icon riding the segment, the rest in one quiet arc. In the middle
 * the total: hours tall and heavy, minutes light beside them. A click opens
 * the Usage app.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "wellbeing_screen_ring"

    readonly property real cx: root.designWidth / 2
    readonly property real cy: root.designHeight / 2
    readonly property real ring: 84
    readonly property real stroke: 26
    readonly property real gapDegrees: 3

    readonly property var apps: ScreenTimeLimits.todayApps()
    readonly property real total: root.apps.reduce((sum, app) => sum + app.seconds, 0)
    readonly property var colors: [WidgetColorScheme.accentColor, WidgetColorScheme.pillFillColor,
        WidgetColorScheme.highlightCircleColor, WidgetColorScheme.innerShapeColor]
    // [{ key, start, sweep, color }] in degrees from 12 o'clock; the fifth is "the rest".
    readonly property var segments: {
        if (root.total <= 0)
            return [];
        const out = [];
        let start = -90;
        const top = root.apps.slice(0, 4);
        const rest = root.total - top.reduce((sum, app) => sum + app.seconds, 0);
        const parts = top.map((app, i) => ({ key: app.key, seconds: app.seconds, color: root.colors[i] }));
        if (rest > 0)
            parts.push({ key: "", seconds: rest, color: WidgetColorScheme.pillBgColor });
        for (const part of parts) {
            const sweep = 360 * part.seconds / root.total;
            out.push({ key: part.key, start: start, sweep: sweep, color: part.color });
            start += sweep;
        }
        return out;
    }
    readonly property int totalMinutes: Math.floor(root.total / 60)

    Component.onCompleted: ScreenTimeLimits.watch(true)
    Component.onDestruction: ScreenTimeLimits.watch(false)

    onCardTapped: GlobalStates.openUsageApp("")

    // Nothing yet today: the empty ring.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: root.segments.length === 0

        ShapePath {
            strokeColor: WidgetColorScheme.pillBgColor
            strokeWidth: root.stroke
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.cx
                centerY: root.cy
                radiusX: root.ring
                radiusY: root.ring
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    Repeater {
        model: root.segments

        delegate: Item {
            id: segment
            required property var modelData
            readonly property real mid: (segment.modelData.start + segment.modelData.sweep / 2) * Math.PI / 180
            anchors.fill: parent

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: segment.modelData.color
                    strokeWidth: root.stroke
                    capStyle: ShapePath.FlatCap
                    fillColor: "transparent"
                    PathAngleArc {
                        centerX: root.cx
                        centerY: root.cy
                        radiusX: root.ring
                        radiusY: root.ring
                        startAngle: segment.modelData.start + root.gapDegrees / 2
                        sweepAngle: Math.max(0.5, segment.modelData.sweep - root.gapDegrees)
                    }
                }
            }

            // The app rides its own segment when the segment is wide enough to hold it.
            WellbeingAppIcon {
                visible: segment.modelData.key.length > 0 && segment.modelData.sweep >= 24
                appKey: segment.modelData.key
                size: 18
                x: root.cx + root.ring * Math.cos(segment.mid) - width / 2
                y: root.cy + root.ring * Math.sin(segment.mid) - height / 2
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -4

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2

            StyledText {
                anchors.baseline: minutesText.baseline
                text: String(Math.floor(root.totalMinutes / 60))
                color: WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: 50
                font.variableAxes: ({ "wght": 820, "wdth": 45, "ROND": 100 })
            }
            StyledText {
                anchors.baseline: minutesText.baseline
                text: "h"
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: 20
                font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
            }
            StyledText {
                id: minutesText
                leftPadding: 4
                text: String(root.totalMinutes % 60).padStart(2, "0")
                color: WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: 30
                font.variableAxes: ({ "wght": 280, "wdth": 100, "ROND": 100 })
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("today")
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 12
            font.variableAxes: ({ "wght": 500, "wdth": 110, "slnt": -10, "ROND": 100 })
        }
    }
}
