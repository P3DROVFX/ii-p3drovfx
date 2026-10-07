import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Date Banner (2x1). An editorial card: the weekday as a headline that fills
 * the width, over a two-by-two grid of monospace captions and values (date,
 * week, day of the year, next event) like an event poster's fact sheet.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "calendar_date_banner"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "calendar_date_banner")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.calendar_date_banner ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    readonly property bool italicHeadline: root.options?.italicHeadline ?? true
    readonly property bool showNextEvent: root.options?.showNextEvent ?? true

    // -- Geometry (design units) --
    readonly property real designWidth: 492
    readonly property real designHeight: 240
    readonly property real padding: 20
    readonly property real headlineMaxSize: 150
    readonly property real factGap: 12

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    CalendarWidgetData {
        id: cal
    }

    readonly property var facts: {
        const today = cal.today;
        const list = [
            { label: Translation.tr("Date"), value: cal.locale.toString(today, "dd MMM yyyy") },
            { label: Translation.tr("Week"), value: String(cal.weekNumber(today)) },
            { label: Translation.tr("Day"), value: Translation.tr("%1 of %2").arg(cal.dayOfYear(today)).arg(cal.daysInYear(today)) }
        ];
        if (root.showNextEvent) {
            const next = cal.nextEvent;
            list.push({
                label: Translation.tr("Next"),
                value: next ? `${next.content} · ${cal.eventTime(next)}` : Translation.tr("Free week")
            });
        } else {
            const yearDone = Math.round(cal.dayOfYear(today) / cal.daysInYear(today) * 100);
            list.push({ label: Translation.tr("Year"), value: Translation.tr("%1% done").arg(yearDone) });
        }
        return list;
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

            Text {
                id: headline
                // Fills what the fact sheet leaves; Fit sizes it to that box.
                x: root.padding
                anchors.top: parent.top
                anchors.topMargin: root.padding - 10
                anchors.bottom: factGrid.top
                anchors.bottomMargin: 2
                width: parent.width - root.padding * 2
                text: cal.locale.toString(cal.today, "dddd").toUpperCase()
                color: WidgetColorScheme.accentColor
                font.family: Appearance.font.family.main
                font.pixelSize: root.headlineMaxSize
                font.variableAxes: root.italicHeadline
                    ? ({ "wght": 900, "wdth": 82, "slnt": -10, "ROND": 0, "opsz": 144 })
                    : ({ "wght": 900, "wdth": 82, "ROND": 100, "opsz": 144 })
                fontSizeMode: Text.Fit
                minimumPixelSize: 40
                verticalAlignment: Text.AlignVCenter
                renderType: Text.QtRendering
            }

            Grid {
                id: factGrid
                x: root.padding
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.padding - 2
                width: parent.width - root.padding * 2
                columns: 2
                columnSpacing: root.factGap * 2
                rowSpacing: root.factGap

                Repeater {
                    model: root.facts

                    delegate: Column {
                        required property var modelData
                        width: (factGrid.width - factGrid.columnSpacing) / 2
                        spacing: 1

                        StyledText {
                            width: parent.width
                            text: modelData.label
                            color: WidgetColorScheme.subtextColorOnBg
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                        }
                        StyledText {
                            width: parent.width
                            text: modelData.value
                            color: WidgetColorScheme.textColorOnBg
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
