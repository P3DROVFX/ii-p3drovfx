pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Week Strip (2x0.5). The seven days of this week as chips: pills for the
 * other days, and today as a wider rounded square filled with the accent,
 * carrying its short weekday name. Days with events get dots under the number.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "calendar_week_strip"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "calendar_week_strip")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.calendar_week_strip ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool showEventDots: root.options?.showEventDots ?? true
    readonly property bool dimPastDays: root.options?.dimPastDays ?? true

    // -- Geometry (design units) --
    readonly property real designWidth: 492
    readonly property real designHeight: 120
    readonly property real padding: 12
    readonly property real chipGap: 6
    // Today's chip is this many times as wide as another day's.
    readonly property real todayWeight: 2.2
    readonly property real chipWidth: (root.designWidth - root.padding * 2 - root.chipGap * 6) / (6 + root.todayWeight)
    readonly property real dotSize: 6
    readonly property int maxDots: 3

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    CalendarWidgetData {
        id: cal
    }

    Item {
        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: root.contentScale

        StyledRectangularShadow {
            target: card
            visible: Config.options.background.widgets.enableShadows ?? true
        }

        Rectangle {
            id: card
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)

            Row {
                anchors.fill: parent
                anchors.margins: root.padding
                spacing: root.chipGap

                Repeater {
                    model: cal.currentWeek

                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool today: cal.isToday(chip.modelData)
                        readonly property bool past: chip.modelData < cal.today && !chip.today
                        readonly property int eventCount: root.showEventDots ? cal.eventsFor(chip.modelData).length : 0
                        readonly property color contentColor: chip.today ? WidgetColorScheme.onAccentColor
                            : (cal.isWeekend(chip.modelData) ? WidgetColorScheme.subtextColorOnBg : WidgetColorScheme.textColorOnBg)

                        width: chip.today ? root.chipWidth * root.todayWeight : root.chipWidth
                        height: parent.height
                        radius: chip.today ? Appearance.rounding.large : Appearance.rounding.full
                        color: chip.today ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor
                        opacity: root.dimPastDays && chip.past ? 0.55 : 1

                        Column {
                            anchors.centerIn: parent
                            spacing: 0

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: chip.today
                                    ? cal.locale.toString(chip.modelData, "ddd").toUpperCase()
                                    : cal.locale.dayName(chip.modelData.getDay(), Locale.NarrowFormat)
                                color: chip.contentColor
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.letterSpacing: chip.today ? 1.5 : 0
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: chip.modelData.getDate()
                                color: chip.contentColor
                                font.family: Appearance.font.family.main
                                font.pixelSize: chip.today ? 46 : 30
                                font.variableAxes: chip.today
                                    ? ({ "wght": 820, "wdth": 40, "ROND": 100 })
                                    : ({ "wght": 600, "wdth": 70, "ROND": 100 })
                                renderType: Text.QtRendering
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                height: root.dotSize
                                spacing: 3

                                Repeater {
                                    model: Math.min(chip.eventCount, root.maxDots)

                                    delegate: Rectangle {
                                        width: root.dotSize
                                        height: root.dotSize
                                        radius: root.dotSize / 2
                                        color: chip.today ? WidgetColorScheme.onAccentColor : WidgetColorScheme.accentColor
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
