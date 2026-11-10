pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Month Tall (1x2). The month's short name set huge and condensed fills the
 * top half; the month grid sits in the bottom half. Today is a sunny shape in
 * the accent, days with events carry a dot, weekends step back.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "calendar_month_tall"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "calendar_month_tall")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.calendar_month_tall ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool showEventDots: root.options?.showEventDots ?? true
    readonly property bool showOtherMonths: root.options?.showOtherMonths ?? false

    // -- Geometry (design units) --
    readonly property real designWidth: 240
    readonly property real designHeight: 492
    readonly property real padding: 18
    readonly property real contentWidth: root.designWidth - root.padding * 2
    readonly property real cellSize: root.contentWidth / 7
    // Rows grow to fill what the headline leaves, up to this height.
    readonly property real maxRowHeight: 40
    readonly property real gridHeaderHeight: 22
    readonly property real monthFigureSize: 150

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    CalendarWidgetData {
        id: cal
    }

    readonly property int rows: cal.currentMonthCells.length / 7

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

            // -- Month headline --
            Text {
                id: monthName
                x: root.padding - 4
                y: root.padding - 22
                width: root.contentWidth + 8
                height: root.monthFigureSize + 16
                text: cal.locale.toString(cal.today, "MMM").replace(".", "").toUpperCase()
                color: WidgetColorScheme.accentColor
                font.family: Appearance.font.family.main
                font.pixelSize: root.monthFigureSize
                font.variableAxes: ({ "wght": 860, "wdth": 25, "ROND": 100, "opsz": 144 })
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 60
                verticalAlignment: Text.AlignVCenter
                renderType: Text.QtRendering
            }

            StyledText {
                id: dayLine
                x: root.padding
                anchors.top: monthName.bottom
                anchors.topMargin: -6
                width: root.contentWidth
                text: cal.locale.toString(cal.today, "dddd d")
                color: WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.huge
                font.variableAxes: ({ "wght": 650, "ROND": 100 })
                elide: Text.ElideRight
            }

            StyledText {
                id: subtitle
                x: root.padding
                anchors.top: dayLine.bottom
                text: Translation.tr("%1 · week %2").arg(cal.today.getFullYear()).arg(cal.weekNumber(cal.today))
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1
            }

            // -- Month grid --
            Item {
                id: grid
                x: root.padding
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.padding - 4
                width: root.contentWidth
                readonly property real available: card.height - root.padding - (subtitle.y + subtitle.height + 14)
                readonly property real rowHeight: Math.min(root.maxRowHeight, (grid.available - root.gridHeaderHeight) / root.rows)
                height: root.gridHeaderHeight + root.rows * grid.rowHeight

                Repeater {
                    model: cal.narrowDayNames

                    delegate: StyledText {
                        required property string modelData
                        required property int index
                        x: index * root.cellSize
                        width: root.cellSize
                        height: root.gridHeaderHeight
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: WidgetColorScheme.subtextColorOnBg
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallest + 1
                    }
                }

                Repeater {
                    model: cal.currentMonthCells

                    delegate: Item {
                        id: dayCell
                        required property var modelData
                        required property int index
                        readonly property bool inMonth: dayCell.modelData.getMonth() === cal.today.getMonth()
                        readonly property bool today: cal.isToday(dayCell.modelData)
                        readonly property bool hasEvents: root.showEventDots && dayCell.inMonth && cal.eventsFor(dayCell.modelData).length > 0

                        x: (dayCell.index % 7) * root.cellSize
                        y: root.gridHeaderHeight + Math.floor(dayCell.index / 7) * grid.rowHeight
                        width: root.cellSize
                        height: grid.rowHeight
                        visible: dayCell.inMonth || root.showOtherMonths

                        MaterialShape {
                            visible: dayCell.today
                            anchors.centerIn: parent
                            implicitSize: root.cellSize + 2
                            shape: MaterialShape.Shape.Sunny
                            color: WidgetColorScheme.accentColor
                        }

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: dayCell.hasEvents && !dayCell.today ? -2 : 0
                            text: dayCell.modelData.getDate()
                            color: dayCell.today ? WidgetColorScheme.onAccentColor
                                : (!dayCell.inMonth || cal.isWeekend(dayCell.modelData) ? WidgetColorScheme.subtextColorOnBg : WidgetColorScheme.textColorOnBg)
                            opacity: dayCell.inMonth ? 1 : 0.5
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.variableAxes: dayCell.today
                                ? ({ "wght": 800, "wdth": 80, "ROND": 100 })
                                : ({ "wght": 520, "wdth": 90, "ROND": 100 })
                            renderType: Text.QtRendering
                        }

                        Rectangle {
                            visible: dayCell.hasEvents && !dayCell.today
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 4
                            height: 4
                            radius: 2
                            color: WidgetColorScheme.accentColor
                        }
                    }
                }
            }
        }
    }
}
