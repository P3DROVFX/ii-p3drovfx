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
    property int sizeW: 0
    property int sizeH: 0

    readonly property bool isShortHeight: (sizeH > 0 && sizeH <= 2) || (sizeH === 0 && root.height > 0 && root.height < 200)
    readonly property bool isCompactSquare: isShortHeight && ((sizeW > 0 && sizeW <= 2) || (sizeW === 0 && root.width < 260))
    readonly property bool isWideBanner: isShortHeight && ((sizeW >= 4) || (sizeW === 0 && root.width >= 260))
    readonly property bool isTall: sizeH >= 4 || (sizeH === 0 && root.height > 220 && root.width < 260)
    readonly property bool isCompact: isCompactSquare
    readonly property bool isWide: isWideBanner

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

    function openCalendar() {
        GlobalStates.sidebarRightOpen = false;
        if (PanelFamily.nativeAppWindows)
            GlobalStates.openAppDrawerTool("", "calendar");
        else
            GlobalStates.openSearchPanel("calendar");
    }

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

    readonly property var currentSelectedEvents: root.tasksForDate(
        root.selectedDate.getFullYear(),
        root.selectedDate.getMonth(),
        root.selectedDate.getDate()
    ) ?? []

    readonly property var weekDaysList: {
        const d = new Date(root.selectedDate);
        const currentDay = d.getDay();
        const firstDay = Config.options.time.firstDayOfWeek ?? 0;
        const diff = (currentDay - firstDay + 7) % 7;
        const startOfWeek = new Date(d);
        startOfWeek.setDate(d.getDate() - diff);

        const list = [];
        const today = new Date();
        for (let i = 0; i < 7; i++) {
            const dayDate = new Date(startOfWeek);
            dayDate.setDate(startOfWeek.getDate() + i);
            const isToday = (dayDate.getFullYear() === today.getFullYear() &&
                             dayDate.getMonth() === today.getMonth() &&
                             dayDate.getDate() === today.getDate());
            const dayOfWeek = dayDate.getDay();
            const shortName = Qt.locale().dayName(dayOfWeek, Locale.ShortFormat);
            const letter = shortName ? shortName.charAt(0).toUpperCase() : "";
            list.push({
                date: dayDate,
                day: dayDate.getDate(),
                month: dayDate.getMonth(),
                year: dayDate.getFullYear(),
                weekdayName: letter,
                isToday: isToday
            });
        }
        return list;
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
    readonly property real headerHeight: (root.isCompact || root.isWide) ? 22 : (root.compact ? 24 : 30)
    readonly property real calendarSpacing: root.isCompact ? 2 : (root.isWide ? 1 : (root.compact ? 1 : 5))
    readonly property real availableGridWidth: root.isWide ? Math.min(200, Math.round(root.width * 0.48)) : root.width
    readonly property real availableGridHeight: root.isTall
        ? Math.round(root.height * 0.65)
        : (root.height - root.headerHeight - root.calendarSpacing * 2 - ((!root.isCompact && navigationHint.visible) ? navigationHint.implicitHeight : 0))

    readonly property real cellSize: {
        if (root.height <= 0)
            return 38;
        const forRows = root.availableGridHeight - root.calendarSpacing * 6;
        const heightBound = forRows / 7;
        const widthBound = (root.availableGridWidth - root.calendarSpacing * 6) / 7;
        return Math.max(14, Math.min(38, heightBound, widthBound));
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
    Item {
        id: calendarLeftContainer
        visible: !root.isShortHeight
        anchors.top: parent.top
        anchors.left: parent.left
        width: root.isWide ? root.availableGridWidth : parent.width
        height: root.isTall ? (root.availableGridHeight + root.headerHeight + root.calendarSpacing * 2) : parent.height

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
                buttonText: `${monthShift != 0 ? "• " : ""}${root.isCompact ? viewingDate.toLocaleDateString(Qt.locale(), "MMM yyyy") : viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                tooltipText: Translation.tr("Today") + " (Ctrl+Home)"
                onClicked: root.selectDate(new Date())
                contentItem: TaskShortcutContent {
                    labelText: todayButton.buttonText
                    shortcut: "Ctrl + Home"
                    showHint: root.hintVisible
                    labelPixelSize: root.isCompact ? Appearance.font.pixelSize.small : (root.compact ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.larger)
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
                implicitWidth: root.isCompact ? 22 : Math.max(root.headerHeight, Appearance.font.pixelSize.smallest * 3)
                onClicked: root.changeMonth(-1)

                contentItem: TaskShortcutContent {
                    symbol: "chevron_left"
                    shortcut: "Ctrl\n+ ←"
                    showHint: root.hintVisible
                    iconSize: root.isCompact ? Appearance.font.pixelSize.small : (root.compact ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
                    color: Appearance.colors.colOnLayer1
                }
            }

            CalendarHeaderButton {
                Accessible.name: Translation.tr("Next month")
                tooltipText: Translation.tr("Next month") + " (Ctrl+→ / PgDn)"
                forceCircle: true
                implicitHeight: root.headerHeight
                implicitWidth: root.isCompact ? 22 : Math.max(root.headerHeight, Appearance.font.pixelSize.smallest * 3)
                onClicked: root.changeMonth(1)

                contentItem: TaskShortcutContent {
                    symbol: "chevron_right"
                    shortcut: "Ctrl\n+ →"
                    showHint: root.hintVisible
                    iconSize: root.isCompact ? Appearance.font.pixelSize.small : (root.compact ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.larger)
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
            anchors.topMargin: root.isCompact ? 4 : root.calendarSpacing
            anchors.bottomMargin: (root.hintVisible ? 16 : 0) + root.calendarSpacing

            ColumnLayout {
                id: calendarGridColumn
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
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
    }

    // Side agenda panel for desktop wide layout
    Rectangle {
        id: wideAgendaPanel
        visible: !root.isShortHeight && root.isWide
        anchors.left: calendarLeftContainer.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "transparent"

        ColumnLayout {
            anchors.fill: parent
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "event"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.selectedDate.toLocaleDateString(Qt.locale(), "ddd, d MMM")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.currentSelectedEvents.length > 0
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimaryContainer
                    implicitWidth: countText.implicitWidth + 10
                    implicitHeight: countText.implicitHeight + 4
                    StyledText {
                        id: countText
                        anchors.centerIn: parent
                        text: String(root.currentSelectedEvents.length)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnPrimaryContainer
                        font.weight: Font.Bold
                    }
                }
            }

            ListView {
                id: agendaListView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 4
                model: root.currentSelectedEvents

                delegate: Rectangle {
                    required property var modelData
                    width: agendaListView.width
                    implicitHeight: 28
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainer

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 6

                        Rectangle {
                            width: 3
                            height: 16
                            radius: 1.5
                            color: modelData.color || Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.content || modelData.title || Translation.tr("Event")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: !!modelData.startDate
                            text: Qt.formatDateTime(modelData.startDate, "hh:mm")
                            font.pixelSize: Appearance.font.pixelSize.smallest * 0.9
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Item {
                    visible: root.currentSelectedEvents.length === 0
                    anchors.fill: parent

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "event_available"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("No events")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    // Bottom agenda card for tall layout (2x4)
    Rectangle {
        id: tallAgendaPanel
        visible: root.isTall
        anchors.top: calendarLeftContainer.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: navigationHint.top
        anchors.bottomMargin: 2
        radius: Appearance.rounding.small
        color: Appearance.colors.colSurfaceContainer
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 6
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                MaterialSymbol {
                    text: "event"
                    iconSize: 14
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.selectedDate.toLocaleDateString(Qt.locale(), "ddd, d MMM")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    text: root.currentSelectedEvents.length > 0
                        ? `${root.currentSelectedEvents.length} ${Translation.tr("events")}`
                        : Translation.tr("No events")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.currentSelectedEvents.slice(0, 3)

                delegate: RowLayout {
                    required property var modelData
                    width: parent.width
                    spacing: 4

                    Rectangle {
                        width: 2
                        height: 12
                        radius: 1
                        color: modelData.color || Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.content || modelData.title || ""
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Shared 7-Day Week Strip Component ─────────────────────────────
    component WeekStrip: RowLayout {
        id: weekStrip
        property bool compactMode: false
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: root.weekDaysList
            delegate: Rectangle {
                id: dayCell
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredHeight: weekStrip.compactMode ? 36 : 40
                radius: Appearance.rounding.small

                readonly property bool isToday: modelData.isToday
                readonly property bool isSelected: modelData.date.toDateString() === root.selectedDate.toDateString()
                readonly property var dayEvents: root.tasksForDate(modelData.year, modelData.month, modelData.day) ?? []

                color: dayMouseArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"

                Behavior on color {
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                }

                MouseArea {
                    id: dayMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectDate(dayCell.modelData.date)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 1

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: dayCell.modelData.weekdayName
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        color: dayCell.isToday ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 22
                        height: 22
                        radius: 11
                        color: dayCell.isToday ? Appearance.colors.colPrimary
                            : dayCell.isSelected ? Appearance.colors.colLayer2Hover
                            : "transparent"
                        border.width: !dayCell.isToday && dayCell.isSelected ? 1.5 : 0
                        border.color: Appearance.colors.colPrimary

                        Behavior on color {
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: String(dayCell.modelData.day)
                            font.pixelSize: 11
                            font.weight: dayCell.isToday || dayCell.isSelected ? Font.Bold : Font.Normal
                            color: dayCell.isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 3
                        height: 3
                        radius: 1.5
                        visible: dayCell.dayEvents.length > 0
                        color: dayCell.isToday ? Appearance.colors.colPrimary
                            : (dayCell.dayEvents[0]?.color || Appearance.colors.colPrimary)
                    }
                }
            }
        }
    }

    // ── Compact Week View (2x2) ───────────────────────────────────────────
    Item {
        id: compactWeekView
        visible: root.isCompactSquare
        anchors.fill: parent
        anchors.margins: 6

        ColumnLayout {
            anchors.fill: parent
            spacing: 4

            // Header: Month Year + navigation chevrons
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                MouseArea {
                    Layout.fillWidth: true
                    implicitHeight: 22
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectDate(new Date())

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        text: root.selectedDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    implicitWidth: 20
                    implicitHeight: 20
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        const d = new Date(root.selectedDate);
                        d.setDate(d.getDate() - 7);
                        root.selectDate(d);
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: 14
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Previous week") }
                }

                RippleButton {
                    implicitWidth: 20
                    implicitHeight: 20
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        const d = new Date(root.selectedDate);
                        d.setDate(d.getDate() + 7);
                        root.selectDate(d);
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: 14
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Next week") }
                }
            }

            // 7-day week strip
            WeekStrip {
                compactMode: true
            }

            // Selected Day Agenda / Event Preview card
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                clip: true

                ListView {
                    id: compactEventsList
                    anchors.fill: parent
                    anchors.margins: 4
                    visible: root.currentSelectedEvents.length > 0
                    spacing: 2
                    model: root.currentSelectedEvents.slice(0, 2)
                    delegate: RowLayout {
                        required property var modelData
                        width: compactEventsList.width
                        spacing: 4

                        Rectangle {
                            width: 2.5
                            height: 12
                            radius: 1
                            color: modelData.color || Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.content || modelData.title || ""
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }
                    }
                }

                RowLayout {
                    anchors.centerIn: parent
                    visible: root.currentSelectedEvents.length === 0
                    spacing: 4

                    MaterialSymbol {
                        text: "event_available"
                        iconSize: 14
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        text: Translation.tr("No events")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openCalendar()
                }
            }
        }
    }

    // ── Wide Banner View (4x2): Week Strip on Left + Full Agenda on Right ──
    Item {
        id: wideWeekView
        visible: root.isWideBanner
        anchors.fill: parent
        anchors.margins: 6

        readonly property real paneWidth: Math.floor((width - 9) / 2)

        // Left Pane: Weekly Calendar Navigation (guaranteed 50% width)
        Item {
            id: leftCalendarPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: wideWeekView.paneWidth
            clip: true

            // Month header + week navigation
            RowLayout {
                id: leftHeaderRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 22
                spacing: 2

                MouseArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 22
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectDate(new Date())

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.right: parent.right
                        text: root.selectedDate.toLocaleDateString(Qt.locale(), "MMM yyyy")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    implicitWidth: 18
                    implicitHeight: 18
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        const d = new Date(root.selectedDate);
                        d.setDate(d.getDate() - 7);
                        root.selectDate(d);
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: 13
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Previous week") }
                }

                RippleButton {
                    implicitWidth: 18
                    implicitHeight: 18
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: {
                        const d = new Date(root.selectedDate);
                        d.setDate(d.getDate() + 7);
                        root.selectDate(d);
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: 13
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip { text: Translation.tr("Next week") }
                }
            }

            // 7-day strip (fits perfectly in 135-150px: 7 * 19px = 133px)
            Item {
                id: leftStripContainer
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: leftHeaderRow.bottom
                anchors.topMargin: 3
                height: 40

                WeekStrip {
                    anchors.fill: parent
                    compactMode: false
                }
            }

            // Bottom row: Clean single Today shortcut pill (NEVER overlaps)
            RippleButton {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                implicitHeight: 22
                implicitWidth: Math.min(leftCalendarPane.width - 8, todayRow.implicitWidth + 14)
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.selectDate(new Date())

                contentItem: Row {
                    id: todayRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "today"
                        iconSize: 11
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.selectedDate.toDateString() === (new Date()).toDateString()
                            ? Translation.tr("Today")
                            : root.selectedDate.toLocaleDateString(Qt.locale(), "d MMM")
                        font.pixelSize: Appearance.font.pixelSize.smallest * 0.9
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                    }
                }
                StyledToolTip { text: Translation.tr("Go to today") }
            }
        }

        // Divider
        Rectangle {
            id: paneDivider
            anchors.left: leftCalendarPane.right
            anchors.leftMargin: 4
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.3
        }

        // Right Pane: Rich Agenda List for selected day (guaranteed 50% width)
        Rectangle {
            id: rightAgendaPane
            anchors.left: paneDivider.right
            anchors.leftMargin: 4
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: Appearance.rounding.small
            color: Appearance.colors.colSurfaceContainer
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                // Agenda Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    MaterialSymbol {
                        text: "event"
                        iconSize: 13
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedDate.toLocaleDateString(Qt.locale(), "ddd, d MMM")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: root.currentSelectedEvents.length > 0
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        implicitWidth: agendaCountText.implicitWidth + 8
                        implicitHeight: agendaCountText.implicitHeight + 2
                        StyledText {
                            id: agendaCountText
                            anchors.centerIn: parent
                            text: String(root.currentSelectedEvents.length)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnPrimaryContainer
                            font.weight: Font.Bold
                        }
                    }

                    RippleButton {
                        implicitWidth: 18
                        implicitHeight: 18
                        buttonRadius: Appearance.rounding.full
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.openCalendar()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "open_in_new"
                            iconSize: 12
                            color: Appearance.colors.colSubtext
                        }
                        StyledToolTip { text: Translation.tr("Open full calendar") }
                    }
                }

                // Agenda List
                ListView {
                    id: wideAgendaList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 3
                    model: root.currentSelectedEvents

                    delegate: Rectangle {
                        required property var modelData
                        width: wideAgendaList.width
                        implicitHeight: 24
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            anchors.rightMargin: 5
                            spacing: 4

                            Rectangle {
                                width: 2.5
                                height: 13
                                radius: 1
                                color: modelData.color || Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.content || modelData.title || Translation.tr("Event")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                visible: !!modelData.startDate
                                text: Qt.formatDateTime(modelData.startDate, "hh:mm")
                                font.pixelSize: Appearance.font.pixelSize.smallest * 0.85
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    Item {
                        visible: root.currentSelectedEvents.length === 0
                        anchors.fill: parent

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "event_available"
                                iconSize: 18
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("No events scheduled")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                            }
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
