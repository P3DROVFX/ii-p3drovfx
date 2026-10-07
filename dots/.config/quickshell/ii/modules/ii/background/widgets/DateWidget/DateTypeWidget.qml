pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/*
 * Date Type (2x1). Text only. The weekday is set letter by letter with the
 * variable font's axes ramping across the word - heavy and wide at one end,
 * hairline and condensed at the other - framed by small auxiliary lines: the
 * date and week in monospace above, the long date in italic and the day of
 * the year below.
 */
AbstractBackgroundWidget {
    id: root

    configEntryName: "calendar_date_type"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom"
                    || root.lockBehavior === "center"
                    || root.lockBehavior === "lockOnly"
                    || (Config.options.lock.centerWidget === "calendar_date_type")

    opacity: {
        if (root.lockBehavior === "lockOnly")
            return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked)
            return 0;
        return 1;
    }

    readonly property var options: Config.options?.background?.widgets?.calendar_date_type ?? ({})
    readonly property real contentScale: (root.options?.widgetSize ?? 100) / 100.0
    // true: heavy first letter thinning out; false: the other way round.
    readonly property bool heavyFirst: root.options?.heavyFirst ?? true
    readonly property bool accentWord: root.options?.accentWord ?? false

    // -- Geometry (design units) --
    readonly property real designWidth: 492
    readonly property real designHeight: 240
    readonly property real padding: 22
    readonly property real wordMaxHeight: 128
    // The ramp's ends.
    readonly property real heavyWeight: 920
    readonly property real lightWeight: 120
    readonly property real wideWidth: 125
    readonly property real narrowWidth: 45
    readonly property real measureSize: 100

    implicitWidth: root.designWidth * root.contentScale
    implicitHeight: root.designHeight * root.contentScale

    CalendarWidgetData {
        id: cal
    }

    readonly property string word: cal.locale.toString(cal.today, "dddd")
    readonly property var letters: root.word.split("")

    function axesAt(index) {
        const n = Math.max(1, root.letters.length - 1);
        const t = root.heavyFirst ? index / n : 1 - index / n;
        return {
            "wght": Math.round(root.heavyWeight + (root.lightWeight - root.heavyWeight) * t),
            "wdth": Math.round(root.wideWidth + (root.narrowWidth - root.wideWidth) * t),
            "ROND": 100,
            "opsz": 144
        };
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

            // -- Top line --
            StyledText {
                id: topLeft
                x: root.padding
                y: root.padding - 2
                text: cal.locale.toString(cal.today, "dd.MM.yyyy")
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.5
            }
            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.verticalCenter: topLeft.verticalCenter
                text: Translation.tr("WEEK %1").arg(cal.weekNumber(cal.today))
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.5
            }

            // The word at a fixed size, never shown: its width sizes the real one.
            // Transparent rather than invisible - a Row skips invisible children,
            // which would measure nothing.
            Row {
                id: measure
                opacity: 0
                Repeater {
                    model: root.letters
                    delegate: Text {
                        required property string modelData
                        required property int index
                        text: modelData
                        font.family: Appearance.font.family.main
                        font.pixelSize: root.measureSize
                        font.variableAxes: root.axesAt(index)
                    }
                }
            }

            // -- The weekday --
            Row {
                id: wordRow
                readonly property real fitSize: Math.floor(Math.min(
                    root.measureSize * (card.width - root.padding * 2) / Math.max(1, measure.implicitWidth),
                    root.wordMaxHeight))
                x: root.padding - 2
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -4

                Repeater {
                    model: root.letters
                    delegate: Text {
                        required property string modelData
                        required property int index
                        text: modelData
                        color: root.accentWord ? WidgetColorScheme.accentColor : WidgetColorScheme.textColorOnBg
                        font.family: Appearance.font.family.main
                        font.pixelSize: wordRow.fitSize
                        font.variableAxes: root.axesAt(index)
                        renderType: Text.QtRendering
                    }
                }
            }

            // -- Bottom line --
            StyledText {
                id: longDate
                x: root.padding
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.padding - 4
                width: parent.width * 0.6
                text: cal.locale.toString(cal.today, "d MMMM")
                color: root.accentWord ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.accentColor
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.huge
                font.variableAxes: ({ "wght": 480, "wdth": 100, "slnt": -10, "ROND": 0 })
                elide: Text.ElideRight
            }
            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.baseline: longDate.baseline
                text: Translation.tr("%1/%2").arg(cal.dayOfYear(cal.today)).arg(cal.daysInYear(cal.today))
                color: WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
