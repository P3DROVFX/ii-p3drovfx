import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import "TimetableHelpers.js" as H

/**
 * Month grid, Google-Calendar shaped, Material 3 dressed.
 *
 * Geometry is computed rather than delegated to a layout: the grid needs exact
 * cell rectangles anyway to answer "which day is the cursor over" during a
 * drag, and computing it once means the drop hit-test cannot disagree with what
 * is on screen. Nothing here scrolls — a month always fits, and a cell that
 * runs out of room collapses into a counter.
 */
Item {
    id: root

    property int viewYear: DateTime.clock.date.getFullYear()
    property int viewMonth: DateTime.clock.date.getMonth()
    property bool showUpcoming: true
    property string categoryFilter: ""
    property bool sportsEnabled: false
    property int loadedCellCount: 0
    property string requestedSportsRange: ""
    property date keyboardDate: DateTime.clock.date
    property bool keyboardNavigationActive: false

    readonly property int firstDayOfWeek: Config.options.time.firstDayOfWeek
    readonly property real gridGap: 6
    readonly property var densityModes: ["comfortable", "compact", "dots"]
    readonly property string densityMode: root.densityModes.includes(Persistent.states.cheatsheet.timetableMonthDensity)
        ? Persistent.states.cheatsheet.timetableMonthDensity
        : "compact"

    readonly property var cells: H.buildMonthCells(root.viewYear, root.viewMonth, root.firstDayOfWeek, DateTime.clock.date)
    readonly property int cellCount: root.cells?.length ?? 0
    readonly property int rowCount: Math.max(1, root.cellCount / 7)
    readonly property bool initialLoadComplete: root.cellCount > 0 && root.loadedCellCount >= root.cellCount

    readonly property bool holidaysVisible: (Config.options.calendar.holidays.enable ?? false) && (Config.options.calendar.holidays.showInMonthView ?? false)
    readonly property var holidayMap: root.holidaysVisible ? Holidays.byDayKey : ({})
    readonly property var overdueTasks: Todo.getOverdueTasks(DateTime.clock.date)
    readonly property var undatedTasks: Todo.getUndatedTasks()
    readonly property var availableCategories: {
        const seen = new Set();
        for (const event of CalendarService.events ?? []) {
            for (const category of (event.categories ?? []))
                seen.add(String(category));
        }
        return Array.from(seen).sort((left, right) => left.localeCompare(right));
    }

    // The event rail takes room from the grid. When the view is not wide enough
    // for both rails, the upcoming list is the one that yields.
    readonly property real eventRailWidth: Math.max(300, Math.min(390, root.width * 0.29))
    readonly property real usableWidth: root.width - (eventSidebar.open ? root.eventRailWidth + 14 : 0)
    readonly property bool sidebarAllowed: root.showUpcoming && root.usableWidth >= 1000
    readonly property real sidebarWidth: Math.max(260, Math.min(330, root.width * 0.23))
    readonly property bool compactNav: root.usableWidth < 830
    readonly property bool viewingCurrentMonth: root.viewYear === DateTime.clock.date.getFullYear() && root.viewMonth === DateTime.clock.date.getMonth()
    readonly property bool collapseRecurring: Persistent.states.cheatsheet.timetableCollapseRecurring

    readonly property date viewAnchorDate: new Date(root.viewYear, root.viewMonth, 1)

    signal weekViewRequested

    function filteredEvents(events) {
        if (!root.categoryFilter)
            return events ?? [];
        return (events ?? []).filter(event => (event.categories ?? []).includes(root.categoryFilter));
    }

    function recurrenceSeriesKey(event) {
        const uid = String(event?.uid ?? "");
        if (!uid || String(event?.repeatSymbol ?? "").length === 0 || !event?.startDate)
            return "";
        const startTime = Qt.formatTime(event.startDate, "hh:mm");
        const duration = event.endDate ? Math.max(0, event.endDate.getTime() - event.startDate.getTime()) : 0;
        // UID identifies the series. Presentation fields deliberately remain
        // in the signature so an overridden occurrence stays individually
        // visible instead of being swallowed by its parent routine.
        return [
            String(event.calendar ?? ""), uid, String(event.content ?? ""),
            startTime, String(duration), String(event.status ?? ""),
            String(event.colorToken ?? "")
        ].join("|");
    }

    function recurringOccurrenceKey(event) {
        const series = root.recurrenceSeriesKey(event);
        return series ? series + "|" + H.dayKeyOf(event.startDate) : "";
    }

    function buildRecurringProjection() {
        const empty = { hiddenOccurrences: ({}), segments: [], rowLaneCounts: ({}) };
        if (!root.collapseRecurring)
            return empty;

        const bySeries = {};
        for (let cellIndex = 0; cellIndex < root.cells.length; cellIndex++) {
            const cell = root.cells[cellIndex];
            const events = root.filteredEvents(CalendarService.eventsByDay[cell.key] ?? []);
            for (const event of events) {
                const seriesKey = root.recurrenceSeriesKey(event);
                if (!seriesKey)
                    continue;
                if (!bySeries[seriesKey])
                    bySeries[seriesKey] = [];
                bySeries[seriesKey].push({ cellIndex: cellIndex, event: event });
            }
        }

        const hiddenOccurrences = {};
        const pendingSegments = [];
        for (const seriesKey in bySeries) {
            const occurrences = bySeries[seriesKey].sort((left, right) => left.cellIndex - right.cellIndex);
            if (occurrences.length < 2)
                continue;
            for (const occurrence of occurrences)
                hiddenOccurrences[root.recurringOccurrenceKey(occurrence.event)] = true;

            let runStart = 0;
            for (let i = 1; i <= occurrences.length; i++) {
                const previous = occurrences[i - 1];
                const current = i < occurrences.length ? occurrences[i] : null;
                const continues = current
                    && current.cellIndex === previous.cellIndex + 1
                    && Math.floor(current.cellIndex / 7) === Math.floor(previous.cellIndex / 7);
                if (continues)
                    continue;
                const first = occurrences[runStart];
                pendingSegments.push({
                    seriesKey: seriesKey,
                    event: first.event,
                    row: Math.floor(first.cellIndex / 7),
                    startColumn: first.cellIndex % 7,
                    span: previous.cellIndex - first.cellIndex + 1,
                    occurrenceCount: occurrences.length
                });
                runStart = i;
            }
        }

        pendingSegments.sort((left, right) => left.row - right.row || left.startColumn - right.startColumn || right.span - left.span);
        const rowLaneEnds = {};
        const rowLaneCounts = {};
        for (const segment of pendingSegments) {
            const ends = rowLaneEnds[segment.row] ?? [];
            let lane = 0;
            while (lane < ends.length && segment.startColumn <= ends[lane])
                lane++;
            ends[lane] = segment.startColumn + segment.span - 1;
            rowLaneEnds[segment.row] = ends;
            rowLaneCounts[segment.row] = Math.max(rowLaneCounts[segment.row] ?? 0, lane + 1);
            segment.lane = lane;
        }

        return { hiddenOccurrences: hiddenOccurrences, segments: pendingSegments, rowLaneCounts: rowLaneCounts };
    }

    readonly property var recurringProjection: root.buildRecurringProjection()

    function cellEvents(cell) {
        const events = root.filteredEvents(CalendarService.eventsByDay[cell.key] ?? []);
        if (!root.collapseRecurring)
            return events;
        return events.filter(event => !root.recurringProjection.hiddenOccurrences[root.recurringOccurrenceKey(event)]);
    }

    function tasksForDay(date) {
        const isToday = H.sameDate(date, DateTime.clock.date);
        const dueToday = Todo.getTasksByDate(date).filter(task => !root.overdueTasks.some(overdue => overdue === task || String(overdue?.id ?? "") === String(task?.id ?? "")));
        if (!isToday)
            return dueToday;
        // Overdue tasks live on today only: a calendar user sees the action
        // where it matters now, rather than in a past cell and today.
        return root.overdueTasks.concat(dueToday);
    }

    // ─── Month navigation ───
    property int entranceKey: 0
    // Starts hidden: Component.onCompleted plays the entrance, and a default
    // of 1 meant the grid painted a frame at its final state before that reset
    // it to 0 — the cells appeared, vanished, then faded in again.
    property real gridOpacity: 0
    property real gridShiftX: 0

    function goToMonth(year, month, direction) {
        if (year === root.viewYear && month === root.viewMonth)
            return;
        root.viewYear = year;
        root.viewMonth = month;
        root.playMonthTransition(direction);
    }

    function shiftMonth(delta) {
        const target = H.addMonths(new Date(root.viewYear, root.viewMonth, 1), delta);
        root.goToMonth(target.getFullYear(), target.getMonth(), delta >= 0 ? 1 : -1);
    }

    function goToday() {
        const now = DateTime.clock.date;
        const currentIndex = root.viewYear * 12 + root.viewMonth;
        const targetIndex = now.getFullYear() * 12 + now.getMonth();
        if (currentIndex === targetIndex) {
            root.playMonthTransition(0);
            return;
        }
        root.goToMonth(now.getFullYear(), now.getMonth(), targetIndex > currentIndex ? 1 : -1);
    }

    function focusKeyboardDate(date) {
        const target = H.startOfDay(date);
        const currentIndex = root.viewYear * 12 + root.viewMonth;
        const targetIndex = target.getFullYear() * 12 + target.getMonth();
        root.keyboardDate = target;
        root.keyboardNavigationActive = true;
        if (targetIndex !== currentIndex)
            root.goToMonth(target.getFullYear(), target.getMonth(), targetIndex > currentIndex ? 1 : -1);
    }

    function handleNavigationKey(event) {
        const origin = root.keyboardNavigationActive ? root.keyboardDate : (root.viewingCurrentMonth ? DateTime.clock.date : root.viewAnchorDate);
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            root.focusKeyboardDate(H.addDays(origin, event.key === Qt.Key_Left ? -1 : 1));
            return true;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            root.focusKeyboardDate(H.addDays(origin, event.key === Qt.Key_Up ? -7 : 7));
            return true;
        }
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            root.focusKeyboardDate(H.addMonths(origin, event.key === Qt.Key_PageUp ? -1 : 1));
            return true;
        }
        if (event.key === Qt.Key_Home) {
            root.goToday();
            root.focusKeyboardDate(DateTime.clock.date);
            return true;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.keyboardNavigationActive = true;
            root.requestDay(origin);
            return true;
        }
        return false;
    }

    function focusRequestedDate() {
        const text = String(GlobalStates.timetableRequestedDate ?? "");
        const match = text.match(/^(\d{4})-(\d{2})-(\d{2})$/);
        if (!match)
            return;
        const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
        if (Qt.formatDate(date, "yyyy-MM-dd") !== text)
            return;
        const currentIndex = root.viewYear * 12 + root.viewMonth;
        const targetIndex = date.getFullYear() * 12 + date.getMonth();
        root.goToMonth(date.getFullYear(), date.getMonth(), targetIndex === currentIndex ? 0 : (targetIndex > currentIndex ? 1 : -1));
        root.requestDay(date);
        // A navigation request is single-use: opening the cheatsheet later
        // should retain the user's current month instead of replaying it.
        GlobalStates.timetableRequestedDate = "";
    }

    // Explicit reset then start: a Behavior would not fire on a repeat in the
    // same direction, because the values it would animate are already final.
    function playMonthTransition(direction) {
        monthAnim.stop();
        root.gridShiftX = direction * 44;
        root.gridOpacity = 0;
        root.entranceKey++;
        monthAnim.start();
    }

    ParallelAnimation {
        id: monthAnim

        NumberAnimation {
            target: root
            property: "gridShiftX"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }

        NumberAnimation {
            target: root
            property: "gridOpacity"
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    onViewAnchorDateChanged: {
        root.requestedSportsRange = "";
        root.ensureDataForView();
        root.restartCellLoading();
    }

    onFirstDayOfWeekChanged: {
        root.requestedSportsRange = "";
        root.ensureDataForView();
        root.restartCellLoading();
    }

    function ensureDataForView() {
        CalendarService.ensureRangeCovers(new Date(root.viewYear, root.viewMonth, 1));
        CalendarService.ensureRangeCovers(new Date(root.viewYear, root.viewMonth + 1, 0));
        if (root.holidaysVisible) {
            Holidays.ensureYear(root.viewYear);
            Holidays.ensureYear(new Date(root.viewYear, root.viewMonth + 1, 0).getFullYear());
        }
    }

    function requestSportsRange() {
        if (!root.sportsEnabled || !root.initialLoadComplete || root.cellCount === 0)
            return;
        const fromDate = root.cells[0].date;
        const toDate = root.cells[root.cellCount - 1].date;
        const range = Qt.formatDate(fromDate, "yyyy-MM-dd") + "|" + Qt.formatDate(toDate, "yyyy-MM-dd");
        if (range === root.requestedSportsRange)
            return;
        root.requestedSportsRange = range;
        SportsService.requestTimetableRange(fromDate, toDate);
    }

    function restartCellLoading() {
        root.loadedCellCount = -1;
        Qt.callLater(() => root.loadedCellCount = 0);
    }

    function advanceCellLoading(index) {
        if (index !== root.loadedCellCount || index >= root.cellCount)
            return;
        root.loadedCellCount = index + 1;
    }

    onInitialLoadCompleteChanged: {
        if (root.initialLoadComplete)
            root.requestSportsRange();
    }

    onSportsEnabledChanged: {
        if (root.sportsEnabled)
            root.requestSportsRange();
    }

    Component.onCompleted: {
        root.ensureDataForView();
        root.restartCellLoading();
        root.playMonthTransition(0);
        Qt.callLater(root.focusRequestedDate);
    }

    Connections {
        target: GlobalStates
        function onTimetableNavigationRequestChanged() {
            Qt.callLater(root.focusRequestedDate);
        }
    }

    onHolidaysVisibleChanged: {
        if (root.holidaysVisible)
            Holidays.ensureYear(root.viewYear);
    }

    // ─── Drag state ───
    property var dragEvent: null
    property bool dragOffsetKnown: false
    property real dragOriginX: 0
    property real dragOriginY: 0
    property real dragGrabX: 0
    property real dragGrabY: 0
    property real dragProxyX: 0
    property real dragProxyY: 0
    property real dragProxyW: 0
    property real dragProxyH: 0
    property int dropIndex: -1

    function beginEventDrag(eventData, originX, originY, w, h) {
        root.dragEvent = eventData;
        root.dragOriginX = originX;
        root.dragOriginY = originY;
        root.dragProxyX = originX;
        root.dragProxyY = originY;
        root.dragProxyW = w;
        root.dragProxyH = h;
        root.dragOffsetKnown = false;
        root.dropIndex = -1;
    }

    function moveEventDrag(x, y) {
        if (!root.dragEvent)
            return;
        if (!root.dragOffsetKnown) {
            root.dragGrabX = x - root.dragOriginX;
            root.dragGrabY = y - root.dragOriginY;
            root.dragOffsetKnown = true;
        }
        root.dragProxyX = x - root.dragGrabX;
        root.dragProxyY = y - root.dragGrabY;

        const local = gridArea.mapFromItem(root, x, y);
        root.dropIndex = gridArea.cellIndexAt(local.x, local.y);
    }

    function endEventDrag() {
        const moved = root.dragEvent;
        const target = root.dropIndex >= 0 && root.dropIndex < root.cells.length ? root.cells[root.dropIndex] : null;
        root.cancelEventDrag();
        if (!moved || !target)
            return;
        if (H.sameDate(target.date, moved.startDate))
            return;
        // A recurring master would drag its whole series along, so the drop asks
        // for a scope in the rail instead of guessing.
        eventSidebar.requestMove(moved, target.date);
    }

    function cancelEventDrag() {
        root.dragEvent = null;
        root.dropIndex = -1;
        root.dragOffsetKnown = false;
    }

    // ─── Actions ───
    function requestCreate(date) {
        eventSidebar.startCreate(date);
    }

    function requestOpen(eventData) {
        eventSidebar.showEvent(eventData);
    }

    function requestDay(date) {
        eventSidebar.showDay(date);
    }

    function applySidebarPayload(payload) {
        if (!payload)
            return;
        const nextDay = new Date(payload.date.getFullYear(), payload.date.getMonth(), payload.date.getDate() + 1);
        const fields = {
            summary: payload.title, description: payload.description, location: payload.location,
            url: payload.url, status: payload.status, recurrence: payload.recurrence,
            alarms: payload.alarms, color: payload.color, categories: payload.categories, allDay: payload.allDay,
            start: payload.allDay ? Qt.formatDate(payload.date, "yyyy-MM-dd") : CalendarService.localIso(payload.date, payload.start),
            end: payload.allDay ? Qt.formatDate(nextDay, "yyyy-MM-dd") : CalendarService.localIso(payload.date, payload.end)
        };
        if (payload.editMode) {
            CalendarService.saveEventFields(payload.event, fields, payload.scope ?? "all");
            return;
        }
        CalendarService.createEventFields(payload.calendar, fields);
    }

    function deleteEvent(eventData, scope = "all") {
        if (!eventData)
            return;
        if (eventData.uid)
            CalendarService.deleteEventWithScope(eventData, scope);
    }

    // ─── Layout ───
    RowLayout {
        anchors.fill: parent
        spacing: 14

        // ─── Upcoming rail ───
        Item {
            id: sidebarSlot
            Layout.fillHeight: true
            Layout.preferredWidth: root.sidebarAllowed ? root.sidebarWidth : 0
            visible: Layout.preferredWidth > 1
            clip: true

            Behavior on Layout.preferredWidth {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(sidebarSlot)
            }

            MonthUpcomingPanel {
                anchors.fill: parent
                anchors.rightMargin: 2
                entranceKey: root.entranceKey
                categoryFilter: root.categoryFilter
                holidaysByDay: root.holidayMap
                onEventActivated: eventData => root.requestOpen(eventData)
                onDateActivated: date => root.goToMonth(date.getFullYear(), date.getMonth(), 0)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            // ─── Navigation ───
            RowLayout {
                id: navBar
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2

                    StyledText {
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.viewAnchorDate, "MMMM")
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.compactNav ? 26 : 32
                        font.weight: Font.Bold
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                        animateChange: true
                        animationDistanceX: 0
                        animationDistanceY: 10
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.viewingCurrentMonth ? Translation.tr("%1 · this month").arg(String(root.viewYear)) : String(root.viewYear)
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.Bold
                        color: root.viewingCurrentMonth ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                RippleButton {
                    id: upcomingToggle
                    visible: root.usableWidth >= 1000
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    toggled: root.showUpcoming
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: {
                        root.showUpcoming = !root.showUpcoming;
                        Persistent.states.cheatsheet.timetableShowUpcoming = root.showUpcoming;
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "view_sidebar"
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.showUpcoming ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip {
                        extraVisibleCondition: upcomingToggle.hovered
                        text: root.showUpcoming ? Translation.tr("Hide upcoming events") : Translation.tr("Show upcoming events")
                    }
                }

                // Wrapped in a Toolbar so the three densities read as one
                // segmented control, like the view switch in the header, rather
                // than three loose round buttons.
                Toolbar {
                    // colLayer2 resolves to the same value as the timetable
                    // plate, so the container needs the opaque step this module
                    // already uses for surfaces that must separate from it.
                    enableShadow: false
                    implicitHeight: 42
                    padding: 1
                    colBackground: Appearance.m3colors.m3surfaceContainerHigh

                    ToolbarTabBar {
                        id: densityTabs
                        requestOnly: true
                        currentIndex: Math.max(0, root.densityModes.indexOf(root.densityMode))
                        tabButtonList: [
                            {
                                "icon": "density_large",
                                "name": ""
                            },
                            {
                                "icon": "density_medium",
                                "name": ""
                            },
                            {
                                "icon": "scatter_plot",
                                "name": ""
                            }
                        ]
                        onIndexSelected: index => Persistent.states.cheatsheet.timetableMonthDensity = root.densityModes[index]

                        HoverHandler {
                            id: densityHover
                        }

                        StyledToolTip {
                            extraVisibleCondition: densityHover.hovered
                            text: root.densityMode === "dots"
                                ? Translation.tr("Month density: dots")
                                : (root.densityMode === "comfortable" ? Translation.tr("Month density: comfortable") : Translation.tr("Month density: compact"))
                        }
                    }
                }

                RippleButton {
                    id: recurrenceToggle
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    toggled: root.collapseRecurring
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: Persistent.states.cheatsheet.timetableCollapseRecurring = !root.collapseRecurring

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "repeat"
                        iconSize: Appearance.font.pixelSize.larger
                        color: root.collapseRecurring ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                    }

                    StyledToolTip {
                        extraVisibleCondition: recurrenceToggle.hovered
                        text: root.collapseRecurring ? Translation.tr("Show recurring occurrences") : Translation.tr("Group recurring events")
                    }
                }

                RippleButtonWithIcon {
                    id: todayButton
                    implicitWidth: root.compactNav ? 42 : todayButton.contentImplicitWidth + 32
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    centerContent: true
                    materialIcon: "today"
                    materialIconFill: false
                    mainText: root.compactNav ? "" : Translation.tr("Today")
                    iconPixelSize: Appearance.font.pixelSize.larger
                    textPixelSize: Appearance.font.pixelSize.small
                    mainTextWeight: Font.Bold
                    colText: Appearance.colors.colOnSurface
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: root.goToday()

                    StyledToolTip {
                        extraVisibleCondition: todayButton.hovered && root.compactNav
                        text: Translation.tr("Today")
                    }
                }

                RippleButton {
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: root.shiftMonth(-1)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_left"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnSurface
                    }
                }

                RippleButton {
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: root.shiftMonth(1)

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "chevron_right"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnSurface
                    }
                }

                RippleButton {
                    id: calendarSourcesButton
                    implicitWidth: 42
                    implicitHeight: 42
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colBackgroundActive: Appearance.colors.colLayer2Active
                    onClicked: eventSidebar.showSources()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "calendar_add_on"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurface
                    }

                    StyledToolTip {
                        extraVisibleCondition: calendarSourcesButton.hovered
                        text: Translation.tr("Calendar sources")
                    }
                }

                RippleButtonWithIcon {
                    id: newEventButton
                    implicitWidth: root.compactNav ? 46 : newEventButton.contentImplicitWidth + 36
                    implicitHeight: 46
                    buttonRadius: Appearance.rounding.full
                    centerContent: true
                    materialIcon: "add"
                    materialIconFill: false
                    mainText: root.compactNav ? "" : Translation.tr("New event")
                    iconPixelSize: Appearance.font.pixelSize.huge
                    textPixelSize: Appearance.font.pixelSize.small
                    mainTextWeight: Font.Bold
                    colText: Appearance.colors.colOnPrimary
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colBackgroundActive: Appearance.colors.colPrimaryActive
                    enabled: CalendarService.khalAvailable
                    onClicked: root.requestCreate(root.viewingCurrentMonth ? DateTime.clock.date : root.viewAnchorDate)

                    StyledToolTip {
                        extraVisibleCondition: newEventButton.hovered && root.compactNav
                        text: Translation.tr("New event")
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                visible: root.availableCategories.length > 0
                spacing: 6

                Repeater {
                    model: [""].concat(root.availableCategories)

                    delegate: RippleButton {
                        required property string modelData
                        readonly property bool selected: root.categoryFilter === modelData

                        implicitWidth: filterLabel.implicitWidth + 24
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        colBackground: selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                        colBackgroundHover: selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
                        onClicked: root.categoryFilter = modelData

                        contentItem: StyledText {
                            id: filterLabel
                            anchors.centerIn: parent
                            text: modelData ? modelData : Translation.tr("All labels")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            // ─── Weekday header ───
            Item {
                id: weekdayHeader
                Layout.fillWidth: true
                Layout.preferredHeight: 26

                // Locale short names ("Mon", "Seg"). Deliberately not tied to
                // the waffles two-character tweak: that one belongs to the
                // Windows-style shell, not to this calendar.
                readonly property var labels: H.weekdayLabels(root.firstDayOfWeek, Config.options.calendar.locale, Locale.ShortFormat)

                Repeater {
                    model: 7

                    delegate: StyledText {
                        required property int index

                        x: index * (gridArea.cellWidth + root.gridGap)
                        width: gridArea.cellWidth
                        height: weekdayHeader.height
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: String(weekdayHeader.labels?.[index] ?? "").toUpperCase()
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: H.isWeekendColumn(index, root.firstDayOfWeek) ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            // ─── Grid ───
            Item {
                id: gridArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property real cellWidth: Math.max(1, (width - root.gridGap * 6) / 7)
                readonly property real cellHeight: Math.max(1, (height - root.gridGap * (root.rowCount - 1)) / root.rowCount)

                function cellRect(index) {
                    const column = index % 7;
                    const row = Math.floor(index / 7);
                    return Qt.rect(column * (gridArea.cellWidth + root.gridGap), row * (gridArea.cellHeight + root.gridGap), gridArea.cellWidth, gridArea.cellHeight);
                }

                function cellIndexAt(x, y) {
                    if (x < 0 || y < 0 || x > gridArea.width || y > gridArea.height)
                        return -1;
                    const column = Math.floor(x / (gridArea.cellWidth + root.gridGap));
                    const row = Math.floor(y / (gridArea.cellHeight + root.gridGap));
                    if (column < 0 || column > 6 || row < 0 || row >= root.rowCount)
                        return -1;
                    return row * 7 + column;
                }

                opacity: root.gridOpacity
                transform: Translate {
                    x: root.gridShiftX
                }

                Repeater {
                    model: root.cells ?? []

                    delegate: Loader {
                        id: cellLoader

                        required property int index
                        required property var modelData

                        x: index % 7 * (gridArea.cellWidth + root.gridGap)
                        y: Math.floor(index / 7) * (gridArea.cellHeight + root.gridGap)
                        width: gridArea.cellWidth
                        height: gridArea.cellHeight
                        active: index <= root.loadedCellCount
                        asynchronous: true

                        onLoaded: root.advanceCellLoading(index)

                        sourceComponent: MonthDayCell {
                            cellData: cellLoader.modelData
                            densityMode: root.densityMode
                            recurrenceLaneOffset: (root.recurringProjection.rowLaneCounts[Math.floor(cellLoader.index / 7)] ?? 0) * 18
                            events: root.cellEvents(cellLoader.modelData)
                            tasks: root.tasksForDay(cellLoader.modelData.date)
                            birthdays: BirthdaysService.birthdaysForDate(cellLoader.modelData.date)
                            holidays: root.holidayMap[cellLoader.modelData.key] ?? []
                            sportsEnabled: root.sportsEnabled
                            dropTarget: root.dropIndex === cellLoader.index && root.dragEvent !== null
                            coordinateRoot: root
                            draggedEvent: root.dragEvent
                            entranceKey: root.entranceKey
                            keyboardSelected: root.keyboardNavigationActive && H.sameDate(root.keyboardDate, cellLoader.modelData.date)
                            undatedTaskCount: cellLoader.modelData.isToday ? root.undatedTasks.length : 0

                            onCreateRequested: date => root.requestCreate(date)
                            onDayActivated: date => root.requestDay(date)
                            onEventActivated: eventData => root.requestOpen(eventData)
                            onTaskCompletionRequested: task => Todo.markDone(task)
                            onUndatedTasksActivated: eventSidebar.showUndatedTasks()
                            onEventDragBegan: (eventData, x, y, w, h) => root.beginEventDrag(eventData, x, y, w, h)
                            onEventDragMoved: (x, y) => root.moveEventDrag(x, y)
                            onEventDragEnded: root.endEventDrag()
                            onEventDragCanceled: root.cancelEventDrag()
                        }
                    }
                }

                Repeater {
                    model: root.recurringProjection.segments

                    delegate: RippleButton {
                        id: recurringBand
                        required property var modelData

                        readonly property color accent: H.chipColor(recurringBand.modelData.event, Appearance.colors, GoogleCalendarService.colorForEvent(recurringBand.modelData.event))
                        x: recurringBand.modelData.startColumn * (gridArea.cellWidth + root.gridGap) + 5
                        y: recurringBand.modelData.row * (gridArea.cellHeight + root.gridGap)
                            + 24 + recurringBand.modelData.lane * 18
                        width: recurringBand.modelData.span * gridArea.cellWidth
                            + Math.max(0, recurringBand.modelData.span - 1) * root.gridGap - 10
                        implicitHeight: 16
                        z: 4
                        buttonRadius: Appearance.rounding.verysmall
                        colBackground: recurringBand.accent
                        colBackgroundHover: ColorUtils.mix(recurringBand.accent, Appearance.colors.colOnSurface, 0.88)
                        onClicked: root.requestOpen(recurringBand.modelData.event)

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 7
                            anchors.rightMargin: 7
                            spacing: 4

                            MaterialSymbol {
                                text: "repeat"
                                iconSize: Appearance.font.pixelSize.smallest
                                color: ColorUtils.getContrastingTextColor(recurringBand.accent)
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: (recurringBand.modelData.event?.content ?? Translation.tr("Event"))
                                    + " · ×" + String(recurringBand.modelData.occurrenceCount)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: ColorUtils.getContrastingTextColor(recurringBand.accent)
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: recurringBand.hovered
                            text: Translation.tr("%1 recurring occurrences")
                                .arg(String(recurringBand.modelData.occurrenceCount))
                        }
                    }
                }
            }
        }

        // ─── Event rail ───
        Item {
            id: eventRailSlot
            Layout.fillHeight: true
            Layout.preferredWidth: eventSidebar.open ? root.eventRailWidth : 0
            visible: Layout.preferredWidth > 1
            clip: true

            Behavior on Layout.preferredWidth {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(eventRailSlot)
            }

            EventSidebar {
                id: eventSidebar
                width: root.eventRailWidth
                height: parent.height
                anchors.right: parent.right

                onSaveRequested: payload => root.applySidebarPayload(payload)
                onTaskCreateRequested: task => Todo.addItem(task)
                onTaskCompletionRequested: task => Todo.markDone(task)
                onDeleteRequested: (eventData, scope) => root.deleteEvent(eventData, scope)
                onMoveRequested: (eventData, newDate, scope) => {
                    if (!eventData || !newDate)
                        return;
                    CalendarService.moveEvent(eventData, newDate, scope);
                    root.goToMonth(newDate.getFullYear(), newDate.getMonth(), 0);
                }
                onTimePickerRequested: (which, startHour, startMinute) => {
                    timePicker.target = which;
                    timePicker.open(startHour, startMinute, which === "start" ? Translation.tr("Starts at") : Translation.tr("Ends at"));
                }
                onDatePickerRequested: (purpose, date) => {
                    datePicker.purpose = purpose;
                    datePicker.open(date, purpose === "reschedule" ? Translation.tr("Move event to") : Translation.tr("Event date"));
                }
            }
        }
    }

    // ─── khal missing ───
    Rectangle {
        anchors.fill: parent
        visible: !CalendarService.khalAvailable
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        z: 90

        PagePlaceholder {
            icon: "calendar_add_on"
            shape: "Cookie12Sided"
            title: Translation.tr("No calendar backend")
            description: Translation.tr("Install khal to create and browse events here")
            animateIconOnShow: true
        }
    }

    // ─── Drag proxy ───
    Rectangle {
        id: dragProxy
        visible: root.dragEvent !== null
        x: root.dragProxyX
        y: root.dragProxyY
        width: Math.max(120, root.dragProxyW)
        height: Math.max(26, root.dragProxyH)
        radius: Math.min(height / 2, Appearance.rounding.small)
        color: H.chipColor(root.dragEvent, Appearance.colors, GoogleCalendarService.colorForEvent(root.dragEvent))
        opacity: 0.96
        scale: 1.06
        z: 120

        Row {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 6

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "drag_indicator"
                iconSize: Appearance.font.pixelSize.small
                color: ColorUtils.getContrastingTextColor(dragProxy.color)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - x)
                text: root.dragEvent?.content ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: ColorUtils.getContrastingTextColor(dragProxy.color)
                elide: Text.ElideRight
            }
        }
    }

    // ─── Pickers ───
    // Owned here rather than by the rail so they centre over the whole view.
    TimePickerPopup {
        id: timePicker
        anchors.fill: parent

        property string target: "start"

        onAccepted: (pickedHour, pickedMinute) => eventSidebar.applyPickedTime(timePicker.target, pickedHour, pickedMinute)
    }

    DatePickerPopup {
        id: datePicker
        anchors.fill: parent

        property string purpose: "form"

        onAccepted: pickedDate => eventSidebar.applyPickedDate(datePicker.purpose, pickedDate)
    }
}
