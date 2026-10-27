pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import "WeatherMood.js" as Mood

/*
 * Weather Ribbon (2x1): the next day as a landscape. The hourly temperatures
 * (three-hour steps) draw one smooth ridge across the card's lower half, a
 * filled relief standing on a base line, each step's reading over its point
 * and its hour under the line. Above, the contrast of the type: the
 * temperature in a hairline weight beside the sky in the heaviest one.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "weather_ribbon"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 18
    readonly property var current: Weather.data
    readonly property var today: (Weather.forecastData ?? []).length > 0 ? Weather.forecastData[0] : null
    readonly property string fam: Mood.family(root.current?.wCode ?? 113)

    // The next eight three-hour steps from the current one.
    readonly property var steps: {
        const list = Array.from(Weather.hourlyData ?? []);
        if (list.length === 0)
            return [];
        const hour = DateTime.clock.date.getHours();
        let start = list.findIndex(item => Math.floor(parseInt(item.time) / 100) + 2 >= hour);
        if (start < 0)
            start = 0;
        return list.slice(start, start + 8).map(item => ({
            hour: Math.floor(parseInt(item.time) / 100),
            temp: Number(Weather.useUSCS ? item.tempF : item.tempC)
        }));
    }
    readonly property real low: root.steps.length ? Math.min.apply(null, root.steps.map(s => s.temp)) : 0
    readonly property real high: root.steps.length ? Math.max.apply(null, root.steps.map(s => s.temp)) : 1

    // ── Top: hairline number, heavy sky ──
    StyledText {
        id: tempText
        x: root.padding - 4
        y: root.padding - 14
        text: Mood.number(root.current?.temp) + "°"
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 80
        font.variableAxes: ({ "wght": 110, "wdth": 100, "ROND": 100 })
    }

    Column {
        anchors.left: tempText.right
        anchors.leftMargin: 10
        anchors.right: extremes.left
        anchors.rightMargin: 10
        y: root.padding + 6
        spacing: 0

        StyledText {
            width: parent.width
            elide: Text.ElideRight
            text: String(root.current?.wDesc ?? "").toUpperCase()
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 21
            font.variableAxes: ({ "wght": 950, "wdth": 80, "ROND": 0 })
        }
        StyledText {
            width: parent.width
            elide: Text.ElideRight
            text: root.current?.city ?? ""
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.reading
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    Column {
        id: extremes
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding + 4
        visible: root.today !== null
        spacing: 2

        Repeater {
            model: [
                { label: "H", value: Weather.useUSCS ? root.today?.maxF : root.today?.maxC, high: true },
                { label: "L", value: Weather.useUSCS ? root.today?.minF : root.today?.minC, high: false }
            ]

            delegate: Rectangle {
                id: chip
                required property var modelData
                anchors.right: parent.right
                width: chipText.implicitWidth + 18
                height: 24
                radius: root.pill(height)
                color: chip.modelData.high ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor

                StyledText {
                    id: chipText
                    anchors.centerIn: parent
                    text: chip.modelData.label + " " + (chip.modelData.value ?? "--") + "°"
                    color: chip.modelData.high ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 12
                    font.variableAxes: ({ "wght": 700, "wdth": 90, "ROND": 100 })
                }
            }
        }
    }

    // ── The ridge ──
    Item {
        id: relief
        x: root.padding
        y: 96
        width: root.designWidth - root.padding * 2
        height: root.designHeight - relief.y - root.padding

        readonly property real baseLine: relief.height - 22
        readonly property real ridgeTop: 22
        readonly property real ridgeBottom: relief.baseLine - 26
        readonly property real inset: 22
        readonly property var points: root.steps.map((step, i) => ({
            x: relief.inset + (relief.width - relief.inset * 2) * (root.steps.length > 1 ? i / (root.steps.length - 1) : 0.5),
            y: relief.ridgeBottom - (relief.ridgeBottom - relief.ridgeTop) * ((step.temp - root.low) / Math.max(1, root.high - root.low))
        }))
        // A smooth ridge through every point (cubic segments, horizontal tangents).
        readonly property string ridge: {
            const p = relief.points;
            if (p.length === 0)
                return "";
            let d = "M " + p[0].x + " " + p[0].y;
            for (let i = 1; i < p.length; i++) {
                const mid = (p[i - 1].x + p[i].x) / 2;
                d += " C " + mid + " " + p[i - 1].y + " " + mid + " " + p[i].y + " " + p[i].x + " " + p[i].y;
            }
            return d;
        }
        readonly property string area: relief.points.length === 0 ? ""
            : relief.ridge + " L " + relief.points[relief.points.length - 1].x + " " + relief.baseLine
              + " L " + relief.points[0].x + " " + relief.baseLine + " Z"

        Rectangle {
            x: 0
            y: relief.baseLine
            width: relief.width
            height: 3
            radius: 1.5
            color: WidgetColorScheme.pillBgColor
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            visible: relief.points.length > 1

            ShapePath {
                strokeColor: "transparent"
                fillColor: ColorUtils.mix(WidgetColorScheme.accentColor, root.cardColor, 0.28)
                PathSvg { path: relief.area }
            }
            ShapePath {
                strokeColor: WidgetColorScheme.accentColor
                strokeWidth: 4
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                fillColor: "transparent"
                PathSvg { path: relief.ridge }
            }
        }

        Repeater {
            model: root.steps

            delegate: Item {
                id: step
                required property var modelData
                required property int index
                readonly property var point: relief.points[step.index] ?? ({ x: 0, y: 0 })

                StyledText {
                    x: step.point.x - width / 2
                    y: step.point.y - height - 4
                    text: step.modelData.temp + "°"
                    color: step.index === 0 ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 13
                    font.variableAxes: ({ "wght": step.index === 0 ? 800 : 600, "wdth": 90, "ROND": 100 })
                }
                StyledText {
                    x: step.point.x - width / 2
                    y: relief.baseLine + 6
                    text: step.index === 0 ? Translation.tr("Now") : (String(step.modelData.hour).padStart(2, "0") + "h")
                    color: WidgetColorScheme.subtextColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 11
                    font.variableAxes: ({ "wght": 550, "wdth": 100, "ROND": 100 })
                }
            }
        }

        // Now: a stem from the ridge down to the base line.
        Rectangle {
            visible: relief.points.length > 0
            x: (relief.points[0]?.x ?? 0) - width / 2
            y: relief.points[0]?.y ?? 0
            width: 3
            height: relief.baseLine - y
            radius: 1.5
            color: WidgetColorScheme.accentColor
        }
    }
}
