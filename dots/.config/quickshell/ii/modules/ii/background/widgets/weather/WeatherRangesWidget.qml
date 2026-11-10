pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets
import "WeatherMood.js" as Mood

/*
 * Weather Ranges (1x2): the week as spans of temperature. A hero block in the
 * accent holds now - the reading in medium weight, the condition's shape
 * large and cut by the block's edge. Below, one row per day: its name in the
 * grotesk face, its sky, and a bar whose filled stretch runs from the day's
 * low to its high on a scale shared by the whole week, so warm and cold days
 * read at a glance. Today carries a dot at the current temperature.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "weather_ranges"
    designWidth: 240
    designHeight: 492

    readonly property real padding: 12
    readonly property var current: Weather.data
    readonly property bool night: Mood.isNight(DateTime.clock.date, root.current?.sunrise, root.current?.sunset)
    readonly property string fam: Mood.family(root.current?.wCode ?? 113)
    readonly property var days: (Weather.forecastData ?? []).slice(0, 5).map(day => ({
        date: day.date,
        code: day.code,
        min: Weather.useUSCS ? day.minF : day.minC,
        max: Weather.useUSCS ? day.maxF : day.maxC
    }))
    readonly property real low: root.days.length ? Math.min.apply(null, root.days.map(day => day.min)) : 0
    readonly property real high: root.days.length ? Math.max.apply(null, root.days.map(day => day.max)) : 1
    readonly property real nowTemp: Number(Mood.number(root.current?.temp))

    function fraction(value) {
        return Math.max(0, Math.min(1, (value - root.low) / Math.max(1, root.high - root.low)));
    }
    function dayName(day, index) {
        if (index === 0)
            return Translation.tr("Today");
        return Qt.locale().toString(new Date(day.date + "T12:00:00"), "ddd").replace(".", "");
    }

    // ── Now ──
    Rectangle {
        id: hero
        x: root.padding
        y: root.padding
        width: root.designWidth - root.padding * 2
        height: 196
        radius: Appearance.rounding.large
        color: WidgetColorScheme.accentColor
        clip: true

        // Cut by the block's straight right edge (clear of its rounded
        // corners, so the rectangular clip is exact): half the shape shows.
        MaterialShape {
            x: hero.width - 92
            y: 26
            width: 150
            height: 150
            shapeString: Mood.shapeName(root.fam, root.night)
            color: ColorUtils.mix(WidgetColorScheme.onAccentColor, WidgetColorScheme.accentColor, 0.2)
        }
        MaterialSymbol {
            x: hero.width - 58
            y: 84
            text: WeatherIcons.getMaterialSymbol(root.current?.wCode ?? 113)
            iconSize: 34
            fill: 1
            color: WidgetColorScheme.accentColor
        }

        StyledText {
            id: heroCity
            x: 16
            y: 16
            width: hero.width - 120
            elide: Text.ElideRight
            text: root.current?.city ?? ""
            color: WidgetColorScheme.onAccentColor
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
        }

        StyledText {
            id: heroTemp
            x: 12
            anchors.bottom: heroSky.top
            anchors.bottomMargin: -10
            text: Mood.number(root.current?.temp) + "°"
            color: WidgetColorScheme.onAccentColor
            font.family: Appearance.font.family.main
            font.pixelSize: 88
            font.variableAxes: ({ "wght": 560, "wdth": 100, "ROND": 100 })
        }

        StyledText {
            id: heroSky
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: hero.width - 32
            elide: Text.ElideRight
            text: root.current?.wDesc ?? ""
            color: WidgetColorScheme.onAccentColor
            opacity: 0.85
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": 500, "wdth": 110, "slnt": -10, "ROND": 100 })
        }
    }

    // ── The week ──
    Column {
        id: week
        x: root.padding
        anchors.top: hero.bottom
        anchors.topMargin: 10
        width: root.designWidth - root.padding * 2
        spacing: 4

        readonly property real rowHeight: (root.designHeight - hero.y - hero.height - 10 - root.padding - week.spacing * 4) / 5

        Repeater {
            model: root.days

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: week.width
                height: week.rowHeight

                StyledText {
                    id: dayText
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 46
                    elide: Text.ElideRight
                    text: root.dayName(row.modelData, row.index).toUpperCase()
                    color: row.index === 0 ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.expressive
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    font.letterSpacing: 0.6
                }

                MaterialSymbol {
                    id: daySymbol
                    anchors.left: dayText.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: WeatherIcons.getMaterialSymbol(row.modelData.code)
                    iconSize: 18
                    fill: 1
                    color: WidgetColorScheme.subtextColorOnBg
                }

                StyledText {
                    id: minText
                    anchors.left: daySymbol.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    horizontalAlignment: Text.AlignRight
                    text: row.modelData.min + "°"
                    color: WidgetColorScheme.subtextColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 14
                    font.variableAxes: ({ "wght": 500, "wdth": 75, "ROND": 100 })
                }

                StyledText {
                    id: maxText
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    text: row.modelData.max + "°"
                    color: WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 14
                    font.variableAxes: ({ "wght": 760, "wdth": 75, "ROND": 100 })
                }

                Rectangle {
                    id: track
                    anchors.left: minText.right
                    anchors.leftMargin: 8
                    anchors.right: maxText.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: 10
                    radius: root.pill(height)
                    color: WidgetColorScheme.pillBgColor

                    Rectangle {
                        x: track.width * root.fraction(row.modelData.min)
                        width: Math.max(track.height, track.width * (root.fraction(row.modelData.max) - root.fraction(row.modelData.min)))
                        height: track.height
                        radius: track.radius
                        color: row.index === 0 ? WidgetColorScheme.accentColor : WidgetColorScheme.pillFillColor
                    }

                    // Now, on today's span: a tick standing through the bar.
                    Rectangle {
                        visible: row.index === 0 && isFinite(root.nowTemp)
                        x: track.width * root.fraction(root.nowTemp) - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4
                        height: 20
                        radius: 2
                        color: WidgetColorScheme.textColorOnBg
                    }
                }
            }
        }
    }
}
