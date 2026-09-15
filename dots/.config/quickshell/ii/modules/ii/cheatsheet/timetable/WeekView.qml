import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import qs.modules.common.functions
import "."
import "TimetableHelpers.js" as H

Item {
    id: root

    property real spacing: 8
    property string viewMode: "week"

    readonly property bool eventPopupVisible: eventSidebar.open

    property int startHour: 0
    property int startMinute: 0
    property int endHour: 24
    property int slotDuration: 60 // in minutes
    readonly property list<int> slotHeightSteps: [96, 120, 144, 168, 192]
    readonly property int comfortableSlotHeight: 168
    readonly property int slotHeightStateVersion: 1
    property int slotHeight: Persistent.states.cheatsheet.timetableSlotHeight
    property int timeColumnWidth: 56
    property real maxContentWidth: 1600
    property real navBarHeight: 56

    readonly property int totalSlots: Math.floor(((endHour * 60) - (startHour * 60 + startMinute)) / slotDuration)
    readonly property real pixelsPerMinute: slotHeight / slotDuration
    readonly property int contentHeight: totalSlots * slotHeight

    property real maxHeight: 700
    property bool allDayExpanded: false
    readonly property int collapsedAllDayRows: 2
    readonly property int expandedAllDayRows: 5
    readonly property int visibleAllDayRows: Math.min(root.maxHeaderChipCount, root.allDayExpanded ? root.expandedAllDayRows : root.collapsedAllDayRows)
    readonly property bool hasExpandableAllDayLane: root.maxHeaderChipCount > root.collapsedAllDayRows
    readonly property int allDayExpanderHeight: 28
    property real headerHeight: 64
        + (root.visibleAllDayRows > 0 ? root.visibleAllDayRows * (allDayChipHeight + allDayChipSpacing) + 8 : 0)
        + (root.hasExpandableAllDayLane ? root.allDayExpanderHeight + root.allDayChipSpacing : 0)
    property real currentTimeY: -1
    property bool initialScrollApplied: false
    property bool sportsEnabled: false
    property int loadedDayCount: 0
    property string requestedSportsRange: ""
    readonly property int visibleDayCount: root.viewMode === "day" ? 1 : (root.viewMode === "threeDay" ? 3 : 7)
    property date viewWeekStart: root.rangeStartFor(DateTime.clock.date)
    property bool followingCurrentWeek: true
    property int entranceKey: 0
    property real weekOpacity: 1
    property real weekShiftX: 0
    property real zoomWheelAccumulator: 0
    property bool componentReady: false
    property date keyboardDate: DateTime.clock.date
    property bool keyboardNavigationActive: false
    readonly property int dayCount: root.days?.length ?? 0
    readonly property bool initialLoadComplete: root.dayCount > 0 && root.loadedDayCount >= root.dayCount
    readonly property date currentWeekStart: root.rangeStartFor(DateTime.clock.date)
    readonly property date viewWeekEnd: H.addDays(root.viewWeekStart, root.visibleDayCount - 1)
    readonly property bool viewingCurrentWeek: H.startOfDay(DateTime.clock.date).getTime() >= H.startOfDay(root.viewWeekStart).getTime()
        && H.startOfDay(DateTime.clock.date).getTime() <= H.startOfDay(root.viewWeekEnd).getTime()

    readonly property real eventRailWidth: Math.max(300, Math.min(390, root.width * 0.29))
    readonly property real usableWidth: root.width - (eventSidebar.open ? root.eventRailWidth + 14 : 0)
    readonly property bool compactNav: root.usableWidth < 830
    readonly property real dayColumnWidth: {
        let availableWidth = root.usableWidth > 0 ? root.usableWidth : maxContentWidth;
        return Math.max(80, (availableWidth - timeColumnWidth - root.dayCount * spacing) / Math.max(1, root.dayCount));
    }
    readonly property int currentDayIndex: {
        for (let index = 0; index < root.days.length; index++) {
            if (H.sameDate(root.days[index]?.sportsDate, DateTime.clock.date))
                return index;
        }
        return -1;
    }
    readonly property string clockDayKey: Qt.formatDate(DateTime.clock.date, "yyyy-MM-dd")

    implicitWidth: maxContentWidth
    implicitHeight: Math.min(navBarHeight + headerHeight + contentHeight, maxHeight)

    Behavior on headerHeight {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    readonly property var days: {
        const calendarEvents = CalendarService.eventsByDay;
        // gamesForDate() reads a plain array, so depend explicitly on the
        // replacement that SportsService publishes after each refresh.
        const sportsGames = root.sportsEnabled ? SportsService.timetableGames : [];
        const result = [];
        for (let i = 0; i < root.visibleDayCount; i++) {
            const date = H.addDays(root.viewWeekStart, i);
            const games = root.sportsEnabled && Array.isArray(sportsGames) ? SportsService.gamesForDate(date) : [];
            result.push({
                name: Qt.formatDate(date, "dddd"),
                date: date,
                events: calendarEvents?.[H.dayKeyOf(date)] ?? [],
                sportsDate: date,
                sportsCount: games.length
            });
        }
        return result;
    }
    readonly property int allDayChipHeight: 36
    readonly property int allDayChipSpacing: 6
    readonly property int maxHeaderChipCount: {
        if (!root.days || root.days.length === 0)
            return 0;
        let maxCount = 0;
        for (let i = 0; i < root.days.length; i++) {
            const sportsCount = Number(root.days[i]?.sportsCount ?? 0) > 0 ? 1 : 0;
            const count = (root.days[i]?.events ?? []).filter(event => CalendarService.isAllDayEvent(event)).length + sportsCount;
            if (count > maxCount)
                maxCount = count;
        }
        return maxCount;
    }

    // ─── Theme Colors ───
    readonly property color todayHighlightFill: H.withOpacity(Appearance.colors.colPrimary, 0.12)
    readonly property color dayBackgroundFill: H.withOpacity(Appearance.colors.colSecondary, 0.04)
    readonly property color dayBackgroundFillVariant: H.withOpacity(Appearance.colors.colSecondary, 0.08)

    // ─── State ───
    property var nextEventData: null
    property real maxLogicalDistance: 1.0

    property bool ghostVisible: false
    property int ghostDayIndex: -1
    property real ghostTopY: 0
    property real ghostHeight: 0
    // The host exposes this to Cheatsheet.qml so a day-grid selection keeps
    // ownership of its pointer instead of switching the outer SwipeView tab.
    property bool timetableDragActive: false

    function clearGhostPreview() {
        root.ghostVisible = false;
        root.ghostDayIndex = -1;
        root.ghostTopY = 0;
        root.ghostHeight = 0;
    }
    property var timedMutationEvent: null
    property string timedMutationKind: ""
    property real timedMutationPointerOffsetY: 0
    property int timedMutationStartMinutes: 0
    property int timedMutationEndMinutes: 0
    property int timedMutationDayIndex: -1

    function setTimetableDragActive(active) {
        root.timetableDragActive = active;
        if (styledFlickable)
            styledFlickable.interactive = !active;
    }

    // ─── Helpers ───
    function updateCurrentTimeLine() {
        let time = DateTime.clock.date;
        let currentTotalMinutes = time.getHours() * 60 + time.getMinutes();
        let baseTotalMinutes = root.startHour * 60 + root.startMinute;
        currentTimeY = (currentTotalMinutes - baseTotalMinutes) * root.pixelsPerMinute;
    }

    function updateNextEvent() {
        if (!root.days || root.days.length === 0) {
            root.nextEventData = null;
            root.maxLogicalDistance = 1.0;
            return;
        }

        let now = DateTime.clock.date;
        let currentDayIdx = root.currentDayIndex;
        let nowTotalMins = currentDayIdx * 24 * 60 + (now.getHours() * 60 + now.getMinutes());

        let bestDiff = Infinity;
        let nextEvt = null;

        for (let i = 0; i < root.days.length; i++) {
            let events = (root.days[i]?.events ?? []).filter(event => !CalendarService.isAllDayEvent(event));
            for (let evt of events) {
                let startMins = H.eventStartMinutes(evt);
                let endMins = H.eventEndMinutes(evt);
                if (startMins === null)
                    continue;
                if (endMins === null)
                    endMins = 24 * 60;

                let evtStartTotal = i * 24 * 60 + startMins;
                let evtEndTotal = i * 24 * 60 + endMins;

                if (evtEndTotal > nowTotalMins) {
                    let diff = Math.max(0, evtStartTotal - nowTotalMins);
                    if (diff < bestDiff) {
                        bestDiff = diff;
                        nextEvt = {
                            dayIndex: i,
                            startMinutes: startMins,
                            endMinutes: endMins
                        };
                    }
                }
            }
        }

        if (!nextEvt) {
            let earliestTotal = Infinity;
            for (let i = 0; i < root.days.length; i++) {
                for (let evt of (root.days[i]?.events ?? []).filter(event => !CalendarService.isAllDayEvent(event))) {
                    let startMins = H.eventStartMinutes(evt);
                    if (startMins === null)
                        continue;
                    let evtStartTotal = i * 24 * 60 + startMins;
                    if (evtStartTotal < earliestTotal) {
                        earliestTotal = evtStartTotal;
                        nextEvt = {
                            dayIndex: i,
                            startMinutes: startMins,
                            endMinutes: H.eventEndMinutes(evt)
                        };
                    }
                }
            }
        }

        root.nextEventData = nextEvt;
        if (!Config.options.calendar.timetable.proximityColorGradient || !nextEvt) {
            root.maxLogicalDistance = 1.0;
            return;
        }

        let maxDistance = 0;
        for (let i = 0; i < root.days.length; i++) {
            const events = (root.days[i]?.events ?? []).filter(event => !CalendarService.isAllDayEvent(event));
            for (const event of events) {
                const startMinutes = H.eventStartMinutes(event);
                if (startMinutes === null)
                    continue;
                const dayDistance = i - nextEvt.dayIndex;
                const hourDistance = (startMinutes - nextEvt.startMinutes) / 60.0;
                maxDistance = Math.max(maxDistance, Math.sqrt(dayDistance * dayDistance + hourDistance * hourDistance));
            }
        }
        root.maxLogicalDistance = Math.max(1.0, maxDistance);
    }

    function scrollToCurrentTime() {
        if (!styledFlickable || styledFlickable.height <= 0) {
            Qt.callLater(root.scrollToCurrentTime);
            return;
        }
        let now = DateTime.clock.date;
        let diff = Math.max(0, (now.getHours() * 60 + now.getMinutes()) - (root.startHour * 60 + root.startMinute));
        let targetY = diff * root.pixelsPerMinute - (styledFlickable.height / 3);
        styledFlickable.contentY = Math.min(Math.max(0, targetY), Math.max(0, styledFlickable.contentHeight - styledFlickable.height));
    }

    function zoomSlotHeight(direction, viewportY) {
        const currentHeight = root.slotHeight;
        let currentIndex = root.slotHeightSteps.indexOf(currentHeight);
        if (currentIndex < 0) {
            currentIndex = 0;
            for (let i = 1; i < root.slotHeightSteps.length; i++) {
                if (Math.abs(root.slotHeightSteps[i] - currentHeight) < Math.abs(root.slotHeightSteps[currentIndex] - currentHeight))
                    currentIndex = i;
            }
        }

        const nextIndex = Math.max(0, Math.min(root.slotHeightSteps.length - 1, currentIndex + direction));
        const nextHeight = root.slotHeightSteps[nextIndex];
        if (nextHeight === currentHeight)
            return;

        const focalY = Math.max(0, Math.min(styledFlickable.height, viewportY));
        const oldPixelsPerMinute = currentHeight / root.slotDuration;
        const focalMinutes = (styledFlickable.contentY + focalY) / oldPixelsPerMinute;
        Persistent.states.cheatsheet.timetableSlotHeight = nextHeight;
        Qt.callLater(() => {
            const targetY = focalMinutes * root.pixelsPerMinute - focalY;
            styledFlickable.contentY = Math.max(0, Math.min(targetY, styledFlickable.contentHeight - styledFlickable.height));
        });
    }

    function normalizeSlotHeight() {
        if (Persistent.states.cheatsheet.timetableSlotHeightVersion < root.slotHeightStateVersion) {
            Persistent.states.cheatsheet.timetableSlotHeight = root.comfortableSlotHeight;
            Persistent.states.cheatsheet.timetableSlotHeightVersion = root.slotHeightStateVersion;
            return;
        }
        if (root.slotHeightSteps.indexOf(root.slotHeight) >= 0)
            return;
        Persistent.states.cheatsheet.timetableSlotHeight = root.comfortableSlotHeight;
    }

    function maybeApplyInitialScroll() {
        if (root.initialScrollApplied)
            return;
        if (!styledFlickable || styledFlickable.height <= 0 || !root.days || root.days.length === 0) {
            initialScrollRetryTimer.restart();
            return;
        }
        root.scrollToCurrentTime();
        root.initialScrollApplied = true;
    }

    // A Timer belongs to the week view and is destroyed with it. Keeping the
    // layout retry here avoids a self-perpetuating Qt.callLater callback after
    // the asynchronously-loaded view has been released.
    Timer {
        id: initialScrollRetryTimer
        interval: Appearance.animation.elementMoveFast.duration
        repeat: false
        onTriggered: root.maybeApplyInitialScroll()
    }

    function toggleSportsDay(date) {
        if (eventSidebar.open && eventSidebar.mode === "day" && eventSidebar.sportsListOnly && H.sameDate(eventSidebar.day, date)) {
            eventSidebar.close();
            return;
        }
        eventSidebar.sportsListOnly = true;
        eventSidebar.showSportsDay(date);
    }

    function toggleDay(date) {
        if (eventSidebar.open && eventSidebar.mode === "day" && !eventSidebar.sportsListOnly && H.sameDate(eventSidebar.day, date)) {
            eventSidebar.close();
            return;
        }
        eventSidebar.sportsListOnly = false;
        eventSidebar.showDay(date);
    }

    function startCreate(date) {
        if (!CalendarService.khalAvailable)
            return;
        eventSidebar.sportsListOnly = false;
        eventSidebar.startCreate(date);
    }

    function rangeStartFor(date) {
        return root.viewMode === "week"
            ? H.weekStartFor(date, Config.options.time.firstDayOfWeek, Config.options.cheatsheet.timetableTodayFirst)
            : H.startOfDay(date);
    }

    function weekRangeLabel(compact) {
        const start = root.viewWeekStart;
        const end = root.viewWeekEnd;
        if (root.visibleDayCount === 1)
            return Qt.formatDate(start, compact ? "d MMM yyyy" : "dddd, d MMMM yyyy");
        const sameMonth = start.getFullYear() === end.getFullYear() && start.getMonth() === end.getMonth();
        const sameYear = start.getFullYear() === end.getFullYear();
        if (compact) {
            if (sameMonth)
                return String(start.getDate()) + " – " + Qt.formatDate(end, "d MMM");
            if (sameYear)
                return Qt.formatDate(start, "d MMM") + " – " + Qt.formatDate(end, "d MMM");
            return Qt.formatDate(start, "d MMM yy") + " – " + Qt.formatDate(end, "d MMM yy");
        }
        if (sameMonth)
            return String(start.getDate()) + " – " + Qt.formatDate(end, "d MMMM yyyy");
        if (sameYear)
            return Qt.formatDate(start, "d MMMM") + " – " + Qt.formatDate(end, "d MMMM yyyy");
        return Qt.formatDate(start, "d MMMM yyyy") + " – " + Qt.formatDate(end, "d MMMM yyyy");
    }

    function ensureDataForView() {
        CalendarService.ensureRangeCovers(root.viewWeekStart);
        CalendarService.ensureRangeCovers(root.viewWeekEnd);
    }

    function playWeekTransition(direction) {
        weekAnim.stop();
        root.weekShiftX = direction * 44;
        root.weekOpacity = 0;
        root.entranceKey++;
        weekAnim.start();
    }

    function goToWeek(date, direction = 0) {
        const target = root.rangeStartFor(date);
        const currentMs = root.viewWeekStart.getTime();
        const targetMs = target.getTime();
        root.followingCurrentWeek = H.sameDate(target, root.currentWeekStart);
        root.allDayExpanded = false;
        if (targetMs === currentMs) {
            root.playWeekTransition(0);
            return;
        }
        root.viewWeekStart = target;
        root.playWeekTransition(direction === 0 ? (targetMs > currentMs ? 1 : -1) : direction);
    }

    function shiftWeek(delta) {
        root.goToWeek(H.addDays(root.viewWeekStart, delta * root.visibleDayCount), delta >= 0 ? 1 : -1);
    }

    function goToday() {
        root.followingCurrentWeek = true;
        root.goToWeek(DateTime.clock.date, 0);
    }

    function focusKeyboardDate(date) {
        const target = H.startOfDay(date);
        const beforeRange = target.getTime() < H.startOfDay(root.viewWeekStart).getTime();
        const afterRange = target.getTime() > H.startOfDay(root.viewWeekEnd).getTime();
        root.keyboardDate = target;
        root.keyboardNavigationActive = true;
        if (beforeRange || afterRange)
            root.goToWeek(target, afterRange ? 1 : -1);
    }

    function scrollKeyboardHours(delta) {
        const target = styledFlickable.contentY + delta * root.slotHeight;
        styledFlickable.contentY = Math.max(0, Math.min(target, styledFlickable.contentHeight - styledFlickable.height));
    }

    function handleNavigationKey(event) {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            root.focusKeyboardDate(H.addDays(root.keyboardNavigationActive ? root.keyboardDate : (root.viewingCurrentWeek ? DateTime.clock.date : root.viewWeekStart), event.key === Qt.Key_Left ? -1 : 1));
            return true;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            root.keyboardNavigationActive = true;
            root.scrollKeyboardHours(event.key === Qt.Key_Up ? -1 : 1);
            return true;
        }
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            const delta = event.key === Qt.Key_PageUp ? -root.visibleDayCount : root.visibleDayCount;
            root.focusKeyboardDate(H.addDays(root.keyboardNavigationActive ? root.keyboardDate : root.viewWeekStart, delta));
            return true;
        }
        if (event.key === Qt.Key_Home) {
            root.goToday();
            root.focusKeyboardDate(DateTime.clock.date);
            return true;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.toggleDay(root.keyboardNavigationActive ? root.keyboardDate : (root.viewingCurrentWeek ? DateTime.clock.date : root.viewWeekStart));
            return true;
        }
        return false;
    }

    function toggleDayRail() {
        if (eventSidebar.open) {
            eventSidebar.close();
            return;
        }
        root.toggleDay(root.viewingCurrentWeek ? DateTime.clock.date : root.viewWeekStart);
    }

    function eventMinutes(date) {
        return date.getHours() * 60 + date.getMinutes();
    }

    function dayIndexForDate(date) {
        for (let index = 0; index < root.days.length; index++) {
            if (H.sameDate(root.days[index]?.sportsDate, date))
                return index;
        }
        return -1;
    }

    function gridPointAt(x, y) {
        const point = root.mapToItem(contentRow, x, y);
        const relativeX = point.x - root.timeColumnWidth - root.spacing;
        const stride = root.dayColumnWidth + root.spacing;
        const dayIndex = Math.floor(relativeX / stride);
        if (dayIndex < 0 || dayIndex >= root.dayCount || relativeX - dayIndex * stride > root.dayColumnWidth)
            return null;
        return { dayIndex: dayIndex, contentY: point.y };
    }

    function clampStart(minutes, duration) {
        const snapped = H.snapToGrid(minutes, 15);
        return Math.max(root.startHour * 60 + root.startMinute, Math.min(24 * 60 - duration, snapped));
    }

    function beginEventMove(event, x, y, pointerOffsetY) {
        if (!event?.uid || event.readOnly === true)
            return;
        const dayIndex = root.dayIndexForDate(event.startDate);
        if (dayIndex < 0)
            return;
        root.timedMutationEvent = event;
        root.timedMutationKind = "move";
        root.timedMutationPointerOffsetY = pointerOffsetY;
        root.timedMutationStartMinutes = root.eventMinutes(event.startDate);
        root.timedMutationEndMinutes = H.eventEndMinutes(event) ?? root.timedMutationStartMinutes;
        root.timedMutationDayIndex = dayIndex;
        root.updateEventMove(x, y);
    }

    function updateEventMove(x, y) {
        if (!root.timedMutationEvent || root.timedMutationKind !== "move")
            return;
        const target = root.gridPointAt(x, y);
        if (!target)
            return;
        const duration = root.timedMutationEndMinutes - root.timedMutationStartMinutes;
        const topY = target.contentY - root.timedMutationPointerOffsetY;
        root.timedMutationStartMinutes = root.clampStart(H.yToMinutes(topY, root.startHour, root.startMinute, root.pixelsPerMinute), duration);
        root.timedMutationEndMinutes = root.timedMutationStartMinutes + duration;
        root.timedMutationDayIndex = target.dayIndex;
    }

    function beginEventResize(event, x, y) {
        if (!event?.uid || event.readOnly === true)
            return;
        const dayIndex = root.dayIndexForDate(event.startDate);
        if (dayIndex < 0)
            return;
        root.timedMutationEvent = event;
        root.timedMutationKind = "resize";
        root.timedMutationStartMinutes = root.eventMinutes(event.startDate);
        root.timedMutationEndMinutes = H.eventEndMinutes(event) ?? root.timedMutationStartMinutes;
        root.timedMutationDayIndex = dayIndex;
        root.updateEventResize(x, y);
    }

    function updateEventResize(x, y) {
        if (!root.timedMutationEvent || root.timedMutationKind !== "resize")
            return;
        const target = root.gridPointAt(x, y);
        if (!target)
            return;
        const end = H.snapToGrid(H.yToMinutes(target.contentY, root.startHour, root.startMinute, root.pixelsPerMinute), 15);
        root.timedMutationEndMinutes = Math.max(root.timedMutationStartMinutes + 15, Math.min(24 * 60, end));
    }

    function isoForDayMinutes(date, minutes) {
        const value = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        value.setMinutes(minutes);
        return CalendarService.localIso(value, Qt.formatTime(value, "hh:mm"));
    }

    function commitTimedMutation() {
        const event = root.timedMutationEvent;
        const day = root.days[root.timedMutationDayIndex]?.sportsDate;
        const action = root.timedMutationKind;
        if (event?.uid && day && root.timedMutationEndMinutes > root.timedMutationStartMinutes) {
            eventSidebar.requestTimedMutation(event, {
                allDay: false,
                start: root.isoForDayMinutes(day, root.timedMutationStartMinutes),
                end: root.isoForDayMinutes(day, root.timedMutationEndMinutes)
            }, action);
        }
        root.cancelTimedMutation();
    }

    function cancelTimedMutation() {
        root.timedMutationEvent = null;
        root.timedMutationKind = "";
        root.timedMutationDayIndex = -1;
    }

    function requestWeekDelete(event) {
        if (!event?.uid || event.readOnly === true)
            return;
        if (String(event.repeatSymbol ?? "").length === 0) {
            CalendarService.deleteEventWithScope(event, "all");
            return;
        }
        eventSidebar.showEvent(event);
        eventSidebar.requestDelete();
    }

    // ─── Actions ───
    function openPopupForGhost() {
        let topMin = H.snapToGrid(H.yToMinutes(root.ghostTopY, root.startHour, root.startMinute, root.pixelsPerMinute), 15);
        let botMin = H.snapToGrid(H.yToMinutes(root.ghostTopY + root.ghostHeight, root.startHour, root.startMinute, root.pixelsPerMinute), 15);
        let eventDate = root.days[root.ghostDayIndex]?.sportsDate ?? root.viewWeekStart;
        eventSidebar.sportsListOnly = false;
        eventSidebar.startCreateAt(eventDate, topMin, botMin);
    }

    function openPopupForEdit(event, dayIndex) {
        if (event?.sportEvent === true) {
            eventSidebar.showEvent(event);
            return;
        }
        eventSidebar.startEdit(event);
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

    Connections {
        target: DateTime.clock
        function onDateChanged() {
            root.updateCurrentTimeLine();
            root.updateNextEvent();
        }
    }

    onClockDayKeyChanged: {
        if (root.followingCurrentWeek)
            root.viewWeekStart = root.currentWeekStart;
        root.requestedSportsRange = "";
        root.requestSportsRange();
    }
    Connections {
        target: CalendarService
        function onEventsByDayChanged() {
            root.updateNextEvent();
            root.maybeApplyInitialScroll();
        }
    }
    Connections {
        target: Config.options.cheatsheet
        function onTimetableTodayFirstChanged() {
            const focus = root.followingCurrentWeek ? DateTime.clock.date : root.viewWeekStart;
            root.viewWeekStart = root.rangeStartFor(focus);
            root.refreshVisibleRange();
        }
    }
    Connections {
        target: Config.options.calendar.timetable
        function onProximityColorGradientChanged() {
            root.updateNextEvent();
        }
    }
    Connections {
        target: Config.options.time
        function onFirstDayOfWeekChanged() {
            const focus = root.followingCurrentWeek ? DateTime.clock.date : root.viewWeekStart;
            root.viewWeekStart = root.rangeStartFor(focus);
            root.refreshVisibleRange();
        }
    }

    onViewModeChanged: {
        if (!root.componentReady)
            return;
        const focus = root.followingCurrentWeek ? DateTime.clock.date : root.viewWeekStart;
        root.viewWeekStart = root.rangeStartFor(focus);
        root.allDayExpanded = false;
        root.restartDayLoading();
        root.refreshVisibleRange();
    }

    function requestSportsRange() {
        if (!root.sportsEnabled || !root.initialLoadComplete)
            return;
        const fromDate = root.viewWeekStart;
        const toDate = root.viewWeekEnd;
        const range = Qt.formatDate(fromDate, "yyyy-MM-dd") + "|" + Qt.formatDate(toDate, "yyyy-MM-dd");
        if (range === root.requestedSportsRange)
            return;
        root.requestedSportsRange = range;
        SportsService.requestTimetableRange(fromDate, toDate);
    }

    function refreshVisibleRange() {
        root.requestedSportsRange = "";
        root.ensureDataForView();
        root.updateNextEvent();
        Qt.callLater(root.requestSportsRange);
    }

    onViewWeekStartChanged: root.refreshVisibleRange()

    function restartDayLoading() {
        root.loadedDayCount = -1;
        root.requestedSportsRange = "";
        Qt.callLater(() => root.loadedDayCount = 0);
    }

    function advanceDayLoading(index) {
        if (index !== root.loadedDayCount || index >= root.dayCount)
            return;
        root.loadedDayCount = index + 1;
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
        root.normalizeSlotHeight();
        root.componentReady = true;
        root.restartDayLoading();
        root.ensureDataForView();
        root.updateCurrentTimeLine();
        root.updateNextEvent();
        root.maybeApplyInitialScroll();
    }

    ParallelAnimation {
        id: weekAnim

        NumberAnimation {
            target: root
            property: "weekShiftX"
            to: 0
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }

        NumberAnimation {
            target: root
            property: "weekOpacity"
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.OutCubic
        }
    }

    // The surface is owned by CheatsheetTimetable so both views sit on the
    // same borderless plate and can cross-fade without one drawing a second
    // background over the other.

    ColumnLayout {
        id: timetablePane
        anchors.fill: parent
        anchors.rightMargin: eventSidebar.open ? root.eventRailWidth + 14 : 0
        spacing: 0

        Behavior on anchors.rightMargin {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        RowLayout {
            id: navBar
            Layout.fillWidth: true
            Layout.preferredHeight: root.navBarHeight
            spacing: 8

            RippleButton {
                id: weekTitleButton
                Layout.fillWidth: true
                implicitHeight: 52
                buttonRadius: Appearance.rounding.normal
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colBackgroundActive: Appearance.colors.colLayer1Active
                onClicked: {
                    datePicker.purpose = "navigate";
                    datePicker.open(root.viewWeekStart, root.viewMode === "day" ? Translation.tr("Go to day") : Translation.tr("Go to range"));
                }

                contentItem: Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: -2

                    StyledText {
                        width: parent.width
                        text: root.weekRangeLabel(root.compactNav)
                        font.family: Appearance.font.family.title
                        font.pixelSize: root.compactNav ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.hugeass
                        font.weight: Font.Bold
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                        animateChange: true
                        animationDistanceX: 0
                        animationDistanceY: 10
                    }

                    StyledText {
                        width: parent.width
                        text: root.viewingCurrentWeek
                            ? (root.viewMode === "day"
                                ? Translation.tr("Today")
                                : (root.viewMode === "threeDay" ? Translation.tr("Next 3 days") : Translation.tr("This week")))
                            : (root.viewWeekStart.getFullYear() === root.viewWeekEnd.getFullYear()
                                ? String(root.viewWeekStart.getFullYear())
                                : String(root.viewWeekStart.getFullYear()) + " – " + String(root.viewWeekEnd.getFullYear()))
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        font.weight: Font.Bold
                        color: root.viewingCurrentWeek ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                StyledToolTip {
                    extraVisibleCondition: weekTitleButton.hovered
                    text: root.viewMode === "day" ? Translation.tr("Choose day") : Translation.tr("Choose range")
                }
            }

            RippleButton {
                id: dayRailToggle
                visible: root.usableWidth >= 1000
                implicitWidth: 42
                implicitHeight: 42
                buttonRadius: Appearance.rounding.full
                toggled: eventSidebar.open
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: root.toggleDayRail()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "view_sidebar"
                    iconSize: Appearance.font.pixelSize.larger
                    color: eventSidebar.open ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                }

                StyledToolTip {
                    extraVisibleCondition: dayRailToggle.hovered
                    text: eventSidebar.open ? Translation.tr("Hide day details") : Translation.tr("Show day details")
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
                onClicked: root.shiftWeek(-1)

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
                onClicked: root.shiftWeek(1)

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

            FloatingActionButton {
                id: newEventButton
                Layout.alignment: Qt.AlignVCenter
                baseSize: 48
                buttonRadius: Appearance.rounding.full
                iconText: "add"
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colOnBackground: Appearance.colors.colOnPrimary
                enabled: CalendarService.khalAvailable
                onClicked: root.startCreate(root.viewingCurrentWeek ? DateTime.clock.date : root.viewWeekStart)

                StyledToolTip {
                    extraVisibleCondition: newEventButton.hovered
                    text: CalendarService.khalAvailable ? Translation.tr("New event") : Translation.tr("Calendar service unavailable")
                }
            }
        }

        Item {
            id: weekContent
            Layout.fillWidth: true
            Layout.fillHeight: true
            opacity: root.weekOpacity
            transform: Translate {
                x: root.weekShiftX
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                TimetableHeader {
                    id: headerRow
                    Layout.fillWidth: true
                    headerHeight: root.headerHeight
                    itemSpacing: root.spacing
                    timeColumnWidth: root.timeColumnWidth
                    dayColumnWidth: root.dayColumnWidth
                    days: (root.days ?? []).slice(0, Math.max(0, root.loadedDayCount))
                    currentDayIndex: root.currentDayIndex
                    keyboardDate: root.keyboardDate
                    keyboardNavigationActive: root.keyboardNavigationActive
                    allDayChipHeight: root.allDayChipHeight
                    allDayChipSpacing: root.allDayChipSpacing
                    visibleAllDayRows: root.visibleAllDayRows
                    allDayExpanderHeight: root.allDayExpanderHeight
                    expanded: root.allDayExpanded
                    hasExpandableLane: root.hasExpandableAllDayLane
                    onDayActivated: date => root.toggleDay(date)
                    onSportsDayActivated: date => root.toggleSportsDay(date)
                    onAllDayExpansionRequested: expanded => root.allDayExpanded = expanded
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Appearance.colors.colOutlineVariant
                    Layout.bottomMargin: 8
                }

                StyledFlickable {
                    id: styledFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: root.contentHeight
                    topMargin: 20
                    bottomMargin: 20

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        acceptedModifiers: Qt.ControlModifier
                        onWheel: event => {
                            const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                            root.zoomWheelAccumulator += delta;
                            if (Math.abs(root.zoomWheelAccumulator) >= 60) {
                                root.zoomSlotHeight(root.zoomWheelAccumulator > 0 ? 1 : -1, event.y);
                                root.zoomWheelAccumulator = 0;
                            }
                            event.accepted = true;
                        }
                    }

            Row {
                id: contentRow
                spacing: root.spacing

                TimetableTimeColumn {
                    totalSlots: root.totalSlots
                    slotHeight: root.slotHeight
                    slotDuration: root.slotDuration
                    startMinute: root.startMinute
                    timeColumnWidth: root.timeColumnWidth
                }

                Item {
                    id: eventsRow
                    width: root.dayCount * root.dayColumnWidth + Math.max(0, root.dayCount - 1) * root.spacing
                    height: root.contentHeight

                    Item {
                        id: gridLineLayer
                        anchors.fill: parent
                        z: -1

                        Repeater {
                            model: root.totalSlots

                            delegate: Item {
                                required property int index
                                x: 0
                                y: index * root.slotHeight
                                width: gridLineLayer.width
                                height: root.slotHeight

                                Rectangle {
                                    anchors.top: parent.top
                                    width: parent.width
                                    height: 1
                                    color: H.withOpacity(Appearance.colors.colOutlineVariant, 0.30)
                                }

                                Rectangle {
                                    y: parent.height / 2
                                    width: parent.width
                                    height: 1
                                    color: H.withOpacity(Appearance.colors.colOutlineVariant, 0.14)
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: H.withOpacity(Appearance.colors.colOutlineVariant, 0.30)
                        }
                    }

                    Row {
                        anchors.fill: parent
                        spacing: root.spacing

                        Repeater {
                            model: root.days ?? []

                            delegate: Loader {
                                id: dayLoader

                                required property int index
                                required property var modelData

                                width: root.dayColumnWidth
                                height: root.contentHeight
                                active: index <= root.loadedDayCount
                                asynchronous: true

                                onLoaded: root.advanceDayLoading(index)

                                sourceComponent: TimetableDayColumn {
                                    id: dayColDelegate

                                    property int revealKey: root.entranceKey

                                    dayIdx: dayLoader.index
                                    dayData: dayLoader.modelData
                                    isToday: dayLoader.index === root.currentDayIndex
                                    dayColumnWidth: root.dayColumnWidth
                                    contentHeight: root.contentHeight
                                    pixelsPerMinute: root.pixelsPerMinute
                                    eventSpacing: root.spacing / 2
                                    startHour: root.startHour
                                    startMinute: root.startMinute
                                    snapInterval: 15
                                    coordinateRoot: root
                                    draggedEvent: root.timedMutationEvent
                                    ghostVisible: root.ghostVisible
                                    ghostDayIndex: root.ghostDayIndex
                                    ghostTopY: root.ghostTopY
                                    ghostHeight: root.ghostHeight
                                    nextEventData: root.nextEventData
                                    maxLogicalDistance: root.maxLogicalDistance
                                    todayHighlightFill: root.todayHighlightFill
                                    dayBackgroundFill: root.dayBackgroundFill
                                    dayBackgroundFillVariant: root.dayBackgroundFillVariant

                                    opacity: 0
                                    transform: Translate { id: colTrans; y: 15 }

                                    function replayEntrance() {
                                        colAnim.stop();
                                        animTimer.stop();
                                        dayColDelegate.opacity = 0;
                                        colTrans.y = 15;
                                        animTimer.start();
                                    }

                                    onRevealKeyChanged: dayColDelegate.replayEntrance()
                                    Component.onCompleted: dayColDelegate.replayEntrance()

                                    Timer {
                                        id: animTimer
                                        interval: dayLoader.index * 70
                                        repeat: false
                                        onTriggered: colAnim.start()
                                    }

                                    ParallelAnimation {
                                        id: colAnim
                                        NumberAnimation {
                                            target: colTrans
                                            property: "y"
                                            to: 0
                                            duration: Appearance.animation.elementMoveEnter.duration
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                                        }
                                        NumberAnimation {
                                            target: dayColDelegate
                                            property: "opacity"
                                            to: 1
                                            duration: Appearance.animation.elementMoveFast.duration
                                            easing.type: Easing.OutCubic
                                        }
                                    }

                                    onDragRequestInteractivity: i => root.setTimetableDragActive(!i)
                                    onDragReleased: (dIdx, sY, cY) => {
                                        let dist = Math.abs(cY - sY);
                                        if (dist < 10) {
                                            let clickMin = H.snapToGrid(H.yToMinutes(sY, root.startHour, root.startMinute, root.pixelsPerMinute), 15);
                                            root.ghostTopY = H.minutesToY(clickMin, root.startHour, root.startMinute, root.pixelsPerMinute);
                                            root.ghostHeight = H.minutesToY(clickMin + 60, root.startHour, root.startMinute, root.pixelsPerMinute) - root.ghostTopY;
                                        } else {
                                            let topMin = H.snapToGrid(H.yToMinutes(Math.min(sY, cY), root.startHour, root.startMinute, root.pixelsPerMinute), 15);
                                            let botMin = H.snapToGrid(H.yToMinutes(Math.max(sY, cY), root.startHour, root.startMinute, root.pixelsPerMinute), 15);
                                            if (botMin - topMin < 15)
                                                botMin = topMin + 15;
                                            root.ghostTopY = H.minutesToY(topMin, root.startHour, root.startMinute, root.pixelsPerMinute);
                                            root.ghostHeight = H.minutesToY(botMin, root.startHour, root.startMinute, root.pixelsPerMinute) - root.ghostTopY;
                                        }
                                        root.ghostDayIndex = dIdx;
                                        root.ghostVisible = true;
                                        Qt.callLater(root.openPopupForGhost);
                                    }
                                    onEditRequested: (evt, dIdx) => root.openPopupForEdit(evt, dIdx)
                                    onDeleteRequested: (evt, dIdx) => root.requestWeekDelete(evt)
                                    onEventMoveStarted: (evt, x, y, offsetY) => {
                                        root.setTimetableDragActive(true);
                                        root.beginEventMove(evt, x, y, offsetY);
                                    }
                                    onEventMoveMoved: (x, y) => root.updateEventMove(x, y)
                                    onEventMoveEnded: {
                                        root.commitTimedMutation();
                                        root.setTimetableDragActive(false);
                                    }
                                    onEventMoveCanceled: {
                                        root.cancelTimedMutation();
                                        root.setTimetableDragActive(false);
                                    }
                                    onEventResizeStarted: (evt, x, y) => {
                                        root.setTimetableDragActive(true);
                                        root.beginEventResize(evt, x, y);
                                    }
                                    onEventResizeMoved: (x, y) => root.updateEventResize(x, y)
                                    onEventResizeEnded: {
                                        root.commitTimedMutation();
                                        root.setTimetableDragActive(false);
                                    }
                                    onEventResizeCanceled: {
                                        root.cancelTimedMutation();
                                        root.setTimetableDragActive(false);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            TimetableCurrentTime {
                currentTimeY: root.currentTimeY
                contentRowWidth: contentRow.width
                timeColumnWidth: root.timeColumnWidth
                visible: root.currentDayIndex >= 0 && root.currentTimeY >= 0 && root.currentTimeY <= contentRow.height
            }
        }
    }
        }
    }

    TimetableNextEventFAB {
        nextEventData: root.nextEventData
        headerHeight: root.navBarHeight + root.headerHeight
        timeColumnWidth: root.timeColumnWidth
        dayColumnWidth: root.dayColumnWidth
        itemSpacing: root.spacing
        contentY: styledFlickable.contentY
        flickableHeight: styledFlickable.height
        flickableContentHeight: styledFlickable.contentHeight
        pixelsPerMinute: root.pixelsPerMinute
        startHour: root.startHour
        startMinute: root.startMinute
        onScrollRequested: y => styledFlickable.contentY = Math.min(y, Math.max(0, styledFlickable.contentHeight - styledFlickable.height))
    }

    Rectangle {
        id: timedMutationProxy
        visible: root.timedMutationEvent !== null && root.timedMutationDayIndex >= 0
        z: 24
        width: Math.max(32, root.dayColumnWidth - 10)
        height: H.timedBlockHeight(root.timedMutationStartMinutes, root.timedMutationEndMinutes, root.pixelsPerMinute, root.spacing / 2)
        radius: Appearance.rounding.normal
        color: H.chipColor(root.timedMutationEvent, Appearance.colors, GoogleCalendarService.colorForEvent(root.timedMutationEvent))
        opacity: 0.96
        x: {
            const point = eventsRow.mapToItem(root, root.timedMutationDayIndex * (root.dayColumnWidth + root.spacing) + 5, 0);
            return point.x;
        }
        y: {
            const point = eventsRow.mapToItem(root, 0, H.minutesToY(root.timedMutationStartMinutes, root.startHour, root.startMinute, root.pixelsPerMinute));
            return point.y;
        }

        StyledText {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: Text.AlignVCenter
            text: root.timedMutationEvent?.content ?? ""
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: ColorUtils.getContrastingTextColor(timedMutationProxy.color)
            elide: Text.ElideRight
        }
    }

    Item {
        anchors {
            top: parent.top
            right: parent.right
            bottom: parent.bottom
        }
        width: eventSidebar.open ? root.eventRailWidth : 0
        clip: true
        z: 30

        Behavior on width {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        EventSidebar {
            id: eventSidebar
            anchors.fill: parent
            sportsListOnly: false
            onSaveRequested: payload => root.applySidebarPayload(payload)
            onCloseRequested: root.clearGhostPreview()
            onTaskCreateRequested: task => Todo.addItem(task)
            onTaskCompletionRequested: task => Todo.markDone(task)
            onDeleteRequested: (eventData, scope) => CalendarService.deleteEventWithScope(eventData, scope)
            onEventFieldsMutationRequested: (eventData, fields, scope) => CalendarService.saveEventFields(eventData, fields, scope)
            onMoveRequested: (eventData, newDate, scope) => {
                if (!eventData || !newDate)
                    return;
                CalendarService.moveEvent(eventData, newDate, scope);
                root.viewWeekStart = root.rangeStartFor(newDate);
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

    TimePickerPopup {
        id: timePicker
        anchors.fill: parent
        z: 50
        property string target: "start"
        onAccepted: (pickedHour, pickedMinute) => eventSidebar.applyPickedTime(timePicker.target, pickedHour, pickedMinute)
    }

    DatePickerPopup {
        id: datePicker
        anchors.fill: parent
        z: 50
        property string purpose: "form"
        onAccepted: pickedDate => {
            if (datePicker.purpose === "navigate") {
                root.goToWeek(pickedDate);
                return;
            }
            eventSidebar.applyPickedDate(datePicker.purpose, pickedDate);
        }
    }
}
