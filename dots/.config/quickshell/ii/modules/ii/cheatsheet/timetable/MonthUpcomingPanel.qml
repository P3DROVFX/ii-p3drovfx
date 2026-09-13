import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import "TimetableHelpers.js" as H

/**
 * Left rail of the month view: today at a glance, then every day that has
 * something on it within the horizon. Read-only apart from opening an event —
 * the grid stays the place where things are created and moved.
 */
Item {
    id: root

    property int horizonDays: Math.max(1, Math.min(60, Config.options.calendar.timetable.upcomingHorizonDays ?? 14))
    property int entranceKey: 0
    property string categoryFilter: ""
    property var holidaysByDay: ({})

    signal eventActivated(var eventData)
    signal dateActivated(var date)

    readonly property date todayDate: DateTime.clock.date

    readonly property var todayTasks: Todo.getTasksByDate(root.todayDate)
        .filter(task => task?.hasDate === true)
    readonly property var overdueTasks: Todo.getOverdueTasks(root.todayDate)
    readonly property var todayEvents: {
        let events = CalendarService.eventsByDay[H.dayKeyOf(root.todayDate)] ?? [];
        if (root.categoryFilter)
            events = events.filter(event => (event.categories ?? []).includes(root.categoryFilter));
        return events;
    }

    function groupForOffset(offset, today) {
        if (offset === 0)
            return "today";
        if (offset === 1)
            return "tomorrow";
        const weekEnd = H.addDays(H.weekStartFor(today, Config.options.time.firstDayOfWeek, false), 6);
        return H.startOfDay(H.addDays(today, offset)).getTime() <= H.startOfDay(weekEnd).getTime() ? "thisWeek" : "later";
    }

    function groupLabel(key) {
        switch (key) {
        case "today": return Translation.tr("Today");
        case "tomorrow": return Translation.tr("Tomorrow");
        case "thisWeek": return Translation.tr("This week");
        default: return Translation.tr("Later");
        }
    }

    function isGroupCollapsed(key) {
        return (Persistent.states.cheatsheet.timetableCollapsedUpcomingGroups ?? []).includes(key);
    }

    function toggleGroup(key) {
        const collapsed = Array.from(Persistent.states.cheatsheet.timetableCollapsedUpcomingGroups ?? []);
        Persistent.states.cheatsheet.timetableCollapsedUpcomingGroups = collapsed.includes(key)
            ? collapsed.filter(item => item !== key)
            : collapsed.concat([key]);
    }

    readonly property var groups: {
        const buckets = {
            today: [],
            tomorrow: [],
            thisWeek: [],
            later: []
        };
        const now = DateTime.clock.date;
        const today = H.startOfDay(now);

        for (let i = 0; i < root.overdueTasks.length; i++) {
            buckets.today.push({
                rowType: "task",
                rowKey: "task:overdue:" + (root.overdueTasks[i].id || root.overdueTasks[i].content || i),
                groupKey: "today",
                date: today,
                overdue: true,
                task: root.overdueTasks[i]
            });
        }

        for (let offset = 0; offset < root.horizonDays; offset++) {
            const date = H.addDays(today, offset);
            const key = H.dayKeyOf(date);
            const groupKey = root.groupForOffset(offset, today);
            const dayHolidays = root.holidaysByDay[key] ?? [];
            let dayEvents = CalendarService.eventsByDay[key] ?? [];
            if (root.categoryFilter)
                dayEvents = dayEvents.filter(event => (event.categories ?? []).includes(root.categoryFilter));
            const dayBirthdays = BirthdaysService.birthdaysForDate(date);
            const dayTasks = Todo.getTasksByDate(date).filter(task => !root.overdueTasks.some(overdue => overdue === task || String(overdue?.id ?? "") === String(task?.id ?? "")));

            // Today's list is about what is left of today, not what already ran.
            if (offset === 0)
                dayEvents = dayEvents.filter(evt => CalendarService.isAllDayEvent(evt) || (evt.endDate && evt.endDate.getTime() >= now.getTime()));

            if (dayEvents.length === 0 && dayBirthdays.length === 0 && dayHolidays.length === 0 && dayTasks.length === 0)
                continue;

            for (let i = 0; i < dayHolidays.length; i++) {
                buckets[groupKey].push({
                    rowType: "holiday",
                    rowKey: "hol:" + key + ":" + i,
                    groupKey: groupKey,
                    date: date,
                    offset: offset,
                    label: dayHolidays[i].localName || dayHolidays[i].name || ""
                });
            }
            for (let i = 0; i < dayEvents.length; i++) {
                buckets[groupKey].push({
                    rowType: "event",
                    rowKey: "evt:" + key + ":" + (dayEvents[i].uid || dayEvents[i].content || i),
                    groupKey: groupKey,
                    date: date,
                    offset: offset,
                    event: dayEvents[i]
                });
            }
            for (let i = 0; i < dayBirthdays.length; i++) {
                buckets[groupKey].push({
                    rowType: "birthday",
                    rowKey: "birthday:" + key + ":" + (dayBirthdays[i].contactId || dayBirthdays[i].id || i),
                    groupKey: groupKey,
                    date: date,
                    offset: offset,
                    birthday: dayBirthdays[i]
                });
            }
            for (let i = 0; i < dayTasks.length; i++) {
                buckets[groupKey].push({
                    rowType: "task",
                    rowKey: "task:" + key + ":" + (dayTasks[i].id || dayTasks[i].content || i),
                    groupKey: groupKey,
                    date: date,
                    offset: offset,
                    task: dayTasks[i]
                });
            }
        }

        const out = [];
        for (const key of ["today", "tomorrow", "thisWeek", "later"]) {
            if (buckets[key].length === 0)
                continue;
            out.push({ key: key, label: root.groupLabel(key), items: buckets[key] });
        }
        return out;
    }

    readonly property var rows: {
        const out = [];
        const collapsedGroups = Persistent.states.cheatsheet.timetableCollapsedUpcomingGroups ?? [];
        for (const group of root.groups) {
            out.push({
                rowType: "group",
                rowKey: "group:" + group.key,
                groupKey: group.key,
                label: group.label,
                count: group.items.length,
                collapsed: collapsedGroups.includes(group.key)
            });
            if (!collapsedGroups.includes(group.key))
                out.push(...group.items);
        }
        return out;
    }

    readonly property int upcomingCount: root.groups.reduce((count, group) => count + group.items.filter(row => row.rowType === "event" || row.rowType === "birthday" || row.rowType === "task").length, 0)
    // The rail has one visual focal point: an event already in progress wins;
    // otherwise it is the earliest future event. The key is computed from the
    // rows so recurring occurrences remain distinct from one another.
    readonly property string featuredEventRowKey: {
        const now = DateTime.clock.date;
        const nowMs = now.getTime();
        let current = null;
        let next = null;

        for (const group of root.groups) {
            for (const row of group.items) {
                if (row?.rowType !== "event" || !row.event?.startDate)
                    continue;
            const event = row.event;
            const startMs = event.startDate.getTime();
            const endMs = (event.endDate ?? event.startDate).getTime();
            const allDayToday = CalendarService.isAllDayEvent(event) && H.sameDate(row.date, now);
            const inProgress = allDayToday || (startMs <= nowMs && endMs >= nowMs);

            if (inProgress) {
                if (!current || endMs < (current.event.endDate ?? current.event.startDate).getTime())
                    current = row;
                continue;
            }
            if (startMs > nowMs && (!next || startMs < next.event.startDate.getTime()))
                next = row;
            }
        }

        return current?.rowKey ?? next?.rowKey ?? "";
    }

    onEntranceKeyChanged: heroAnim.restart()

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        // ─── Today hero ───
        Rectangle {
            id: hero
            Layout.fillWidth: true
            Layout.preferredHeight: 128
            radius: Appearance.rounding.large
            color: Appearance.colors.colPrimaryContainer

            opacity: 0
            transform: Translate {
                id: heroTranslate
                y: 14
            }

            ParallelAnimation {
                id: heroAnim
                running: true
                NumberAnimation {
                    target: hero
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: heroTranslate
                    property: "y"
                    from: 14
                    to: 0
                    duration: Appearance.animation.elementMoveEnter.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dateActivated(root.todayDate)
            }

            ColumnLayout {
                id: heroContent
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: Qt.formatDate(root.todayDate, "dddd").toUpperCase()
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: ColorUtils.applyAlpha(Appearance.colors.colOnPrimaryContainer, 0.75)
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        text: String(root.todayDate.getDate())
                        font.family: Appearance.font.family.title
                        font.pixelSize: 44
                        font.weight: Font.Bold
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 8
                        text: Qt.formatDate(root.todayDate, "MMMM yyyy")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: ColorUtils.applyAlpha(Appearance.colors.colOnPrimaryContainer, 0.85)
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 events · %2 tasks")
                        .arg(String(root.todayEvents.length))
                        .arg(String(root.todayTasks.length + root.overdueTasks.length))
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.Medium
                    color: ColorUtils.applyAlpha(Appearance.colors.colOnPrimaryContainer, 0.8)
                    elide: Text.ElideRight
                }
            }
        }

        // ─── Section label ───
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.topMargin: 2
            spacing: 8

            StyledText {
                text: Translation.tr("Next %1 days").arg(String(root.horizonDays))
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }

            Item {
                Layout.fillWidth: true
            }

            Rectangle {
                visible: root.upcomingCount > 0
                implicitWidth: countText.implicitWidth + 16
                implicitHeight: 22
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer

                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: String(root.upcomingCount)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        // ─── List ───
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PagePlaceholder {
                shown: root.rows.length === 0
                icon: "event_available"
                shape: "Cookie9Sided"
                title: Translation.tr("All clear")
                description: Translation.tr("No events or tasks in the next %1 days").arg(String(root.horizonDays))
                titlePixelSize: Appearance.font.pixelSize.normal
                descriptionPixelSize: Appearance.font.pixelSize.smallie
                iconSize: 34
                iconPadding: 9
            }

            StyledListView {
                id: list
                anchors.fill: parent
                visible: root.rows.length > 0
                clip: true
                spacing: 3
                popin: false
                animatePopulate: true
                animateAppearance: true
                staggerStep: 22
                model: root.rows
                cacheBuffer: 400

                delegate: Item {
                    id: rowItem
                    required property var modelData
                    required property int index

                    readonly property string rowType: rowItem.modelData?.rowType ?? "day"

                    width: list.width
                    readonly property bool separatorRow: rowItem.rowType === "group"

                    implicitHeight: rowItem.separatorRow ? 34 : 40
                    height: implicitHeight

                    // ─── Horizon group ───
                    RippleButton {
                        anchors.fill: parent
                        visible: rowItem.separatorRow
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.toggleGroup(rowItem.modelData.groupKey)

                        contentItem: RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 6

                            MaterialSymbol {
                                text: rowItem.modelData.collapsed ? "chevron_right" : "expand_more"
                                iconSize: Appearance.font.pixelSize.normal
                                color: rowItem.modelData.groupKey === "today" ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: (rowItem.modelData?.label ?? "") + " · " + String(rowItem.modelData?.count ?? 0)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: rowItem.modelData.groupKey === "today" ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ─── Holiday row ───
                    Rectangle {
                        anchors.fill: parent
                        visible: rowItem.rowType === "holiday"
                        radius: Appearance.rounding.small
                        color: ColorUtils.mix(Appearance.colors.colTertiaryContainer, Appearance.colors.colLayer1, 0.55)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                text: "celebration"
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnTertiaryContainer
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: rowItem.modelData?.label ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnTertiaryContainer
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ─── Event row ───
                    Loader {
                        anchors.fill: parent
                        active: rowItem.rowType === "event"
                        sourceComponent: RippleButton {
                            id: eventButton
                            buttonRadius: Appearance.rounding.small
                            onClicked: root.eventActivated(rowItem.modelData.event)

                            readonly property color accent: H.chipColor(rowItem.modelData.event, Appearance.colors, GoogleCalendarService.colorForEvent(rowItem.modelData.event))
                            readonly property bool allDay: CalendarService.isAllDayEvent(rowItem.modelData.event)
                            readonly property bool cancelled: String(rowItem.modelData.event?.status ?? "").toUpperCase() === "CANCELLED"
                            readonly property bool featured: rowItem.modelData.rowKey === root.featuredEventRowKey
                            readonly property color foreground: featured
                                ? ColorUtils.getContrastingTextColor(accent)
                                : Appearance.colors.colOnSurface

                            colBackground: featured ? accent : Appearance.colors.colLayer1
                            colBackgroundHover: featured
                                ? ColorUtils.mix(accent, foreground, 0.88)
                                : Appearance.colors.colLayer1Hover

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 12
                                spacing: 10

                                Rectangle {
                                    Layout.preferredWidth: 4
                                    Layout.fillHeight: true
                                    Layout.topMargin: 7
                                    Layout.bottomMargin: 7
                                    radius: 2
                                    color: eventButton.featured
                                        ? ColorUtils.applyAlpha(eventButton.foreground, 0.72)
                                        : eventButton.accent
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: rowItem.modelData.event.content
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        font.weight: eventButton.featured ? Font.Bold : Font.DemiBold
                                        font.strikeout: eventButton.cancelled
                                        color: eventButton.foreground
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: {
                                            const time = eventButton.allDay ? Translation.tr("All day") : H.eventRangeText(rowItem.modelData.event, Config.options?.time.format);
                                            if (rowItem.modelData.groupKey === "today" || rowItem.modelData.groupKey === "tomorrow")
                                                return time;
                                            return Qt.formatDate(rowItem.modelData.date, "ddd, d MMM") + " · " + time;
                                        }
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: eventButton.featured
                                            ? ColorUtils.applyAlpha(eventButton.foreground, 0.78)
                                            : Appearance.colors.colOnSurfaceVariant
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        active: rowItem.rowType === "task"
                        sourceComponent: TaskChip {
                            taskData: rowItem.modelData.task
                            compact: false
                            onCompletionRequested: task => Todo.markDone(task)
                        }
                    }

                    Loader {
                        anchors.fill: parent
                        active: rowItem.rowType === "birthday"
                        sourceComponent: BirthdayChip {
                            birthdayData: rowItem.modelData.birthday
                            compact: false
                            onActivated: birthday => root.eventActivated(birthday)
                        }
                    }
                }
            }

            ScrollEdgeFade {
                target: list
                color: Appearance.colors.colSurfaceContainer
                visible: root.rows.length > 0
            }
        }
    }
}
