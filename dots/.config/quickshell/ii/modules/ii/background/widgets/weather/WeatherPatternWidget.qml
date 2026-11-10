pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "WeatherMood.js" as Mood

/*
 * Weather Pattern (1x1): the sky as a halftone, almost no words. An 8x8 grid
 * of marks whose drawing is the condition - dots swelling out of the upper
 * corner for the sun, a band of fat dots for clouds, slanted streaks for
 * rain, scattered specks for snow, flat dashes for fog, streaks crossed by a
 * bolt of warning dots for storms. The lower-left corner is left empty for
 * the one number, small.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "weather_pattern"

    readonly property real padding: 20
    readonly property int cells: 8
    readonly property real cell: (root.designWidth - root.padding * 2) / root.cells
    readonly property var current: Weather.data
    readonly property bool night: Mood.isNight(DateTime.clock.date, root.current?.sunrise, root.current?.sunset)
    readonly property string fam: Mood.family(root.current?.wCode ?? 113)

    WeatherFamilyColors {
        id: tints
    }

    // A stable pseudo-random 0..1 per cell, so the specks never jump.
    function noise(col, row) {
        const v = Math.sin(col * 12.9898 + row * 78.233) * 43758.5453;
        return v - Math.floor(v);
    }
    // The bolt: a zigzag down the middle columns.
    function onBolt(col, row) {
        return col === [4, 4, 3, 3, 4, 4, 3, 3][row] && row > 0 && row < 7;
    }
    // Width, height, corner, rotation and colour of one mark.
    function mark(col, row) {
        const c = root.cell;
        const dot = (size, color) => ({ w: size, h: size, r: size / 2, rot: 0, color: color });
        // The number's corner stays clear.
        if (col < 3 && row > 5)
            return dot(0, "transparent");
        switch (root.fam) {
        case "clear": {
            const d = Math.hypot(root.cells - 1 - col, row) / Math.hypot(root.cells - 1, root.cells - 1);
            const size = c * 0.92 * Math.pow(Math.max(0, 1 - d), root.night ? 2.2 : 1.3);
            return dot(Math.max(2, size), tints.fill("clear"));
        }
        case "partly": {
            const d = Math.hypot(root.cells - 1 - col, row) / Math.hypot(root.cells - 1, root.cells - 1);
            if (d < 0.45)
                return dot(Math.max(3, c * 0.9 * (1 - d / 0.45)), tints.fill("clear"));
            return dot(c * (0.25 + 0.6 * row / (root.cells - 1)), tints.fill("cloud"));
        }
        case "fog":
            return { w: c * (0.55 + 0.4 * root.noise(col, row)), h: c * 0.22, r: c * 0.11, rot: 0,
                     color: row % 2 === 0 ? tints.fill("fog") : tints.fill("cloud") };
        case "rain":
        case "storm":
            if (root.fam === "storm" && root.onBolt(col, row))
                return dot(c * 0.78, tints.fill("storm"));
            return { w: c * 0.16, h: c * (0.5 + 0.35 * root.noise(col, row)), r: c * 0.08, rot: 18,
                     color: tints.fill(root.fam === "storm" ? "cloud" : "rain") };
        case "snow": {
            const n = root.noise(col, row);
            return dot(n > 0.45 ? c * (0.18 + 0.3 * n) : 0, tints.fill("snow"));
        }
        default: {
            const wave = 0.5 + 0.5 * Math.sin(col * 1.1 + row * 0.6);
            return dot(c * (0.3 + 0.55 * wave), tints.fill("cloud"));
        }
        }
    }

    Grid {
        x: root.padding
        y: root.padding
        columns: root.cells

        Repeater {
            model: root.cells * root.cells

            delegate: Item {
                id: cellItem
                required property int index
                readonly property var m: root.mark(cellItem.index % root.cells, Math.floor(cellItem.index / root.cells))
                width: root.cell
                height: root.cell

                Rectangle {
                    anchors.centerIn: parent
                    width: cellItem.m.w
                    height: cellItem.m.h
                    radius: cellItem.m.r
                    rotation: cellItem.m.rot
                    color: cellItem.m.color
                    Behavior on width {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on height {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                }
            }
        }
    }

    StyledText {
        x: root.padding
        anchors.baseline: parent.bottom
        anchors.baselineOffset: -root.padding
        text: Mood.number(root.current?.temp) + "°"
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 40
        font.variableAxes: ({ "wght": 520, "wdth": 88, "ROND": 100 })
    }
}
