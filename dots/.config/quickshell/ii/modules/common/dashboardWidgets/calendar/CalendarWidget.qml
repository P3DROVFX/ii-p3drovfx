import QtQuick
import QtQuick.Layouts
import "calendar_layout.js" as CalendarLayout
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    // The same calendar is hosted by the 350px desktop bottom group and by a
    // near-square tablet tile. Only metrics adapt; navigation, event indexing
    // and the day delegates remain one implementation.
    readonly property bool compact: root.width > 0 && root.width < 300
    property int monthShift: 0
    property int entranceTrigger: -1
    property bool keyboardEnabled: root.visible
    property bool showShortcutHints: false
    property bool ctrlPressed: false
    property date selectedDate: new Date()
    readonly property bool hintVisible: root.keyboardEnabled
        && (root.showShortcutHints || root.ctrlPressed) && (root.Window.window?.active ?? false)
    signal dismissPopups()

    onKeyboardEnabledChanged: {
        if (!root.keyboardEnabled) {
            root.ctrlPressed = false;
            root.dismissPopups();
        }
    }
    Connections {
        target: root.Window.window
        function onActiveChanged() {
            root.ctrlPressed = false;
            if (!root.Window.window.active) root.dismissPopups();
        }
    }

    function releaseKey(event) {
        if (event.key === Qt.Key_Control || !(event.modifiers & Qt.ControlModifier))
            root.ctrlPressed = false;
    }

    function selectedButton() {
        const firstWeekday = (new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), 1).getDay()
            + 6 - Config.options.time.firstDayOfWeek + 7) % 7;
        const index = firstWeekday + root.selectedDate.getDate() - 1;
        return calendarRows.itemAt(Math.floor(index / 7))?.days.itemAt(index % 7) ?? null;
    }

    function selectDate(date) {
        root.dismissPopups();
        const today = new Date();
        const targetShift = (date.getFullYear() - today.getFullYear()) * 12 + date.getMonth() - today.getMonth();
        root.changeMonth(targetShift - root.monthShift);
        root.selectedDate = date;
        root.forceActiveFocus();
    }

    function handleKey(event) {
        if (!root.keyboardEnabled) return false;
        root.ctrlPressed = event.key === Qt.Key_Control || !!(event.modifiers & Qt.ControlModifier);
        const ctrl = event.modifiers === Qt.ControlModifier;
        const plain = event.modifiers === Qt.NoModifier;
        if (!plain && !ctrl) return false;
        if ((plain && event.key === Qt.Key_PageUp) || (ctrl && event.key === Qt.Key_Left)) {
            root.changeMonth(-1);
            root.forceActiveFocus();
        } else if ((plain && event.key === Qt.Key_PageDown) || (ctrl && event.key === Qt.Key_Right)) {
            root.changeMonth(1);
            root.forceActiveFocus();
        } else if (event.key === Qt.Key_Home) {
            root.selectDate(new Date());
        } else if (plain && (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
            const delta = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : event.key === Qt.Key_Up ? -7 : 7;
            root.selectDate(new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), root.selectedDate.getDate() + delta));
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || (plain && event.key === Qt.Key_Space)) {
            if (!event.isAutoRepeat) {
                const button = root.selectedButton();
                const wasPinned = button?.popupPinned ?? false;
                root.dismissPopups();
                if (!wasPinned) button?.togglePopup();
            }
        } else if (plain && event.key === Qt.Key_Escape) {
            let open = false;
            for (let row = 0; row < calendarRows.count; row++) {
                const days = calendarRows.itemAt(row)?.days;
                for (let col = 0; col < (days?.count ?? 0); col++)
                    open = (days.itemAt(col)?.showPopup ?? false) || open;
            }
            if (!open) return false;
            root.dismissPopups();
        } else return false;
        return true;
    }
    property int _entranceKey: 0
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations

    property var viewingDate: CalendarLayout.getDateInXMonthsTime(monthShift)
    property var calendarLayout: CalendarLayout.getCalendarLayout(viewingDate, monthShift === 0, Config.options.time.firstDayOfWeek)

    // CalendarService already owns the shared per-day index. Reusing it avoids
    // a second map and keeps optimistic events visible in this widget too.
    readonly property var tasksByDate: CalendarService.eventsByDay

    function tasksForDate(year, month, day) {
        return CalendarService.eventsForDay(new Date(year, month, day));
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
        root.dismissPopups();
        const nextMonth = CalendarLayout.getDateInXMonthsTime(root.monthShift + delta);
        const lastDay = new Date(nextMonth.getFullYear(), nextMonth.getMonth() + 1, 0).getDate();
        root.selectedDate = new Date(nextMonth.getFullYear(), nextMonth.getMonth(), Math.min(root.selectedDate.getDate(), lastDay));
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
            NumberAnimation { target: root; property: "_monthTextOpacity"; from: 0.0; to: 1.0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            NumberAnimation { target: root; property: "_monthTextTranslateX"; from: root._lastDirection * 25; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

    implicitWidth: Math.max(calendarHeader.implicitWidth, calendarGridColumn.implicitWidth)
    implicitHeight: root.headerHeight
        + root.calendarSpacing
        + calendarGridColumn.implicitHeight
        + root.calendarSpacing
        + navigationHint.implicitHeight

    // A month is a fixed 6 week rows plus the weekday header, so the only way to
    // fit a shorter box is a smaller cell. Whoever hosts the widget sizes it;
    // this reads that size back and never grows past the natural 38px.
    readonly property real headerHeight: root.compact ? 24 : 30
    readonly property real calendarSpacing: root.compact ? 1 : 5
    readonly property real cellSize: {
        if (root.height <= 0)
            return 38;
        const gridViewportHeight = root.height
            - root.headerHeight
            - root.calendarSpacing * 2 - navigationHint.implicitHeight;
        const forRows = gridViewportHeight - calendarGridColumn.spacing * 6;
        const heightBound = forRows / 7;
        const widthBound = (root.width - root.calendarSpacing * 6) / 7;
        return Math.max(root.compact ? 18 : 16, Math.min(38, heightBound, widthBound));
    }
    Keys.onPressed: event => { event.accepted = root.handleKey(event); }
    Keys.onReleased: event => root.releaseKey(event)

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
            id: todayButton
            Accessible.name: Translation.tr("Today")
            implicitHeight: root.headerHeight
            buttonText: `${monthShift != 0 ? "• " : ""}${viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
            tooltipText: Translation.tr("Today") + " (Ctrl+Home)"
            onClicked: root.selectDate(new Date())
            contentItem: TaskShortcutContent {
                labelText: todayButton.buttonText
                shortcut: "Ctrl + Home"
                showHint: root.hintVisible
                labelPixelSize: root.compact ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.larger
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
            Accessible.name: Translation.tr("Previous month")
            tooltipText: Translation.tr("Previous month") + " (Ctrl+← / PgUp)"
            forceCircle: true
            implicitHeight: root.headerHeight
            implicitWidth: Math.max(root.headerHeight, Appearance.font.pixelSize.smallest * 3)
            onClicked: root.changeMonth(-1)

            contentItem: TaskShortcutContent {
                symbol: "chevron_left"
                shortcut: "Ctrl\n+ ←"
                showHint: root.hintVisible
                iconSize: root.compact ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
        }

        CalendarHeaderButton {
            Accessible.name: Translation.tr("Next month")
            tooltipText: Translation.tr("Next month") + " (Ctrl+→ / PgDn)"
            forceCircle: true
            implicitHeight: root.headerHeight
            implicitWidth: Math.max(root.headerHeight, Appearance.font.pixelSize.smallest * 3)
            onClicked: root.changeMonth(1)

            contentItem: TaskShortcutContent {
                symbol: "chevron_right"
                shortcut: "Ctrl\n+ →"
                showHint: root.hintVisible
                iconSize: root.compact ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer1
            }
        }
    }

    Item {
        id: calendarGridViewport
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: calendarHeader.bottom
        anchors.bottom: navigationHint.top
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
                    property alias days: daysRepeater
                    Layout.fillHeight: false
                    spacing: root.calendarSpacing

                    Repeater {
                        id: daysRepeater
                        model: Array(7).fill(modelData)

                        delegate: CalendarDayButton {
                            id: dayButton
                            readonly property bool selected: isToday !== -1 && Number(day) === root.selectedDate.getDate()
                            keyboardSelected: root.keyboardEnabled && selected
                                && (root.activeFocus || activeFocus || root.hintVisible)
                            showShortcutHint: root.hintVisible && selected && taskList.length > 0
                            activeFocusOnTab: isToday !== -1
                            Accessible.name: new Date(root.viewingDate.getFullYear(), root.viewingDate.getMonth(), Number(day)).toLocaleDateString(Qt.locale(), "dddd, d MMMM yyyy")
                            onActiveFocusChanged: {
                                if (activeFocus && isToday !== -1) {
                                    root.dismissPopups();
                                    root.selectedDate = new Date(root.viewingDate.getFullYear(), root.viewingDate.getMonth(), Number(day));
                                }
                            }
                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: event => { event.accepted = root.handleKey(event); }
                            Keys.onReleased: event => root.releaseKey(event)
                            Connections {
                                target: root
                                function onDismissPopups() { dayButton.closePopup(); }
                            }
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

    StyledText {
        id: navigationHint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        text: root.selectedButton()?.popupPinned ? "Esc" : "← ↑ ↓ →  ·  ↵"
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
        opacity: root.hintVisible ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
        }
    }

}
