pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Water Glass (2x1), on the Water Reminder's counter (WaterReminderService):
 * a tall glass fills to today's share of the goal, with a tick for every
 * glass; adding one sloshes the surface once and settles. Beside it, the count
 * in tall digits, the week as small bars, and the keys to add or take back.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "water_glass"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 16
    readonly property real glassWidth: 118
    readonly property real keyHeight: 48

    readonly property int goal: Math.max(1, WaterReminderService.dailyGoal)
    readonly property int glasses: Math.max(0, WaterReminderService.glassesDrunk)
    readonly property real level: Math.min(1, root.glasses / root.goal)
    readonly property bool reached: root.glasses >= root.goal
    readonly property var week: {
        WaterReminderService.glassesDrunk;
        WaterReminderService.history;
        return WaterReminderService.week();
    }

    Component.onCompleted: {
        if (!root.isPreview && Persistent.ready)
            WaterReminderService.ensureToday();
    }

    // One slosh per change: 1 at the change, eased back to calm.
    property real slosh: 0
    property real wavePhase: 0
    onGlassesChanged: {
        if (Appearance.reducedMotion)
            return;
        sloshAnim.restart();
    }
    ParallelAnimation {
        id: sloshAnim
        NumberAnimation { target: root; property: "slosh"; from: 1; to: 0; duration: 1400; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "wavePhase"; from: 0; to: Math.PI * 4; duration: 1400; easing.type: Easing.OutCubic }
    }

    // ── Glass ──
    ClippingRectangle {
        id: glass
        x: root.padding
        y: root.padding
        width: root.glassWidth
        height: root.designHeight - root.padding * 2
        radius: Appearance.rounding.large
        color: WidgetColorScheme.pillBgColor

        Item {
            id: liquid
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            // Never quite empty: a film on the bottom says where it fills from.
            height: Math.max(10, glass.height * root.level)

            Behavior on height {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            readonly property real amplitude: 2 + 7 * root.slosh

            Shape {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height + 12
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: WidgetColorScheme.accentColor
                    strokeWidth: -1

                    PathPolyline {
                        path: {
                            const w = liquid.width;
                            const h = liquid.height + 12;
                            const points = [];
                            const steps = 24;
                            for (let i = 0; i <= steps; i++) {
                                const x = w * i / steps;
                                const y = 12 + Math.sin(i / steps * Math.PI * 2 + root.wavePhase) * liquid.amplitude;
                                points.push(Qt.point(x, y));
                            }
                            points.push(Qt.point(w, h));
                            points.push(Qt.point(0, h));
                            points.push(points[0]);
                            return points;
                        }
                    }
                }
            }
        }

        // A tick at every glass, on the right edge.
        Repeater {
            model: root.goal - 1

            delegate: Rectangle {
                required property int index
                readonly property real at: (index + 1) / root.goal
                readonly property bool under: at <= root.level
                x: glass.width - width - 10
                y: glass.height * (1 - at) - height / 2
                width: 14
                height: 3
                radius: 1.5
                color: under ? WidgetColorScheme.onAccentColor : WidgetColorScheme.subtextColorOnBg
                opacity: under ? 0.55 : 0.45
            }
        }

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            text: root.reached ? "check_circle" : "water_drop"
            iconSize: 28
            fill: 1
            color: root.level > 0.12 ? WidgetColorScheme.onAccentColor : WidgetColorScheme.accentColor
        }
    }

    // ── Header ──
    StyledText {
        anchors.left: glass.right
        anchors.leftMargin: 18
        y: root.padding
        text: Translation.tr("Hydration").toUpperCase()
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.letterSpacing: 1.5
    }

    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding - 4
        width: leftText.implicitWidth + 18
        height: 24
        radius: root.pill(height)
        color: root.reached ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor

        StyledText {
            id: leftText
            anchors.centerIn: parent
            text: root.reached ? Translation.tr("Goal reached") : Translation.tr("%1 to go").arg(root.goal - root.glasses)
            color: root.reached ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
        }
    }

    // ── Count ──
    Row {
        anchors.left: glass.right
        anchors.leftMargin: 14
        y: 26
        spacing: 6

        Text {
            id: countText
            text: String(root.glasses)
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 112
            font.variableAxes: ({ "wght": 780, "wdth": 40, "ROND": 100, "opsz": 144 })
            renderType: Text.QtRendering
        }

        Column {
            // Sits on the digits' baseline, under the descender space.
            y: countText.baselineOffset - height + 6
            spacing: 0

            StyledText {
                text: "/ " + root.goal
                color: WidgetColorScheme.accentColor
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.huge + 6
                font.variableAxes: ({ "wght": 600, "wdth": 70, "ROND": 100 })
            }
            StyledText {
                text: Translation.tr("glasses")
                color: WidgetColorScheme.subtextColorOnBg
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    // ── Week ──
    Row {
        id: weekRow
        anchors.left: glass.right
        anchors.leftMargin: 18
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        height: root.keyHeight
        spacing: 6

        Repeater {
            model: root.week

            delegate: Item {
                id: day
                required property var modelData
                required property int index
                readonly property bool today: day.index === 6
                readonly property real share: Math.min(1, Number(day.modelData.glasses) / root.goal)
                width: 14
                height: weekRow.height

                Rectangle {
                    id: track
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: parent.height - 16
                    radius: root.pill(width)
                    color: WidgetColorScheme.pillBgColor

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(day.share > 0 ? width : 0, parent.height * day.share)
                        radius: parent.radius
                        color: day.today ? WidgetColorScheme.accentColor : WidgetColorScheme.pillFillColor

                        Behavior on height {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: Qt.locale().toString(day.modelData.date, "ddd").charAt(0).toUpperCase()
                    color: day.today ? WidgetColorScheme.accentColor : WidgetColorScheme.subtextColorOnBg
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
        }
    }

    // ── Keys ──
    Row {
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        spacing: 6

        WidgetButton {
            width: root.keyHeight
            height: root.keyHeight
            enabled: root.glasses > 0
            symbol: "remove"
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: WaterReminderService.drink(-1)
        }

        WidgetButton {
            width: 112
            height: root.keyHeight
            symbol: "water_full"
            label: Translation.tr("Glass")
            labelAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
            colFill: WidgetColorScheme.accentColor
            colContent: WidgetColorScheme.onAccentColor
            // Drops into a rounded square for a beat after each glass.
            restRadius: sloshAnim.running ? Appearance.rounding.normal : root.pill(height)
            onClicked: WaterReminderService.drink(1)
        }
    }
}
