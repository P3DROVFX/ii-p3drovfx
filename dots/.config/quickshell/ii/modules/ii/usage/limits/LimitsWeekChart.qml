pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The last seven days of focused time as thick bars standing in full-height tracks,
 * packed close together: today in the full content colour with its figure above it,
 * the rest tinted, and a small check at the top of every day that stayed inside its
 * limit. The limit itself is a faint rail across the tracks.
 *
 * Each day is one column holding its track and its label, so the two can never drift
 * apart the way two independent rows did.
 */
Item {
    id: root

    property color colContent: ClockStyle.colOnPrimary
    property color colPane: ClockStyle.colPrimary

    readonly property int gap: 4
    readonly property int labelHeight: 18
    readonly property real columnWidth: Math.max(0, (root.width - root.gap * 6) / 7)
    readonly property real trackHeight: Math.max(0, root.height - root.labelHeight - 6)

    readonly property var dates: AppStats.recentDates(7)
    readonly property var totalRule: ScreenTimeLimits.totalLimit()
    readonly property var values: {
        void ScreenTimeLimits.revision;
        void AppStats.history;
        return root.dates.map(d => ScreenTimeLimits.focusForDate(d));
    }
    readonly property var budgets: root.dates.map(d => {
        const rule = root.totalRule;
        if (!rule)
            return 0;
        const day = new Date(d + "T12:00:00").getDay();
        return ScreenTimeLimits.appliesOn(rule, day) ? (rule.minutes ?? 0) * 60 : 0;
    })
    readonly property real maxValue: Math.max(3600, ...root.values, ...root.budgets) * 1.12

    // The limit, where there is one: a faint rail behind the bars.
    Rectangle {
        readonly property real budget: root.budgets[root.budgets.length - 1] || root.budgets.find(b => b > 0) || 0
        visible: budget > 0
        width: root.width
        height: 2
        radius: 1
        y: root.trackHeight - root.trackHeight * (budget / root.maxValue) - 1
        color: ColorUtils.applyAlpha(root.colContent, 0.4)
    }

    Row {
        id: columns
        anchors.fill: parent
        spacing: root.gap

        Repeater {
            model: root.dates.length

            Item {
                id: column
                required property int index
                readonly property real value: root.values[column.index] ?? 0
                readonly property real budget: root.budgets[column.index] ?? 0
                readonly property bool isToday: column.index === root.dates.length - 1
                readonly property bool met: column.budget > 0 && column.value > 0 && column.value <= column.budget && !column.isToday
                readonly property real radius: Math.min(column.width / 2, Appearance.rounding.normal)

                width: root.columnWidth
                height: root.height

                Rectangle {
                    id: track
                    width: parent.width
                    height: root.trackHeight
                    radius: column.radius
                    color: ColorUtils.applyAlpha(root.colContent, 0.08)

                    Rectangle {
                        id: bar
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: column.value > 0 ? Math.max(column.radius * 2, track.height * (column.value / root.maxValue)) : 0
                        radius: column.radius
                        color: column.isToday ? root.colContent : ColorUtils.applyAlpha(root.colContent, column.met ? 0.55 : 0.32)

                        Behavior on height {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                        }

                        MaterialSymbol {
                            visible: column.met && bar.height >= 24
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Math.max(4, column.radius - 8)
                            text: "check"
                            iconSize: 16
                            fill: 1
                            color: root.colPane
                        }
                    }

                    // Today's figure as a small pill resting on its bar, or tucked
                    // inside it once the bar reaches the top of the track.
                    Rectangle {
                        readonly property bool inside: bar.height + height + 6 > track.height
                        visible: column.isToday && column.value > 0
                        z: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(track.width, figure.implicitWidth + 10)
                        height: figure.implicitHeight + 4
                        radius: height / 2
                        y: inside ? track.height - bar.height + 4 : track.height - bar.height - height - 4
                        color: inside ? root.colPane : root.colContent

                        StyledText {
                            id: figure
                            anchors.centerIn: parent
                            text: ScreenTimeLimits.formatCompact(column.value).replace(" ", "")
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Bold
                            color: parent.inside ? root.colContent : root.colPane
                        }
                    }
                }

                StyledText {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: root.labelHeight
                    verticalAlignment: Text.AlignBottom
                    text: Qt.locale().toString(new Date(root.dates[column.index] + "T12:00:00"), "ddd").slice(0, 3)
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: column.isToday ? Font.Bold : Font.Medium
                    color: root.colContent
                    opacity: column.isToday ? 1 : 0.7
                }

                HoverHandler {
                    id: barHover
                }

                StyledToolTip {
                    extraVisibleCondition: barHover.hovered
                    text: Qt.locale().toString(new Date(root.dates[column.index] + "T12:00:00"), "dddd") + " · "
                        + (column.value > 0 ? ScreenTimeLimits.formatSeconds(column.value) : Translation.tr("No data"))
                        + (column.met ? " · " + Translation.tr("within the limit") : "")
                }
            }
        }
    }
}
