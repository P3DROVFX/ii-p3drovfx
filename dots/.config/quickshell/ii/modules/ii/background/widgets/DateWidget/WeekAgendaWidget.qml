pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Week Agenda (2x2). The month and week number as a header, then the seven
 * days as rows: a condensed date block and the day's events as chips. Today's
 * row fills with the tonal container and its date block becomes an accent
 * rounded square; days already gone fade back.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "calendar_week_agenda"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "calendar_week_agenda")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.calendar_week_agenda ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property int maxEvents: Math.max(1, Math.min(3, root.options?.maxEventsPerDay ?? 2))
    readonly property bool dimPastDays: root.options?.dimPastDays ?? true

    // -- Geometry (design units) --
    readonly property real designSize: 492
    readonly property real padding: 18
    readonly property real headerHeight: 58
    readonly property real rowGap: 4
    readonly property real rowHeight: (root.designSize - root.padding * 2 - root.headerHeight - root.rowGap * 6) / 7
    readonly property real dateBlockWidth: 58

    implicitWidth: root.designSize * root.contentScale
    implicitHeight: root.designSize * root.contentScale

    CalendarWidgetData {
        id: cal
    }

    Item {
        anchors.centerIn: parent
        width: root.designSize
        height: root.designSize
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

            // -- Header --
            Item {
                id: header
                x: root.padding
                y: root.padding
                width: parent.width - root.padding * 2
                height: root.headerHeight

                StyledText {
                    id: monthTitle
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: -4
                    text: cal.locale.toString(cal.today, "MMMM")
                    color: WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.title
                    font.pixelSize: 32
                    font.variableAxes: ({ "wght": 700, "wdth": 110, "ROND": 100 })
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.top: monthTitle.bottom
                    text: Translation.tr("Week %1 · %2").arg(cal.weekNumber(cal.today)).arg(cal.today.getFullYear())
                    color: WidgetColorScheme.subtextColorOnBg
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.letterSpacing: 1
                }

                MaterialShapeWrappedMaterialSymbol {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 46
                    padding: 0
                    shape: MaterialShape.Shape.Cookie7Sided
                    text: "calendar_view_week"
                    iconSize: 22
                    color: WidgetColorScheme.pillFillColor
                    colSymbol: WidgetColorScheme.textColorOnPillFill
                }
            }

            // -- Days --
            Column {
                x: root.padding
                anchors.top: header.bottom
                width: parent.width - root.padding * 2
                spacing: root.rowGap

                Repeater {
                    model: cal.currentWeek

                    delegate: Rectangle {
                        id: dayRow
                        required property var modelData
                        readonly property bool today: cal.isToday(dayRow.modelData)
                        readonly property bool past: dayRow.modelData < cal.today && !dayRow.today
                        readonly property var events: cal.eventsFor(dayRow.modelData)
                        readonly property int shown: Math.min(dayRow.events.length, root.maxEvents)

                        width: parent.width
                        height: root.rowHeight
                        radius: Appearance.rounding.normal
                        color: dayRow.today ? WidgetColorScheme.pillFillColor : "transparent"
                        opacity: root.dimPastDays && dayRow.past ? 0.5 : 1

                        // Date block
                        Rectangle {
                            id: dateBlock
                            x: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.dateBlockWidth
                            height: parent.height - 8
                            radius: Appearance.rounding.small
                            color: dayRow.today ? WidgetColorScheme.accentColor : "transparent"

                            Row {
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: dayRow.modelData.getDate()
                                    color: dayRow.today ? WidgetColorScheme.onAccentColor : WidgetColorScheme.textColorOnBg
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: 28
                                    font.variableAxes: ({ "wght": 780, "wdth": 35, "ROND": 100 })
                                    renderType: Text.QtRendering
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: cal.locale.dayName(dayRow.modelData.getDay(), Locale.NarrowFormat)
                                    color: dayRow.today ? WidgetColorScheme.onAccentColor : WidgetColorScheme.subtextColorOnBg
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                        }

                        // Events
                        Row {
                            id: eventRow
                            anchors.left: dateBlock.right
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            clip: true

                            readonly property real overflowWidth: dayRow.events.length > dayRow.shown ? 36 : 0
                            readonly property real chipWidth: dayRow.shown > 0
                                ? (eventRow.width - eventRow.overflowWidth - eventRow.spacing * (dayRow.shown - (eventRow.overflowWidth > 0 ? 0 : 1))) / dayRow.shown
                                : 0

                            StyledText {
                                visible: dayRow.events.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: dayRow.today ? Translation.tr("Nothing planned") : "—"
                                color: dayRow.today ? WidgetColorScheme.textColorOnPillFill : WidgetColorScheme.subtextColorOnBg
                                font.pixelSize: Appearance.font.pixelSize.small
                            }

                            Repeater {
                                model: dayRow.events.slice(0, dayRow.shown)

                                delegate: Rectangle {
                                    id: eventChip
                                    required property var modelData
                                    width: eventRow.chipWidth
                                    height: 32
                                    radius: Appearance.rounding.full
                                    color: dayRow.today ? WidgetColorScheme.cardBgColor : WidgetColorScheme.pillBgColor

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.right: parent.right
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 6

                                        StyledText {
                                            id: timeLabel
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: cal.eventTime(eventChip.modelData)
                                            color: WidgetColorScheme.accentColor
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smallest + 1
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - timeLabel.width - parent.spacing
                                            text: eventChip.modelData.content || Translation.tr("Untitled")
                                            color: WidgetColorScheme.textColorOnBg
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: eventRow.overflowWidth > 0
                                width: eventRow.overflowWidth
                                height: 32
                                radius: Appearance.rounding.full
                                color: WidgetColorScheme.accentColor

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "+" + (dayRow.events.length - dayRow.shown)
                                    color: WidgetColorScheme.onAccentColor
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
