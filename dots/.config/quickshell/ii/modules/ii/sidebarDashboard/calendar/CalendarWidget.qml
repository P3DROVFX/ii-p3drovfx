import QtQuick
import QtQuick.Layouts
import "calendar_layout.js" as CalendarLayout
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    property int monthShift: 0
    property int _entranceKey: 0
    property int entranceTrigger: -1
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0, Config.options.time.firstDayOfWeek)

    onEntranceTriggerChanged: {
        _entranceKey++;
    }

    onMonthShiftChanged: _entranceKey++

    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 5
    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown)
                monthShift++;
            else if (event.key === Qt.Key_PageUp)
                monthShift--;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (event.angleDelta.y > 0)
                monthShift--;
            else if (event.angleDelta.y < 0)
                monthShift++;
        }
    }

    ColumnLayout {
        id: calendarColumn

        anchors.centerIn: parent
        spacing: 5

        // Calendar header
        RowLayout {
            Layout.fillWidth: true
            spacing: 5

            CalendarHeaderButton {
                clip: true
                buttonText: `${monthShift != 0 ? "• " : ""}${viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                tooltipText: (monthShift === 0) ? "" : Translation.tr("Jump to current month")
                downAction: () => {
                    monthShift = 0;
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }

            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift--;
                }

                contentItem: MaterialSymbol {
                    text: "chevron_left"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }

            }

            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    monthShift++;
                }

                contentItem: MaterialSymbol {
                    text: "chevron_right"
                    iconSize: Appearance.font.pixelSize.larger
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer1
                }

            }

        }

        // Week days row
        RowLayout {
            id: weekDaysRow

            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
            spacing: 5

            Repeater {
                id: buttonRepeater
                model: CalendarLayout.weekDays.map((_, i) => {
                    return CalendarLayout.weekDays[(i + Config.options.time.firstDayOfWeek) % 7];
                })

                delegate: CalendarDayButton {
                    day: Translation.tr(modelData.day)
                    isToday: modelData.today
                    bold: true
                    enabled: false
                    taskList: []
                }

            }

        }

        // Real week rows
        Repeater {
            id: calendarRows

            // model: calendarLayout
            model: 6

            delegate: RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: 5

                Repeater {
                    model: Array(7).fill(modelData)

                    delegate: CalendarDayButton {
                        day: calendarLayout[modelData][index].day
                        isToday: calendarLayout[modelData][index].today
                        taskList: CalendarService.getTasksByDate(new Date(calendarLayout[modelData][index].year, calendarLayout[modelData][index].month, calendarLayout[modelData][index].day))
                        gridRow: modelData
                        gridCol: index
                        entranceKey: calendarColumn.parent._entranceKey
                    }

                }

            }

        }

    }

}