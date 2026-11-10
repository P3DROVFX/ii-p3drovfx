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
 * Weather Daylight (2x1): where the sun is. On the right, the day as an arc
 * from sunrise to sunset; the part already lived is filled in the accent and
 * the sun's shape sits at this minute's point on it. After dusk the arc is
 * the night's, travelled by the moon. On the left, the temperature in the
 * widest, lightest cut of the font against the sky in narrow heavy capitals.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "weather_daylight"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 18
    readonly property var current: Weather.data
    readonly property date now: DateTime.clock.date
    readonly property real dayProgress: Mood.dayProgress(root.now, root.current?.sunrise, root.current?.sunset)
    readonly property bool night: root.dayProgress < 0 || root.dayProgress > 1
    // By day, sunrise → sunset; by night, sunset → sunrise over the same arc.
    readonly property real progress: {
        if (!root.night)
            return root.dayProgress;
        const rise = Mood.minutesOf(root.current?.sunrise);
        const set = Mood.minutesOf(root.current?.sunset);
        if (!isFinite(rise) || !isFinite(set))
            return 0.5;
        const length = 1440 - (set - rise);
        let since = root.now.getHours() * 60 + root.now.getMinutes() - set;
        if (since < 0)
            since += 1440;
        return Math.max(0, Math.min(1, since / length));
    }
    readonly property string fam: Mood.family(root.current?.wCode ?? 113)

    // ── Left: the reading ──
    StyledText {
        id: cityText
        x: root.padding
        y: root.padding
        width: 200
        elide: Text.ElideRight
        text: root.current?.city ?? ""
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        font.variableAxes: ({ "wght": 560, "wdth": 100, "ROND": 100 })
    }

    StyledText {
        id: tempText
        x: root.padding - 3
        anchors.top: cityText.bottom
        anchors.topMargin: -2
        width: 210
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 40
        text: Mood.number(root.current?.temp) + "°"
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 92
        font.variableAxes: ({ "wght": 230, "wdth": 151, "ROND": 100 })
    }

    StyledText {
        id: skyText
        x: root.padding
        anchors.top: tempText.bottom
        anchors.topMargin: -4
        width: 200
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        lineHeight: 0.85
        text: String(root.current?.wDesc ?? "").toUpperCase()
        color: WidgetColorScheme.accentColor
        font.family: Appearance.font.family.main
        font.pixelSize: 22
        font.variableAxes: ({ "wght": 820, "wdth": 55, "ROND": 0 })
    }

    StyledText {
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        text: Translation.tr("Feels like %1").arg(Mood.number(root.current?.tempFeelsLike) + "°")
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        font.variableAxes: ({ "wght": 450, "wdth": 100, "slnt": -10, "ROND": 100 })
    }

    // ── Right: the arc ──
    Item {
        id: sky
        x: 236
        y: root.padding
        width: root.designWidth - sky.x - root.padding
        height: root.designHeight - root.padding * 2

        readonly property real stroke: 10
        readonly property real cx: sky.width / 2
        readonly property real rx: sky.width / 2 - 26
        readonly property real horizon: sky.height - 52
        readonly property real ry: sky.horizon - 24
        readonly property real angle: Math.PI * (1 + root.progress)
        readonly property real pointX: sky.cx + sky.rx * Math.cos(sky.angle)
        readonly property real pointY: sky.horizon + sky.ry * Math.sin(sky.angle)

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: WidgetColorScheme.pillBgColor
                strokeWidth: sky.stroke
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"
                PathAngleArc {
                    centerX: sky.cx
                    centerY: sky.horizon
                    radiusX: sky.rx
                    radiusY: sky.ry
                    startAngle: 180
                    sweepAngle: 180
                }
            }
            ShapePath {
                strokeColor: root.night ? WidgetColorScheme.innerShapeColor : WidgetColorScheme.accentColor
                strokeWidth: sky.stroke
                capStyle: ShapePath.RoundCap
                fillColor: "transparent"
                PathAngleArc {
                    centerX: sky.cx
                    centerY: sky.horizon
                    radiusX: sky.rx
                    radiusY: sky.ry
                    startAngle: 180
                    sweepAngle: Math.max(0.5, 180 * root.progress)
                }
            }
        }

        // The ground the arc stands on, with both ends of the day.
        Rectangle {
            id: ground
            x: 0
            y: sky.horizon + 14
            width: sky.width
            height: sky.height - ground.y
            radius: Appearance.rounding.large
            color: WidgetColorScheme.pillBgColor

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "wb_twilight"
                    iconSize: 16
                    color: WidgetColorScheme.subtextColorOnBg
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current?.sunrise ?? ""
                    color: WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.variableAxes: ({ "wght": 650, "wdth": 85, "ROND": 100 })
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current?.sunset ?? ""
                    color: WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.variableAxes: ({ "wght": 650, "wdth": 85, "ROND": 100 })
                }
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "nights_stay"
                    iconSize: 16
                    color: WidgetColorScheme.subtextColorOnBg
                }
            }
        }

        // The sun (or the moon) at this minute's point; a ring of card
        // colour lifts it off the arc.
        Item {
            id: body
            readonly property real size: 50
            x: sky.pointX - body.size / 2
            y: sky.pointY - body.size / 2
            width: body.size
            height: body.size
            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            MaterialShape {
                anchors.centerIn: parent
                width: body.size + 12
                height: body.size + 12
                shapeString: root.night ? "Circle" : "VerySunny"
                color: root.cardColor
            }
            MaterialShape {
                anchors.fill: parent
                shapeString: root.night ? "Circle" : "VerySunny"
                color: root.night ? WidgetColorScheme.innerShapeColor : WidgetColorScheme.accentColor
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.night ? "bedtime" : WeatherIcons.getMaterialSymbol(root.current?.wCode ?? 113)
                iconSize: 22
                fill: 1
                color: root.night ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.onAccentColor
            }
        }
    }
}
