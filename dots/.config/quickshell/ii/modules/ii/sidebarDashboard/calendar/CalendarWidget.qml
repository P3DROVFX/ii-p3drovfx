import QtQuick
import QtQuick.Layouts
import "calendar_layout.js" as CalendarLayout
import "CalendarEventIndex.js" as CalendarEventIndex
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    property int monthShift: 0
    property int _entranceKey: 0
    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0, Config.options.time.firstDayOfWeek)

    // Build one index when the event collection changes instead of scanning
    // every event independently from each of the 42 day delegates.
    readonly property var tasksByDate: CalendarEventIndex.groupEvents(
        CalendarService.events,
        CalendarService.khalAvailable
    )

    function tasksForDate(year, month, day) {
        return CalendarEventIndex.tasksForDate(root.tasksByDate, year, month, day);
    }

    onEntranceTriggerChanged: {
        if (entranceAnimationsEnabled && entranceTrigger >= 0)
            _entranceKey++;
    }

    onMonthShiftChanged: {
        if (entranceAnimationsEnabled)
            _entranceKey++;
    }

    property real _monthTextOpacity: 1.0
    property real _monthTextTranslateX: 0
    property int _lastDirection: 1 // 1 = next (slide left), -1 = prev (slide right)

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

    width: Math.max(calendarHeader.implicitWidth, calendarGridColumn.implicitWidth)
    implicitHeight: root.headerHeight
        + root.calendarSpacing
        + calendarGridColumn.implicitHeight
        + root.calendarSpacing

    // A month is a fixed 6 week rows plus the weekday header, so the only way to
    // fit a shorter box is a smaller cell. Whoever hosts the widget sizes it;
    // this reads that size back and never grows past the natural 38px.
    readonly property real headerHeight: 30
    readonly property real calendarSpacing: 5
    readonly property real cellSize: {
        if (root.height <= 0)
            return 38;
        const gridViewportHeight = root.height
            - root.headerHeight
            - root.calendarSpacing * 2;
        const forRows = gridViewportHeight - calendarGridColumn.spacing * 6;
        return Math.max(26, Math.min(38, forRows / 7));
    }
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

    // The controls share the top line with the bottom group's collapse button.
    // The month grid gets its own viewport so extra fill height is distributed
    // around the grid instead of pushing the controls away from the top.
    RowLayout {
        id: calendarHeader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: root.calendarSpacing

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

    Item {
        id: calendarGridViewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: calendarHeader.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: root.calendarSpacing
        anchors.bottomMargin: root.calendarSpacing

        ColumnLayout {
            id: calendarGridColumn
            anchors.centerIn: parent
            spacing: root.calendarSpacing

            RowLayout {
                id: weekDaysRow
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: false
                spacing: root.calendarSpacing

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
                        cellSize: root.cellSize
                    }
                }
            }

            Repeater {
                id: calendarRows
                model: 6

                delegate: RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillHeight: false
                    spacing: root.calendarSpacing

                    Repeater {
                        model: Array(7).fill(modelData)

                        delegate: CalendarDayButton {
                            day: calendarLayout[modelData][index].day
                            isToday: calendarLayout[modelData][index].today
                            taskList: root.tasksForDate(
                                calendarLayout[modelData][index].year,
                                calendarLayout[modelData][index].month,
                                calendarLayout[modelData][index].day
                            )
                            gridRow: modelData
                            gridCol: index
                            entranceKey: root._entranceKey
                            entranceAnimationsEnabled: root.entranceAnimationsEnabled
                            cellSize: root.cellSize
                        }
                    }
                }
            }
        }
    }

}
