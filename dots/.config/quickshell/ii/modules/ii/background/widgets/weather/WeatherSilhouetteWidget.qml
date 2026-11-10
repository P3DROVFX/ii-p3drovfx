pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "WeatherMood.js" as Mood

/*
 * Weather Silhouette (1x2): the next two days as one silhouette and nothing
 * to read but now. Every three hours is a pill centred on the card, as wide
 * as it is warm and coloured by its sky; stacked tight they draw a vase that
 * swells in the afternoons and narrows at night, and a little air opens at
 * each midnight. The top pill is now.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "weather_silhouette"
    designWidth: 240
    designHeight: 492

    readonly property real padding: 18
    readonly property real headerHeight: 52
    readonly property real gap: 3
    readonly property real midnightGap: 12
    readonly property var current: Weather.data

    // From the current three-hour step on, up to 48 hours.
    readonly property var steps: {
        const list = Array.from(Weather.hourlyData ?? []);
        const hour = DateTime.clock.date.getHours();
        let start = list.findIndex(item => Math.floor(parseInt(item.time) / 100) + 2 >= hour);
        if (start < 0)
            start = 0;
        return list.slice(start).map(item => ({
            hour: Math.floor(parseInt(item.time) / 100),
            temp: Number(Weather.useUSCS ? item.tempF : item.tempC),
            fam: Mood.family(item.code)
        }));
    }
    readonly property real low: root.steps.length ? Math.min.apply(null, root.steps.map(s => s.temp)) : 0
    readonly property real high: root.steps.length ? Math.max.apply(null, root.steps.map(s => s.temp)) : 1
    readonly property int midnights: root.steps.filter((s, i) => i > 0 && s.hour === 0).length
    readonly property real rowHeight: root.steps.length === 0 ? 0
        : (root.designHeight - root.padding * 2 - root.headerHeight - root.gap * (root.steps.length - 1) - root.midnightGap * root.midnights) / root.steps.length

    WeatherFamilyColors {
        id: tints
    }

    // ── Now, and only now ──
    Row {
        x: root.padding
        y: root.padding
        spacing: 6

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: WeatherIcons.getMaterialSymbol(root.current?.wCode ?? 113)
            iconSize: 26
            fill: 1
            color: WidgetColorScheme.accentColor
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: Mood.number(root.current?.temp) + "°"
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 30
            font.variableAxes: ({ "wght": 380, "wdth": 100, "ROND": 100 })
        }
    }

    // ── The silhouette ──
    Column {
        x: root.padding
        y: root.padding + root.headerHeight
        width: root.designWidth - root.padding * 2
        spacing: root.gap

        Repeater {
            model: root.steps

            delegate: Item {
                id: band
                required property var modelData
                required property int index
                readonly property bool midnight: band.index > 0 && band.modelData.hour === 0
                readonly property real warmth: (band.modelData.temp - root.low) / Math.max(1, root.high - root.low)
                width: parent.width
                height: root.rowHeight + (band.midnight ? root.midnightGap : 0)

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: parent.width * (0.22 + 0.78 * band.warmth)
                    height: root.rowHeight
                    radius: root.pill(height)
                    color: tints.fill(band.modelData.fam)
                    Behavior on width {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }
}
