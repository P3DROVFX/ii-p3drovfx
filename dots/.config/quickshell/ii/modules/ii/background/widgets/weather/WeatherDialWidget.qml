pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "WeatherMood.js" as Mood

/*
 * Weather Dial (1x1): the next day on a 24-hour face, midnight on top. Each
 * three-hour step is a segment of the ring at its own hours, coloured by its
 * sky and as thick as it is warm, with its reading just outside. A needle
 * turns with the hour (it carries the time) and the current temperature sits
 * in the middle.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "weather_dial"

    readonly property var current: Weather.data
    readonly property real cx: root.designWidth / 2
    readonly property real cy: root.designHeight / 2
    readonly property real ring: 70
    readonly property real labelRadius: 100
    readonly property date now: DateTime.clock.date

    // The next eight three-hour steps: a full turn of the face.
    readonly property var steps: {
        const list = Array.from(Weather.hourlyData ?? []);
        const hour = root.now.getHours();
        let start = list.findIndex(item => Math.floor(parseInt(item.time) / 100) + 2 >= hour);
        if (start < 0)
            start = 0;
        return list.slice(start, start + 8).map(item => ({
            hour: Math.floor(parseInt(item.time) / 100),
            temp: Number(Weather.useUSCS ? item.tempF : item.tempC),
            fam: Mood.family(item.code)
        }));
    }
    readonly property real low: root.steps.length ? Math.min.apply(null, root.steps.map(s => s.temp)) : 0
    readonly property real high: root.steps.length ? Math.max.apply(null, root.steps.map(s => s.temp)) : 1

    // Degrees from 3 o'clock, clockwise (Qt's arcs), with midnight on top.
    function angleOf(hour) {
        return hour / 24 * 360 - 90;
    }

    WeatherFamilyColors {
        id: tints
    }

    // The empty face under the segments.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: WidgetColorScheme.pillBgColor
            strokeWidth: 6
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
        model: root.steps

        delegate: Item {
            id: segment
            required property var modelData
            readonly property real warmth: (segment.modelData.temp - root.low) / Math.max(1, root.high - root.low)
            readonly property real mid: (root.angleOf(segment.modelData.hour) + 22.5) * Math.PI / 180
            anchors.fill: parent

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: tints.fill(segment.modelData.fam)
                    strokeWidth: 8 + 16 * segment.warmth
                    capStyle: ShapePath.FlatCap
                    fillColor: "transparent"
                    PathAngleArc {
                        centerX: root.cx
                        centerY: root.cy
                        radiusX: root.ring
                        radiusY: root.ring
                        startAngle: root.angleOf(segment.modelData.hour) + 1.5
                        sweepAngle: 42
                    }
                }
            }

            StyledText {
                x: root.cx + root.labelRadius * Math.cos(segment.mid) - width / 2
                y: root.cy + root.labelRadius * Math.sin(segment.mid) - height / 2
                text: segment.modelData.temp + "°"
                color: WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: 12
                font.variableAxes: ({ "wght": 680, "wdth": 85, "ROND": 100 })
            }
        }
    }

    // Quarter marks inside the ring.
    Repeater {
        model: [0, 6, 12, 18]

        delegate: StyledText {
            required property int modelData
            readonly property real a: root.angleOf(modelData) * Math.PI / 180
            x: root.cx + 48 * Math.cos(a) - width / 2
            y: root.cy + 48 * Math.sin(a) - height / 2
            text: String(modelData)
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 10
            font.variableAxes: ({ "wght": 500, "wdth": 100, "ROND": 100 })
        }
    }

    // The needle: turns with the hour.
    Item {
        x: root.cx - width / 2
        y: root.cy - height / 2
        width: 4
        height: (root.ring - 14) * 2
        rotation: (root.now.getHours() + root.now.getMinutes() / 60) / 24 * 360
        // The short way round, so midnight does not unwind the whole day.
        Behavior on rotation {
            RotationAnimation {
                direction: RotationAnimation.Shortest
                duration: Appearance.animation.elementMove.duration
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            x: 0
            y: 0
            width: parent.width
            height: 20
            radius: width / 2
            color: WidgetColorScheme.accentColor
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: -6

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            text: WeatherIcons.getMaterialSymbol(root.current?.wCode ?? 113)
            iconSize: 18
            fill: 1
            color: WidgetColorScheme.accentColor
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Mood.number(root.current?.temp) + "°"
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 34
            font.variableAxes: ({ "wght": 700, "wdth": 95, "ROND": 100 })
        }
    }
}
