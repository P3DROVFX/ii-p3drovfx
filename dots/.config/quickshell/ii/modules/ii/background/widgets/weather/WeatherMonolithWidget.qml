pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "WeatherMood.js" as Mood

/*
 * Weather Monolith (1x1): the temperature is the card. Its digits stand on
 * the card's foot at the narrowest, heaviest cut of the font, half-rounded,
 * with the degree hung light in the accent. Above them, room: the
 * city in wide spaced capitals, the sky in a slanted light line, and the
 * condition's shape alone in the corner. Today's high and low ride the right
 * edge in a condensed cut.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "weather_monolith"

    readonly property real padding: 18
    readonly property var current: Weather.data
    readonly property var today: (Weather.forecastData ?? []).length > 0 ? Weather.forecastData[0] : null
    readonly property bool night: Mood.isNight(DateTime.clock.date, root.current?.sunrise, root.current?.sunset)
    readonly property string fam: Mood.family(root.current?.wCode ?? 113)

    StyledText {
        id: cityText
        x: root.padding
        y: root.padding
        width: root.designWidth - root.padding * 2 - conditionShape.width - 8
        elide: Text.ElideRight
        text: String(root.current?.city ?? "").toUpperCase()
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 12
        font.letterSpacing: 1.6
        font.variableAxes: ({ "wght": 720, "wdth": 125, "ROND": 0 })
    }

    StyledText {
        x: root.padding
        anchors.top: cityText.bottom
        anchors.topMargin: 4
        width: cityText.width
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: root.current?.wDesc ?? ""
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 20
        lineHeight: 0.9
        font.variableAxes: ({ "wght": 330, "wdth": 100, "slnt": -10, "ROND": 100 })
    }

    Item {
        id: conditionShape
        x: root.designWidth - width - root.padding + 4
        y: root.padding - 4
        width: 58
        height: 58

        MaterialShape {
            anchors.fill: parent
            shapeString: Mood.shapeName(root.fam, root.night)
            color: WidgetColorScheme.accentColor
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: WeatherIcons.getMaterialSymbol(root.current?.wCode ?? 113)
            iconSize: 26
            fill: 1
            color: WidgetColorScheme.onAccentColor
        }
    }

    // ── The number ──
    StyledText {
        id: digits
        x: root.padding - 4
        anchors.baseline: parent.bottom
        anchors.baselineOffset: -16
        width: 168
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: 60
        text: Mood.number(root.current?.temp)
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 158
        // ROND 0 breaks the heavy, narrow "9" (its tail renders torn).
        font.variableAxes: ({ "wght": 880, "wdth": 25, "ROND": 50 })
    }

    StyledText {
        x: digits.x + digits.contentWidth + 2
        // The degree's top on the digits' cap line (cap height ~0.72 em).
        anchors.baseline: digits.baseline
        anchors.baselineOffset: -Math.round((digits.fontInfo.pixelSize - font.pixelSize) * 0.72)
        text: "°"
        color: WidgetColorScheme.accentColor
        font.family: Appearance.font.family.main
        font.pixelSize: 64
        font.variableAxes: ({ "wght": 260, "wdth": 100, "ROND": 100 })
    }

    // ── High over low ──
    Column {
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        spacing: 0
        visible: root.today !== null

        Repeater {
            model: [
                { symbol: "arrow_upward", value: Weather.useUSCS ? root.today?.maxF : root.today?.maxC, high: true },
                { symbol: "arrow_downward", value: Weather.useUSCS ? root.today?.minF : root.today?.minC, high: false }
            ]

            delegate: Row {
                id: extreme
                required property var modelData
                anchors.right: parent.right
                spacing: 1

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: extreme.modelData.symbol
                    iconSize: 14
                    color: extreme.modelData.high ? WidgetColorScheme.accentColor : WidgetColorScheme.subtextColorOnBg
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (extreme.modelData.value ?? "--") + "°"
                    color: extreme.modelData.high ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.subtextColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 19
                    font.variableAxes: ({ "wght": 640, "wdth": 70, "ROND": 100 })
                }
            }
        }
    }
}
