import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import qs.modules.common.functions
import "./timetable"
import "timetable/TimetableHelpers.js" as H

Item {
    id: root
    property real spacing: 8

    readonly property bool eventPopupVisible: eventPopup.visible

    property int startHour: 0
    property int startMinute: 0
    property int endHour: 24
    property int slotDuration: 60 // in minutes
    property int slotHeight: 120 // in pixels
    property int timeColumnWidth: 100
    property real maxContentWidth: 1600

    readonly property int totalSlots: Math.floor(((endHour * 60) - (startHour * 60 + startMinute)) / slotDuration)
    readonly property real pixelsPerMinute: slotHeight / slotDuration
    readonly property int contentHeight: totalSlots * slotHeight

    property real maxHeight: 700
    property real headerHeight: 64 + (hasAllDayEvents ? maxAllDayEventCount * (allDayChipHeight + allDayChipSpacing) + 8 : 0)
    property real currentTimeY: -1
    property bool initialScrollApplied: false
    readonly property real dayColumnWidth: {
        let availableWidth = root.width > 0 ? root.width : maxContentWidth;
        return Math.max(80, (availableWidth - timeColumnWidth - days.length * spacing) / Math.max(1, days.length));
    }
    readonly property int currentDayIndex: (DateTime.clock.date.getDay() - Config.options.time.firstDayOfWeek + 6) % 7

    implicitWidth: maxContentWidth
    implicitHeight: Math.min(headerHeight + contentHeight, maxHeight)
    property var days: CalendarService.eventsInWeek
    readonly property int allDayChipHeight: 36
    readonly property int allDayChipSpacing: 6
    readonly property int maxAllDayEventCount: {
        if (!root.days || root.days.length === 0)
            return 0;
        let maxCount = 0;
        for (let i = 0; i < root.days.length; i++) {
            let count = H.getAllDayEvents(root.days[i]?.events).length;
            if (count > maxCount)
                maxCount = count;
        }
        return maxCount;
    }
    readonly property bool hasAllDayEvents: maxAllDayEventCount > 0

    // ─── Theme Colors ───
    readonly property color todayHighlightFill: H.withOpacity(Appearance.colors.colPrimary, 0.12)
    readonly property color todayHighlightBorder: H.withOpacity(Appearance.colors.colPrimary, 0.28)
    readonly property color dayBackgroundFill: H.withOpacity(Appearance.colors.colSecondary, 0.04)
    readonly property color dayBackgroundFillVariant: H.withOpacity(Appearance.colors.colSecondary, 0.08)

    // ─── State ───
    property var nextEventData: null
    property real maxLogicalDistance: 1.0

    property bool ghostVisible: false
    property int ghostDayIndex: -1
    property real ghostTopY: 0
    property real ghostHeight: 0

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
            let events = H.getTimedEvents(root.days[i]?.events);
            for (let evt of events) {
                let startMins = H.parseTimeToMinutes(evt.start);
                let endMins = H.parseTimeToMinutes(evt.end);
                if (startMins === null)
                    continue;
                if (endMins === null || (endMins === 0 && startMins > 0))
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
                for (let evt of H.getTimedEvents(root.days[i]?.events)) {
                    let startMins = H.parseTimeToMinutes(evt.start);
                    if (startMins === null)
                        continue;
                    let evtStartTotal = i * 24 * 60 + startMins;
                    if (evtStartTotal < earliestTotal) {
                        earliestTotal = evtStartTotal;
                        nextEvt = {
                            dayIndex: i,
                            startMinutes: startMins,
                            endMinutes: H.parseTimeToMinutes(evt.end)
                        };
                    }
                }
            }
        }

        root.nextEventData = nextEvt;

        let maxDist = 0;
        if (nextEvt) {
            for (let i = 0; i < root.days.length; i++) {
                for (let evt of H.getTimedEvents(root.days[i]?.events)) {
                    let startMins = H.parseTimeToMinutes(evt.start);
                    if (startMins === null)
                        continue;
                    let dist = Math.sqrt(Math.pow(i - nextEvt.dayIndex, 2) + Math.pow((startMins - nextEvt.startMinutes) / 60.0, 2));
                    if (dist > maxDist)
                        maxDist = dist;
                }
            }
        }
        root.maxLogicalDistance = Math.max(1.0, maxDist);
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

    function maybeApplyInitialScroll() {
        if (root.initialScrollApplied || !styledFlickable || styledFlickable.height <= 0 || !root.days || root.days.length === 0) {
            Qt.callLater(root.maybeApplyInitialScroll);
            return;
        }
        root.scrollToCurrentTime();
        root.initialScrollApplied = true;
    }

    // ─── Actions ───
    function openPopupForGhost() {
        let topMin = H.snapToGrid(H.yToMinutes(root.ghostTopY, root.startHour, root.startMinute, root.pixelsPerMinute), 15);
        let botMin = H.snapToGrid(H.yToMinutes(root.ghostTopY + root.ghostHeight, root.startHour, root.startMinute, root.pixelsPerMinute), 15);
        let eventDate = H.getDateForDayIndex(root.ghostDayIndex, Config.options.time.firstDayOfWeek);
        let colX = root.timeColumnWidth + (root.ghostDayIndex * (root.dayColumnWidth + root.spacing)) + root.dayColumnWidth;
        let colY = root.ghostTopY + root.headerHeight - styledFlickable.contentY + 20;
        eventPopup.open(H.minutesToTimeStr(topMin, Config.options?.time.format), H.minutesToTimeStr(botMin, Config.options?.time.format), eventDate, root.ghostDayIndex, colX, colY);
    }

    function openPopupForEdit(event, dayIndex) {
        let startMin = H.parseTimeToMinutes(event.start);
        let endMin = H.parseTimeToMinutes(event.end);
        let eventDate = H.getDateForDayIndex(dayIndex, Config.options.time.firstDayOfWeek);
        let colX = root.timeColumnWidth + (dayIndex * (root.dayColumnWidth + root.spacing)) + root.dayColumnWidth;
        let colY = H.minutesToY(startMin, root.startHour, root.startMinute, root.pixelsPerMinute) + root.headerHeight - styledFlickable.contentY + 20;
        eventPopup.openForEdit(H.minutesToTimeStr(startMin, Config.options?.time.format), H.minutesToTimeStr(endMin, Config.options?.time.format), eventDate, dayIndex, colX, colY, event);
    }

    Connections {
        target: DateTime.clock
        function onDateChanged() {
            root.updateCurrentTimeLine();
            root.updateNextEvent();
        }
    }
    Connections {
        target: CalendarService
        function onEventsInWeekChanged() {
            root.updateNextEvent();
            Qt.callLater(root.maybeApplyInitialScroll);
        }
    }
    Component.onCompleted: {
        root.updateCurrentTimeLine();
        root.updateNextEvent();
        Qt.callLater(root.maybeApplyInitialScroll);
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainer
        radius: Appearance.rounding.large
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
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
            days: root.days
            currentDayIndex: root.currentDayIndex
            allDayChipHeight: root.allDayChipHeight
            allDayChipSpacing: root.allDayChipSpacing
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

                Row {
                    id: eventsRow
                    height: root.contentHeight
                    spacing: root.spacing
                    Repeater {
                        model: root.days
                        delegate: TimetableDayColumn {
                            dayIdx: index
                            dayData: modelData
                            isToday: index === root.currentDayIndex
                            dayColumnWidth: root.dayColumnWidth
                            contentHeight: root.contentHeight
                            pixelsPerMinute: root.pixelsPerMinute
                            startHour: root.startHour
                            startMinute: root.startMinute
                            snapInterval: 15
                            ghostVisible: root.ghostVisible
                            ghostDayIndex: root.ghostDayIndex
                            ghostTopY: root.ghostTopY
                            ghostHeight: root.ghostHeight
                            nextEventData: root.nextEventData
                            maxLogicalDistance: root.maxLogicalDistance
                            todayHighlightFill: root.todayHighlightFill
                            todayHighlightBorder: root.todayHighlightBorder
                            dayBackgroundFill: root.dayBackgroundFill
                            dayBackgroundFillVariant: root.dayBackgroundFillVariant

                            onDragRequestInteractivity: i => styledFlickable.interactive = i
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
                        }
                    }
                }
            }

            TimetableCurrentTime {
                currentTimeY: root.currentTimeY
                contentRowWidth: contentRow.width
                timeColumnWidth: root.timeColumnWidth
                visible: root.currentTimeY >= 0 && root.currentTimeY <= contentRow.height
            }
        }
    }

    TimetableNextEventFAB {
        nextEventData: root.nextEventData
        headerHeight: root.headerHeight
        timeColumnWidth: root.timeColumnWidth
        dayColumnWidth: root.dayColumnWidth
        spacing: root.spacing
        contentY: styledFlickable.contentY
        flickableHeight: styledFlickable.height
        flickableContentHeight: styledFlickable.contentHeight
        pixelsPerMinute: root.pixelsPerMinute
        startHour: root.startHour
        startMinute: root.startMinute
        onScrollRequested: y => styledFlickable.contentY = Math.min(y, Math.max(0, styledFlickable.contentHeight - styledFlickable.height))
    }

    EventCreationPopup {
        id: eventPopup
        anchors.fill: parent
        z: 50
        onEventCreated: (title, description) => {
            let topMin = H.snapToGrid(H.yToMinutes(root.ghostTopY, root.startHour, root.startMinute, root.pixelsPerMinute), 15);
            let botMin = H.snapToGrid(H.yToMinutes(root.ghostTopY + root.ghostHeight, root.startHour, root.startMinute, root.pixelsPerMinute), 15);
            CalendarService.addEvent(H.getDateForDayIndex(root.ghostDayIndex, Config.options.time.firstDayOfWeek), H.minutesToKhalTimeStr(topMin), H.minutesToKhalTimeStr(botMin), title, description);
            root.ghostVisible = false;
        }
        onEventUpdated: (oldTitle, title, description) => {
            let evt = eventPopup.editEventData;
            if (!evt)
                return;
            let startMin = H.parseTimeToMinutes(evt.start);
            let endMin = H.parseTimeToMinutes(evt.end);
            if (endMin === 0 && startMin > 0)
                endMin = 24 * 60;
            if (evt.uid)
                CalendarService.removeEventByUid(evt.uid);
            else
                CalendarService.removeEvent(oldTitle);
            CalendarService.addEvent(H.getDateForDayIndex(eventPopup.dayIndex, Config.options.time.firstDayOfWeek), H.minutesToKhalTimeStr(startMin), H.minutesToKhalTimeStr(endMin), title, description);
        }
        onEventDeleted: title => {
            if (eventPopup.editEventData?.uid)
                CalendarService.removeEventByUid(eventPopup.editEventData.uid);
            else
                CalendarService.removeEvent(title);
            root.ghostVisible = false;
        }
        onCancelled: root.ghostVisible = false
    }
}
