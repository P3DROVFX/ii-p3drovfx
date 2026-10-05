import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import "CalendarAgenda.js" as CalendarAgenda

/**
 * The calendar panel: today as a column of events (all-day ones as chips on
 * top, the one happening now on the primary container) and the next days
 * that have something on them.
 */
ColumnLayout {
    id: panel

    property var host: null

    readonly property date now: DateTime.clock.date
    readonly property var events: CalendarService.visibleEvents ?? []
    readonly property var today: CalendarAgenda.dayEvents(panel.events, panel.now)
    readonly property var allDay: panel.today.filter(item => item.allDay)
    readonly property var timed: panel.today.filter(item => !item.allDay)
    readonly property var later: CalendarAgenda.nextDays(panel.events, panel.now, 3)
    readonly property string timeFormat: Config.options?.time?.format ?? "hh:mm"

    spacing: 6

    component EventRow: Rectangle {
        id: row
        property var item
        property bool first: false
        readonly property bool happening: CalendarAgenda.isHappening(row.item, panel.now)
        readonly property bool past: row.item.end <= panel.now
        readonly property color colContent: row.happening ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurface
        Layout.fillWidth: true
        implicitHeight: 56
        radius: row.first ? ClockStyle.radiusNormal : ClockStyle.radiusSmall
        color: row.happening ? ClockStyle.colPrimaryContainer : ClockStyle.colField
        opacity: row.past ? 0.55 : 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10
            Rectangle {
                Layout.fillHeight: true
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                implicitWidth: 4
                radius: 2
                color: row.item.event.color ?? ClockStyle.colPrimary
            }
            ColumnLayout {
                Layout.preferredWidth: 52
                spacing: -2
                StyledText {
                    text: row.item.allDay ? Translation.tr("All day") : Qt.formatDateTime(row.item.start, panel.timeFormat)
                    color: row.colContent
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: row.item.allDay ? ClockStyle.textSmall : 18
                }
                StyledText {
                    visible: !row.item.allDay
                    text: Qt.formatDateTime(row.item.end, panel.timeFormat)
                    color: row.colContent
                    opacity: 0.7
                    font.pixelSize: ClockStyle.textSmall
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: row.item.event.content
                    color: row.colContent
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: String(row.item.event.location ?? "")
                    color: row.colContent
                    opacity: 0.7
                    font.pixelSize: ClockStyle.textSmall
                    elide: Text.ElideRight
                }
            }
        }
    }

    StyledText {
        Layout.leftMargin: 4
        text: Translation.tr("Today")
        color: ClockStyle.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Bold
    }

    Flow {
        Layout.fillWidth: true
        visible: panel.allDay.length > 0
        spacing: 6
        Repeater {
            model: panel.allDay
            delegate: Rectangle {
                required property var modelData
                width: Math.min(panel.width, chipText.implicitWidth + 24)
                height: 30
                radius: 15
                color: ClockStyle.colTertiaryContainer
                StyledText {
                    id: chipText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, panel.width - 24)
                    text: modelData.event.content
                    color: ClockStyle.colOnTertiaryContainer
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }
    }

    Repeater {
        model: panel.timed
        delegate: EventRow {
            required property var modelData
            required property int index
            item: modelData
            first: index === 0
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: panel.today.length === 0
        implicitHeight: 64
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        StyledText {
            anchors.centerIn: parent
            text: CalendarService.khalAvailable ? Translation.tr("Nothing on today") : Translation.tr("No calendar connected")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
        }
    }

    Repeater {
        model: panel.later
        delegate: ColumnLayout {
            id: dayGroup
            required property var modelData
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 4
            StyledText {
                Layout.leftMargin: 4
                text: Qt.formatDate(dayGroup.modelData.day, "dddd, d MMM")
                color: ClockStyle.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
            }
            Repeater {
                model: dayGroup.modelData.events.slice(0, 4)
                delegate: EventRow {
                    required property var modelData
                    required property int index
                    item: modelData
                    first: index === 0
                }
            }
        }
    }
}
