pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Totem (1x2): three cut-outs stacked off-centre, each in its own colour
 * role. An accent arch holds the hour, a twelve-sided cookie in the inner shape colour
 * leans out from under it with the minutes (it morphs round under the
 * pointer), and a capsule at the foot carries the date over a row of the
 * week, today stretched into a filled pill with its initial. The wallpaper
 * shows on the open side of each piece.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "clock_totem"
    showCard: false
    designWidth: 240
    designHeight: 492

    // -- Geometry (design units) --
    readonly property real padding: 12
    readonly property real archSize: 204
    readonly property real minutesSize: 172
    // How far the minutes cookie climbs under the arch.
    readonly property real overlap: 34
    readonly property real weekHeight: 104

    readonly property date now: DateTime.clock.date
    readonly property bool showWeek: root.options?.showWeek ?? true
    readonly property real minutesY: root.padding + root.archSize - root.overlap

    HoverHandler {
        id: hover
        enabled: root.actionsEnabled
    }

    ShapeClockSurfaces {
        anchors.fill: parent

        // Under the arch, so the arch's flat foot cuts across it.
        MaterialShape {
            id: minutesShape
            x: root.designWidth - root.padding - root.minutesSize
            y: root.minutesY
            implicitSize: root.minutesSize
            shapeString: hover.hovered ? "Circle" : "Cookie12Sided"
            color: WidgetColorScheme.innerShapeColor
        }

        MaterialShape {
            id: arch
            x: root.padding
            y: root.padding
            implicitSize: root.archSize
            shapeString: "Arch"
            color: WidgetColorScheme.accentColor
        }

        Rectangle {
            id: week
            visible: root.showWeek
            x: root.padding
            y: root.designHeight - root.padding - height
            width: root.designWidth - root.padding * 2
            height: root.weekHeight
            radius: root.pill(48)
            color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
        }
    }

    Column {
        x: arch.x + arch.width / 2 - width / 2
        y: arch.y + arch.height / 2 - height / 2 + 8
        spacing: -12

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.hours
            color: WidgetColorScheme.onAccentColor
            font.family: Appearance.font.family.main
            font.pixelSize: 150
            font.variableAxes: ({ "wght": 900, "wdth": 35, "ROND": 100, "opsz": 144 })
            renderType: Text.QtRendering
        }
        StyledText {
            visible: DateTime.use12HourClock
            anchors.horizontalCenter: parent.horizontalCenter
            text: DateTime.meridiem.toUpperCase()
            color: WidgetColorScheme.onAccentColor
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.letterSpacing: 1.5
            font.variableAxes: ({ "wght": 700, "wdth": 125 })
        }
    }

    // The part of the cookie below the arch's foot.
    Text {
        readonly property real visibleTop: arch.y + arch.height
        x: minutesShape.x + (minutesShape.width - width) / 2
        y: visibleTop + (minutesShape.y + minutesShape.height - visibleTop - height) / 2
        text: DateTime.minutes
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 84
        font.variableAxes: ({ "wght": 750, "wdth": 110, "ROND": 100, "opsz": 144 })
        renderType: Text.QtRendering
    }

    Item {
        visible: root.showWeek
        x: week.x
        y: week.y
        width: week.width
        height: week.height

        StyledText {
            x: 22
            y: 14
            text: Qt.locale().toString(root.now, "MMMM d").toUpperCase()
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.normal
            font.letterSpacing: 1.2
            font.variableAxes: ({ "wght": 750, "wdth": 115 })
        }

        Row {
            id: days
            readonly property real dot: 22
            readonly property real todayWidth: 50
            readonly property int today: root.now.getDay()
            readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 18 - days.dot - 4
            spacing: (week.width - 36 - days.dot * 6 - days.todayWidth) / 6

            Repeater {
                model: 7
                delegate: Rectangle {
                    id: day
                    required property int index
                    readonly property int weekday: (days.firstDay + index) % 7
                    readonly property bool isToday: day.weekday === days.today
                    // QML's Locale counts days like Date.getDay: Sunday = 0.
                    readonly property string initial: Qt.locale().dayName(day.weekday, Locale.NarrowFormat)
                    anchors.verticalCenter: parent.verticalCenter
                    width: day.isToday ? days.todayWidth : days.dot
                    height: day.isToday ? days.dot + 8 : days.dot
                    radius: root.pill(height)
                    color: day.isToday ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor

                    StyledText {
                        anchors.centerIn: parent
                        text: day.initial.toUpperCase()
                        color: day.isToday ? WidgetColorScheme.onAccentColor : WidgetColorScheme.subtextColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: day.isToday ? Appearance.font.pixelSize.normal : 10
                        font.variableAxes: ({ "wght": day.isToday ? 800 : 600, "wdth": 110 })
                    }
                }
            }
        }
    }
}
