pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.usage.limits

/**
 * Which day, week or month is on screen, and the arrows that walk between them, tinted
 * with the hero pane they sit on.
 *
 * Shared by the App usage and Battery pages rather than written twice: they are two
 * readings of the same period, and a stepper that behaved differently in one of them
 * would read as a bug in the data. Nothing here changes its own state — moving the
 * period also has to clear whatever the page had narrowed to, so this asks and the
 * page decides.
 */
GridLayout {
    id: root

    property string granularity: "day"
    /// Periods back from the current one: 0 is today / this week / this month.
    property int periodOffset: 0
    property color colContent: ClockStyle.colOnPrimary
    property color colPane: ClockStyle.colPrimary

    signal granularityPicked(string key)
    signal stepped(int delta)
    signal periodReset()

    /// Calendar periods rather than a rolling window: a week is always the same seven
    /// days however long ago it is asked about, which is what makes two comparable.
    readonly property var granularities: [
        { key: "day", name: Translation.tr("Day") },
        { key: "week", name: Translation.tr("Week") },
        { key: "month", name: Translation.tr("Month") }
    ]
    // The arrows stop where the data does rather than walking into periods retention
    // has already dropped, and never into the future.
    readonly property bool canGoBack: AppStats.hasEarlierPeriod(root.granularity, root.periodOffset)
    readonly property bool canGoForward: root.periodOffset < 0

    columns: root.width >= 470 ? 2 : 1
    columnSpacing: ClockStyle.gap
    rowSpacing: ClockStyle.gapSmall

    RowLayout {
        spacing: ClockStyle.gapTiny

        Repeater {
            model: root.granularities

            LimitsTintButton {
                id: chip
                required property var modelData
                label: chip.modelData.name
                height_: 34
                colContent: root.colContent
                colSolidContent: root.colPane
                solid: root.granularity === chip.modelData.key
                onClicked: root.granularityPicked(chip.modelData.key)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.alignment: root.columns === 2 ? Qt.AlignRight : Qt.AlignLeft
        spacing: ClockStyle.gapTiny

        ClockCardAction {
            symbol: "chevron_left"
            tip: Translation.tr("Previous period")
            colContent: root.colContent
            enabled: root.canGoBack
            onClicked: root.stepped(-1)
        }

        ColumnLayout {
            Layout.minimumWidth: 110
            Layout.fillWidth: root.columns === 1
            spacing: -2

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: AppStats.periodLabel(root.granularity, root.periodOffset)
                font.pixelSize: ClockStyle.textNormal + 1
                font.weight: Font.Bold
                color: root.colContent
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: AppStats.periodRangeLabel(root.granularity, root.periodOffset)
                font.pixelSize: ClockStyle.textSmall
                color: root.colContent
                opacity: 0.75
            }
        }

        ClockCardAction {
            symbol: "chevron_right"
            tip: Translation.tr("Next period")
            colContent: root.colContent
            enabled: root.canGoForward
            onClicked: root.stepped(1)
        }

        LimitsTintButton {
            visible: root.periodOffset < 0
            symbol: "today"
            label: Translation.tr("Now")
            height_: 34
            colContent: root.colContent
            onClicked: root.periodReset()
        }
    }
}
