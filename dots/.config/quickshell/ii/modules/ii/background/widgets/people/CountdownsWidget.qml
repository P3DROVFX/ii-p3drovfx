pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Countdowns (2x1): the dates you are waiting for - a trip, an anniversary,
 * a deadline - set in this widget's Settings page, each once or every year.
 * The nearest one takes the left: its days in the widest, heaviest cut of
 * the font, its name slanted under them, and the weeks left as a field of
 * dots, one per week. The next three wait on the right as rows.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "people_countdowns"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 18
    readonly property date now: DateTime.clock.date
    // [{ title, date, days }] soonest first; past one-off dates drop out.
    readonly property var events: {
        const start = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate());
        const out = [];
        for (const entry of Array.from(root.options?.events ?? [])) {
            const parts = String(entry?.date ?? "").split("-").map(Number);
            if (parts.length !== 3 || parts.some(n => !isFinite(n)))
                continue;
            let date = new Date(parts[0], parts[1] - 1, parts[2]);
            if (entry.yearly === true) {
                date = new Date(start.getFullYear(), parts[1] - 1, parts[2]);
                if (date < start)
                    date = new Date(start.getFullYear() + 1, parts[1] - 1, parts[2]);
            }
            if (date < start)
                continue;
            out.push({ title: String(entry.title || Translation.tr("Untitled")), date: date,
                       days: Math.round((date.getTime() - start.getTime()) / 86400000) });
        }
        return out.sort((a, b) => a.days - b.days);
    }
    readonly property var hero: root.events.length > 0 ? root.events[0] : null

    // ── The nearest ──
    Item {
        id: heroBox
        x: root.padding
        y: root.padding
        width: 246
        height: root.designHeight - root.padding * 2

        StyledText {
            id: heroDays
            visible: root.hero !== null
            x: -3
            y: -14
            width: parent.width
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 40
            text: root.hero ? (root.hero.days === 0 ? Translation.tr("Today") : String(root.hero.days)) : ""
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 96
            font.variableAxes: ({ "wght": 900, "wdth": 151, "ROND": 100 })
        }
        // Nothing to count yet: an empty calendar waiting.
        MaterialShape {
            id: emptyShape
            visible: root.hero === null
            y: 6
            width: 96
            height: 96
            shapeString: "Cookie7Sided"
            color: WidgetColorScheme.pillBgColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "event_upcoming"
                iconSize: 40
                color: WidgetColorScheme.subtextColorOnBg
            }
        }

        StyledText {
            id: heroTitle
            y: root.hero ? heroDays.y + heroDays.height - 12 : emptyShape.y + emptyShape.height + 12
            width: parent.width
            elide: Text.ElideRight
            text: root.hero ? (root.hero.days === 1 ? Translation.tr("day until %1") : Translation.tr("days until %1")).arg(root.hero.title)
                            : Translation.tr("Add dates in Settings")
            color: WidgetColorScheme.accentColor
            font.family: Appearance.font.family.main
            font.pixelSize: 17
            font.variableAxes: ({ "wght": 550, "wdth": 100, "slnt": -10, "ROND": 100 })
        }

        // One dot per week left.
        Flow {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: 5
            visible: root.hero !== null

            Repeater {
                model: root.hero ? Math.min(52, Math.ceil(root.hero.days / 7)) : 0
                delegate: Rectangle {
                    required property int index
                    width: 12
                    height: 12
                    radius: 6
                    color: index === 0 ? WidgetColorScheme.accentColor : WidgetColorScheme.pillBgColor
                }
            }
        }
    }

    // ── The ones after ──
    Column {
        anchors.left: heroBox.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding
        spacing: 8

        Repeater {
            model: root.events.slice(1, 4)

            delegate: Rectangle {
                id: row
                required property var modelData
                width: parent.width
                height: 60
                radius: Appearance.rounding.normal
                color: WidgetColorScheme.pillBgColor

                StyledText {
                    id: rowDays
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(row.modelData.days)
                    color: WidgetColorScheme.textColorOnBg
                    font.family: Appearance.font.family.main
                    font.pixelSize: 30
                    font.variableAxes: ({ "wght": 760, "wdth": 50, "ROND": 100 })
                }
                Column {
                    anchors.left: rowDays.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -2

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.modelData.title
                        color: WidgetColorScheme.textColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: 13
                        font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                    }
                    StyledText {
                        text: Qt.locale().toString(row.modelData.date, "d MMM yyyy")
                        color: WidgetColorScheme.subtextColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
