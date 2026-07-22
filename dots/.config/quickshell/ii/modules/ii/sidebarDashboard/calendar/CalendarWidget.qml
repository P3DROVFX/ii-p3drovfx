import QtQuick
import QtQuick.Layouts
import "calendar_layout.js" as CalendarLayout
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    property int monthShift: 0
    property int _entranceKey: 0
    property int entranceTrigger: -1
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0, Config.options.time.firstDayOfWeek)

    property real _monthTextOpacity: 1.0
    property real _monthTextTranslateX: 0
    property int _lastDirection: 1 // 1 = next (slide left), -1 = prev (slide right)

    onEntranceTriggerChanged: {
        _entranceKey++;
    }

    function changeMonth(delta) {
        if (delta === 0) return;
        _lastDirection = delta > 0 ? 1 : -1;
        _monthTextOpacity = 0.0;
        _monthTextTranslateX = _lastDirection * 25;
        monthShift += delta;
        monthTextAnim.stop();
        monthTextAnim.start();
    }

    SequentialAnimation {
        id: monthTextAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "_monthTextOpacity"; from: 0.0; to: 1.0; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "_monthTextTranslateX"; from: root._lastDirection * 25; to: 0; duration: 280; easing.type: Easing.OutCubic }
        }
    }

    onMonthShiftChanged: _entranceKey++

    width: calendarColumn.width
    implicitHeight: calendarColumn.height + 5
    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageDown)
                changeMonth(1);
            else if (event.key === Qt.Key_PageUp)
                changeMonth(-1);
            event.accepted = true;
        }
    }

    property real _accumulatedWheelDelta: 0
    property bool _canScrollWheel: true

    Timer {
        id: wheelCooldownTimer
        interval: 400
        repeat: false
        onTriggered: {
            root._canScrollWheel = true;
            root._accumulatedWheelDelta = 0;
        }
    }

    MouseArea {
        anchors.fill: parent
        onWheel: (event) => {
            if (!root._canScrollWheel) return;
            
            root._accumulatedWheelDelta += event.angleDelta.y;
            if (Math.abs(root._accumulatedWheelDelta) >= 360) {
                const step = root._accumulatedWheelDelta > 0 ? -1 : 1;
                root._canScrollWheel = false;
                root._accumulatedWheelDelta = 0;
                wheelCooldownTimer.restart();
                root.changeMonth(step);
            }
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
                    root.changeMonth(-monthShift);
                }
                contentItem: StyledText {
                    text: parent.buttonText
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                    opacity: root._monthTextOpacity
                    transform: Translate {
                        x: root._monthTextTranslateX
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }

            CalendarHeaderButton {
                forceCircle: true
                downAction: () => {
                    root.changeMonth(-1);
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
                    root.changeMonth(1);
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