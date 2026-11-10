pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Next Holiday (1x1): the next public holiday of your country (Settings →
 * Calendar → Holidays) as a tear-off calendar page - the month on a band
 * across the top, the day huge below - with the days still to wait beside
 * it and the holiday's name along the foot.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "people_holiday"

    readonly property real padding: 18
    readonly property date now: DateTime.clock.date
    // { date, name, days } of the first holiday from today on, within a year.
    readonly property var next: {
        void Holidays.byDayKey;
        const start = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate());
        for (let i = 0; i < 366; i++) {
            const day = new Date(start.getFullYear(), start.getMonth(), start.getDate() + i);
            const name = Holidays.holidayNameForDate(day);
            if (name.length > 0)
                return { date: day, name: name, days: i };
        }
        return null;
    }

    Component.onCompleted: {
        Holidays.ensureYear(root.now.getFullYear());
        Holidays.ensureYear(root.now.getFullYear() + 1);
    }

    // ── The page ──
    Rectangle {
        id: page
        x: root.padding
        y: root.padding
        width: 110
        height: 124
        radius: Appearance.rounding.normal
        color: WidgetColorScheme.pillBgColor
        clip: true

        Rectangle {
            id: band
            width: parent.width
            height: 34
            topLeftRadius: page.radius
            topRightRadius: page.radius
            color: WidgetColorScheme.accentColor

            StyledText {
                anchors.centerIn: parent
                text: root.next ? Qt.locale().toString(root.next.date, "MMM").replace(".", "").toUpperCase() : "—"
                color: WidgetColorScheme.onAccentColor
                font.family: Appearance.font.family.main
                font.pixelSize: 15
                font.letterSpacing: 2
                font.variableAxes: ({ "wght": 800, "wdth": 125, "ROND": 0 })
            }
        }
        // The two binding holes of a desk calendar.
        Repeater {
            model: 2
            delegate: Rectangle {
                required property int index
                x: page.width * (index === 0 ? 0.28 : 0.72) - 4
                y: 6
                width: 8
                height: 8
                radius: 4
                color: root.cardColor
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: band.bottom
            anchors.topMargin: -6
            text: root.next ? String(root.next.date.getDate()) : "?"
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 72
            font.variableAxes: ({ "wght": 640, "wdth": 75, "ROND": 100 })
        }
    }

    // ── How long ──
    Column {
        anchors.left: page.right
        anchors.leftMargin: 14
        anchors.verticalCenter: page.verticalCenter
        spacing: -6

        StyledText {
            text: !root.next ? "" : root.next.days === 0 ? Translation.tr("Today") : String(root.next.days)
            color: root.next?.days === 0 ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: root.next?.days === 0 ? 28 : 48
            font.variableAxes: ({ "wght": 300, "wdth": 110, "ROND": 100 })
        }
        StyledText {
            visible: (root.next?.days ?? 0) > 0
            text: root.next?.days === 1 ? Translation.tr("day to go") : Translation.tr("days to go")
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 12
            font.variableAxes: ({ "wght": 500, "wdth": 100, "slnt": -10, "ROND": 100 })
        }
    }

    StyledText {
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        width: root.designWidth - root.padding * 2
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        lineHeight: 0.9
        text: root.next?.name ?? (Holidays.enabled ? Translation.tr("Loading holidays…") : Translation.tr("Holidays are off"))
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: 19
        font.variableAxes: ({ "wght": 760, "wdth": 85, "ROND": 100 })
    }
}
