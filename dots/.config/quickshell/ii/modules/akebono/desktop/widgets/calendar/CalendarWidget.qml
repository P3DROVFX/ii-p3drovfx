pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.akebono.desktop.widgets
import "../../../../common/functions/calendar_layout.js" as CalendarLayout

WidgetCard {
    id: root
    minSize: 220

    property int monthShift: 0
    readonly property date viewingDate: CalendarLayout.getDateInXMonthsTime(root.monthShift)
    readonly property var weeks: CalendarLayout.getCalendarLayout(root.viewingDate, root.monthShift === 0)
    readonly property var days: root.weeks.reduce((all, week) => all.concat(week), [])
    readonly property real cellSize: Math.min(grid.width / 7, grid.height / 6)
    readonly property int dayFontSize: Math.max(Appearance.font.pixelSize.smallest, Math.min(Appearance.font.pixelSize.large, Math.round(root.cellSize * 0.45)))

    WheelHandler {
        onWheel: event => root.monthShift += (event.angleDelta.y > 0 ? -1 : 1)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.viewingDate.toLocaleDateString(Qt.locale(), "yyyy")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButton {
                visible: root.monthShift !== 0
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                onClicked: root.monthShift = 0

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: "today"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        GridLayout {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            columnSpacing: 0
            rowSpacing: 0

            Repeater {
                model: CalendarLayout.weekDays

                StyledText {
                    id: dayHeader
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.cellSize * 0.7
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: dayHeader.modelData.day
                    font.pixelSize: Math.max(Appearance.font.pixelSize.smallest, root.dayFontSize - 3)
                    color: Appearance.colors.colSubtext
                }
            }

            Repeater {
                model: root.days

                Item {
                    id: dayCell
                    required property var modelData
                    readonly property bool isToday: dayCell.modelData.today === 1
                    readonly property bool otherMonth: dayCell.modelData.today === -1
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.centerIn: parent
                        visible: dayCell.isToday
                        width: Math.min(parent.width, parent.height)
                        height: width
                        radius: width / 2
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: dayCell.modelData.day
                        font.pixelSize: root.dayFontSize
                        font.weight: dayCell.isToday ? Font.DemiBold : Font.Normal
                        color: dayCell.isToday ? Appearance.colors.colOnPrimary : (dayCell.otherMonth ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer1)
                        opacity: dayCell.otherMonth ? 0.45 : 1
                    }
                }
            }
        }
    }
}
