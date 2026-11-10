pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "WeatherMood.js" as Mood

/*
 * Weather Strip (2x1): five days side by side, one column each. In every
 * column the day's sky shape floats at a height set by its high - the
 * warmest day highest - so across the strip the shapes trace the week's
 * curve. Under them the high in tall condensed digits, the low light, and
 * the day's name in wide capitals. Today's column is the accent; a column
 * under the pointer morphs its shape into the family's second one.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "weather_strip"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 12
    readonly property real gap: 6
    readonly property var days: (Weather.forecastData ?? []).slice(0, 5).map(day => ({
        date: day.date,
        fam: Mood.family(day.code),
        code: day.code,
        min: Weather.useUSCS ? day.minF : day.minC,
        max: Weather.useUSCS ? day.maxF : day.maxC
    }))
    readonly property real low: root.days.length ? Math.min.apply(null, root.days.map(day => day.max)) : 0
    readonly property real high: root.days.length ? Math.max.apply(null, root.days.map(day => day.max)) : 1

    WeatherFamilyColors {
        id: tints
    }

    Row {
        x: root.padding
        y: root.padding
        spacing: root.gap

        Repeater {
            model: root.days

            delegate: Rectangle {
                id: column
                required property var modelData
                required property int index
                readonly property bool today: column.index === 0
                readonly property color colContent: column.today ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
                readonly property real warmth: (column.modelData.max - root.low) / Math.max(1, root.high - root.low)
                width: (root.designWidth - root.padding * 2 - root.gap * 4) / 5
                height: root.designHeight - root.padding * 2
                radius: Appearance.rounding.large
                color: column.today ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor

                HoverHandler {
                    id: columnHover
                }

                // The shape rides between the top (warmest) and 56 px lower (coolest).
                Item {
                    id: sky
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 10 + 56 * (1 - column.warmth)
                    width: 52
                    height: 52
                    Behavior on y {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }

                    MaterialShape {
                        anchors.fill: parent
                        shapeString: columnHover.hovered && root.actionsEnabled ? Mood.altShapeName(column.modelData.fam, false) : Mood.shapeName(column.modelData.fam, false)
                        color: column.today ? WidgetColorScheme.onAccentColor : tints.fill(column.modelData.fam)
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: WeatherIcons.getMaterialSymbol(column.modelData.code)
                        iconSize: 22
                        fill: 1
                        color: column.today ? WidgetColorScheme.accentColor : root.contentOn(tints.fill(column.modelData.fam))
                    }
                }

                StyledText {
                    id: maxText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: minText.top
                    anchors.bottomMargin: -6
                    text: column.modelData.max + "°"
                    color: column.colContent
                    font.family: Appearance.font.family.main
                    font.pixelSize: 40
                    font.variableAxes: ({ "wght": 780, "wdth": 50, "ROND": 100 })
                }
                StyledText {
                    id: minText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: dayText.top
                    anchors.bottomMargin: 2
                    text: column.modelData.min + "°"
                    color: column.colContent
                    opacity: 0.7
                    font.family: Appearance.font.family.main
                    font.pixelSize: 17
                    font.variableAxes: ({ "wght": 330, "wdth": 100, "ROND": 100 })
                }
                StyledText {
                    id: dayText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    text: (column.today ? Translation.tr("Today")
                        : Qt.locale().toString(new Date(column.modelData.date + "T12:00:00"), "ddd").replace(".", "")).toUpperCase()
                    color: column.colContent
                    font.family: Appearance.font.family.main
                    font.pixelSize: 11
                    font.letterSpacing: 1.2
                    font.variableAxes: ({ "wght": 650, "wdth": 125, "ROND": 0 })
                }
            }
        }
    }
}
