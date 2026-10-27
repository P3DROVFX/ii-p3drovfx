pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Your Day (1x2): the day's balance in one column, each part in its own
 * visual voice. On top, the day's 24 hours as a heat grid of screen time
 * (the current hour a circle, the rest squares). Then today against the
 * week's average as two bars in one track. Then water, a glass per tap of
 * the + key. At the foot, tonight's bedtime.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "wellbeing_day"
    designWidth: 240
    designHeight: 492

    readonly property real padding: 16
    readonly property real innerWidth: root.designWidth - root.padding * 2
    readonly property date now: DateTime.clock.date
    readonly property string today: AppStats.todayDate
    readonly property var pastDates: AppStats.recentDates(8).filter(date => date !== root.today)
    // Screen time per hour of today, seconds (device time, not app sums).
    readonly property var hours: {
        void AppStats.history;
        return AppStats.deviceHours(root.today, "fg");
    }
    readonly property real todayTotal: root.hours.reduce((sum, s) => sum + s, 0)
    readonly property real average: {
        void AppStats.history;
        const totals = root.pastDates.map(date => AppStats.deviceHours(date, "fg").reduce((sum, s) => sum + s, 0)).filter(t => t > 0);
        return totals.length ? totals.reduce((a, b) => a + b, 0) / totals.length : 0;
    }

    Component.onCompleted: {
        if (!root.isPreview)
            AppStats.ensureDates(root.pastDates.concat([root.today]));
    }

    component Caption: StyledText {
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 11
        font.letterSpacing: 1.2
        font.variableAxes: ({ "wght": 700, "wdth": 120, "ROND": 0 })
    }

    Column {
        x: root.padding
        y: root.padding
        width: root.innerWidth
        spacing: 14

        // ── Date ──
        StyledText {
            text: Qt.locale().toString(root.now, "dddd, d MMM")
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.larger
            font.variableAxes: Appearance.font.variableAxes.titleRounded
        }

        // ── Hours ──
        Column {
            width: parent.width
            spacing: 6

            Caption { text: Translation.tr("SCREEN BY HOUR") }

            Grid {
                id: heat
                columns: 6
                spacing: 4
                readonly property real cellSize: (root.innerWidth - heat.spacing * 5) / 6

                Repeater {
                    model: 24

                    delegate: Rectangle {
                        id: hourCell
                        required property int index
                        readonly property real share: Math.min(1, (root.hours[hourCell.index] ?? 0) / 3600)
                        readonly property bool current: hourCell.index === root.now.getHours()
                        width: heat.cellSize
                        height: heat.cellSize * 0.62
                        radius: hourCell.current ? root.pill(height) : Appearance.rounding.verysmall
                        color: hourCell.share > 0
                            ? ColorUtils.mix(WidgetColorScheme.accentColor, WidgetColorScheme.pillBgColor, 0.25 + 0.75 * hourCell.share)
                            : WidgetColorScheme.pillBgColor
                    }
                }
            }
            Row {
                width: parent.width
                Repeater {
                    model: ["0", "6", "12", "18"]
                    delegate: Caption {
                        required property string modelData
                        width: root.innerWidth / 4
                        text: modelData
                        font.letterSpacing: 0
                    }
                }
            }
        }

        // ── Today vs the week ──
        Column {
            width: parent.width
            spacing: 6

            Caption { text: Translation.tr("TODAY VS 7-DAY AVERAGE") }

            Repeater {
                model: [
                    { label: Translation.tr("Today"), seconds: root.todayTotal, accent: true },
                    { label: Translation.tr("Average"), seconds: root.average, accent: false }
                ]

                delegate: Item {
                    id: bar
                    required property var modelData
                    readonly property real peak: Math.max(1, root.todayTotal, root.average)
                    width: root.innerWidth
                    height: 30

                    Rectangle {
                        width: Math.max(height, parent.width * bar.modelData.seconds / bar.peak)
                        height: parent.height
                        radius: root.pill(height)
                        color: bar.modelData.accent ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor
                        Behavior on width {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                    }
                    StyledText {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: bar.modelData.label + "  " + ScreenTimeLimits.formatSeconds(bar.modelData.seconds)
                        color: bar.modelData.accent ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: 13
                        font.variableAxes: ({ "wght": 650, "wdth": 90, "ROND": 100 })
                    }
                }
            }
        }

        // ── Water ──
        Column {
            width: parent.width
            spacing: 6

            Caption {
                text: Translation.tr("WATER · %1 OF %2").arg(WaterReminderService.glassesDrunk).arg(WaterReminderService.dailyGoal)
            }

            Item {
                width: parent.width
                height: 40

                Flow {
                    anchors.left: parent.left
                    anchors.right: addKey.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: Math.min(12, WaterReminderService.dailyGoal)

                        delegate: Rectangle {
                            required property int index
                            readonly property bool full: index < WaterReminderService.glassesDrunk
                            width: 14
                            height: 18
                            // A glass: square-ish at the brim, round at the foot.
                            topLeftRadius: 3
                            topRightRadius: 3
                            bottomLeftRadius: 7
                            bottomRightRadius: 7
                            color: full ? WidgetColorScheme.pillFillColor : WidgetColorScheme.pillBgColor
                        }
                    }
                }

                WidgetButton {
                    id: addKey
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    symbol: "add"
                    symbolSize: 20
                    colFill: WidgetColorScheme.pillFillColor
                    colContent: WidgetColorScheme.textColorOnPillFill
                    onClicked: if (root.actionsEnabled) WaterReminderService.drink(1)
                }
            }
        }
    }

    // ── Tonight ──
    Rectangle {
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        width: root.innerWidth
        height: 44
        radius: root.pill(height)
        color: WidgetColorScheme.pillBgColor
        visible: BedtimeService.enabled

        MaterialSymbol {
            id: bedGlyph
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "bedtime"
            iconSize: 20
            fill: 1
            color: WidgetColorScheme.accentColor
        }
        StyledText {
            anchors.left: bedGlyph.right
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: Translation.tr("Bed at %1").arg(Qt.locale().toString(BedtimeService.targetFor(BedtimeService.nightKey(root.now)), Config.options?.time?.format ?? "hh:mm"))
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
        }
    }
}
