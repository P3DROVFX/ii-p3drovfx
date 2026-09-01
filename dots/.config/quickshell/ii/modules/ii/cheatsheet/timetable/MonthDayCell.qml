import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import "TimetableHelpers.js" as H

/**
 * A single day of the month grid.
 *
 * Owns nothing but presentation: the month view decides which events belong
 * here, which cell a drag is hovering, and what a click means. Overflowing
 * events collapse into a counter instead of scrolling, so the grid never nests
 * a scrollable area inside another one.
 */
Item {
    id: root

    required property var cellData
    property var events: []
    property var tasks: []
    property var birthdays: []
    property var holidays: []
    property bool sportsEnabled: false
    property bool dropTarget: false
    property int entranceKey: 0
    property string densityMode: "compact"
    property real recurrenceLaneOffset: 0
    property bool keyboardSelected: false
    /**
     * Open tasks with no due date, shown on today only and as one chip.
     * They belong to no day, so listing them per cell would bury the calendar.
     */
    property int undatedTaskCount: 0

    signal createRequested(var date)
    signal dayActivated(var date)
    signal eventActivated(var eventData)
    signal taskCompletionRequested(var task)
    signal undatedTasksActivated
    signal eventDragBegan(var eventData, real x, real y, real w, real h)
    signal eventDragMoved(real x, real y)
    signal eventDragEnded
    signal eventDragCanceled

    property Item coordinateRoot: null
    property var draggedEvent: null

    readonly property bool isToday: root.cellData?.isToday ?? false
    readonly property bool inMonth: root.cellData?.inMonth ?? true
    readonly property bool isWeekend: root.cellData?.isWeekend ?? false
    readonly property bool isHoliday: (root.holidays?.length ?? 0) > 0
    readonly property bool isTomorrow: H.sameDate(root.cellData?.date, H.addDays(DateTime.clock.date, 1))
    readonly property string holidayLabel: root.isHoliday ? (root.holidays[0].localName || root.holidays[0].name || "") : ""
    readonly property var forecast: {
        const key = H.dayKeyOf(root.cellData?.date);
        return (Weather.forecastData ?? []).find(day => String(day?.date ?? "") === key) ?? null;
    }

    readonly property bool moonEnabled: Config.options.calendar.timetable.moonPhases?.enable ?? false
    readonly property var moonInfo: H.moonPhaseInfo(root.cellData?.date)
    readonly property string moonPhaseLabel: {
        const info = root.moonInfo;
        if (!info)
            return "";
        switch (info.index) {
        case 0: return Translation.tr("New Moon");
        case 1: return Translation.tr("Waxing Crescent");
        case 2: return Translation.tr("First Quarter");
        case 3: return Translation.tr("Waxing Gibbous");
        case 4: return Translation.tr("Full Moon");
        case 5: return Translation.tr("Waning Gibbous");
        case 6: return Translation.tr("Last Quarter");
        default: return Translation.tr("Waning Crescent");
        }
    }
    readonly property var sportEvents: root.sportsEnabled ? SportsService.gamesForDate(root.cellData?.date) : []

    // The header band is measured from the top of the cell, inset included, so
    // the chip area below it cannot drift when the inset changes.
    readonly property real headerTopInset: 5
    readonly property real headerContentHeight: 20
    readonly property real headerHeight: root.headerTopInset + root.headerContentHeight
    readonly property real headerEventSpacing: 2
    readonly property real chipSpacing: 2
    readonly property real cellPadding: 9
    readonly property bool compactChips: root.densityMode !== "comfortable"
    readonly property real chipHeight: root.densityMode === "comfortable" ? 24 : 16
    readonly property real chipAreaHeight: Math.max(0, root.height - root.headerHeight - root.headerEventSpacing - root.recurrenceLaneOffset - root.cellPadding)
    readonly property int chipCapacity: Math.max(0, Math.floor((root.chipAreaHeight + root.chipSpacing) / (root.chipHeight + root.chipSpacing)))
    // Keep events and tasks in one capacity calculation. Otherwise a busy day
    // could silently overflow below the cell after task integration.
    readonly property var entries: {
        const result = [];
        for (const eventData of (root.events ?? []))
            result.push({ kind: "event", data: eventData });
        for (const birthdayData of (root.birthdays ?? []))
            result.push({ kind: "birthday", data: birthdayData });
        for (const sportData of root.sportEvents)
            result.push({ kind: "sport", data: sportData });
        for (const taskData of (root.tasks ?? []))
            result.push({ kind: "task", data: taskData });
        if (root.undatedTaskCount > 0)
            result.push({ kind: "taskGroup", data: { count: root.undatedTaskCount } });
        return result;
    }
    readonly property int entryCount: root.entries.length
    readonly property bool overflowing: root.entryCount > root.chipCapacity
    readonly property int visibleCount: root.overflowing ? Math.max(0, root.chipCapacity - 1) : root.entryCount
    readonly property int hiddenCount: root.entryCount - root.visibleCount

    readonly property var visibleEntries: root.visibleCount >= root.entryCount ? root.entries : root.entries.slice(0, root.visibleCount)
    readonly property int dotCapacity: Math.max(1, Math.min(12, Math.floor((root.width - root.cellPadding * 2 - 26) / 11)))
    readonly property var dotEntries: root.entries.slice(0, root.dotCapacity)
    readonly property int hiddenDotCount: Math.max(0, root.entryCount - root.dotEntries.length)

    function entryColor(entry) {
        if (entry?.kind === "birthday" || entry?.kind === "sport")
            return Appearance.colors.colTertiary;
        if (entry?.kind === "task" || entry?.kind === "taskGroup")
            return Appearance.colors.colSecondary;
        return H.chipColor(entry?.data, Appearance.colors, GoogleCalendarService.colorForEvent(entry?.data));
    }

    function entryTitle(entry) {
        if (entry?.kind === "taskGroup")
            return Translation.tr("%1 task(s) with no date").arg(String(entry.data?.count ?? 0));
        if (entry?.kind === "task")
            return entry.data?.content ?? entry.data?.title ?? Translation.tr("Task");
        if (entry?.kind === "birthday")
            return entry.data?.name ?? entry.data?.content ?? Translation.tr("Birthday");
        return entry?.data?.content ?? entry?.data?.title ?? Translation.tr("Event");
    }

    // A weekend is marked with a texture rather than another surface colour, so
    // it survives the today / holiday / hover / drop fills stacked on the plate.
    readonly property color weekendHatchColor: {
        const tertiary = Qt.color(Appearance.colors.colTertiary);
        return Qt.hsla(tertiary.hslHue, tertiary.hslSaturation * 0.3, tertiary.hslLightness, root.inMonth ? 0.15 : 0.06);
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: {
            const base = root.isWeekend ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1;
            if (root.dropTarget)
                return ColorUtils.mix(Appearance.colors.colPrimaryContainer, base, 0.75);
            if (root.keyboardSelected)
                return ColorUtils.mix(Appearance.colors.colPrimaryContainer, base, 0.58);
            if (!root.inMonth)
                return ColorUtils.applyAlpha(base, 0.32);
            if (root.isToday)
                return ColorUtils.mix(Appearance.colors.colPrimaryContainer, base, 0.4);
            if (root.isHoliday)
                return ColorUtils.mix(Appearance.colors.colTertiaryContainer, base, 0.24);
            if (cellPointer.containsMouse)
                return root.isWeekend ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1Hover;
            return base;
        }

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(surface)
        }

        DiagonalHatch {
            anchors.fill: parent
            visible: root.isWeekend
            lineColor: root.weekendHatchColor
            lineSpacing: 9
            plateRadius: surface.radius
        }
    }

    // A drop target reads as a lifted plate rather than a coloured box.
    scale: root.dropTarget ? 1.02 : 1.0
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }

    MouseArea {
        id: cellPointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.inMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton
        onClicked: root.createRequested(root.cellData.date)
    }

    // ─── Header: day number, holiday, add affordance ───
    Item {
        id: header
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: root.headerTopInset
            leftMargin: root.cellPadding
            rightMargin: root.cellPadding - 2
        }
        height: root.headerContentHeight

        Rectangle {
            id: dayBadge
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            width: Math.max(height, dayNumber.implicitWidth + 12)
            height: 20
            radius: Appearance.rounding.full
            color: root.isToday ? Appearance.colors.colPrimary : (dayHover.hovered ? Appearance.colors.colLayer3 : "transparent")

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(dayBadge)
            }

            StyledText {
                id: dayNumber
                anchors.centerIn: parent
                text: String(root.cellData?.day ?? "")
                font.pixelSize: root.isToday ? Appearance.font.pixelSize.normal : Appearance.font.pixelSize.smallie
                font.weight: root.isToday ? Font.Bold : (root.inMonth ? Font.DemiBold : Font.Medium)
                color: {
                    if (root.isToday)
                        return Appearance.colors.colOnPrimary;
                    if (!root.inMonth)
                        return Appearance.colors.colOnLayer1Inactive;
                    if (root.isHoliday)
                        return Appearance.colors.colOnTertiaryContainer;
                    return Appearance.colors.colOnSurface;
                }

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(dayNumber)
                }
            }

            HoverHandler {
                id: dayHover
            }

            TapHandler {
                onTapped: root.dayActivated(root.cellData.date)
            }

            StyledToolTip {
                extraVisibleCondition: dayHover.hovered
                text: Qt.formatDate(root.cellData?.date ?? new Date(), Locale.LongFormat)
            }
        }

        StyledText {
            id: holidayText
            visible: root.isHoliday && root.width > 96
            anchors {
                left: dayBadge.right
                right: weatherIcon.left
                leftMargin: 6
                rightMargin: 4
                verticalCenter: parent.verticalCenter
            }
            text: root.holidayLabel
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnTertiaryContainer
            opacity: root.inMonth ? 1 : 0.55
        }

        Image {
            id: weatherIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: moonIcon.left
            anchors.rightMargin: 4
            width: Appearance.font.pixelSize.normal
            height: width
            visible: root.inMonth && root.forecast !== null && root.width > 92 && (root.isToday || root.isTomorrow || cellPointer.containsMouse)
            source: WeatherIcons.getWeatherIcon(root.forecast?.code ?? 113, false)
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit

            HoverHandler {
                id: weatherHover
            }

            StyledToolTip {
                extraVisibleCondition: weatherHover.hovered
                text: {
                    const forecast = root.forecast;
                    if (!forecast)
                        return "";
                    return Translation.tr("Forecast · %1° / %2°")
                        .arg(String(forecast.minC ?? ""))
                        .arg(String(forecast.maxC ?? ""));
                }
            }
        }

        Text {
            id: moonIcon
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: addButton.left
            anchors.rightMargin: 4
            width: Appearance.font.pixelSize.normal
            height: width
            visible: root.inMonth && root.moonEnabled && root.moonInfo !== null && root.width > 92 && (root.isToday || root.isTomorrow || cellPointer.containsMouse)
            text: H.moonGlyphFor(root.moonInfo?.index ?? 0)
            font.family: Appearance.font.family.iconNerd
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            HoverHandler {
                id: moonHover
            }

            StyledToolTip {
                extraVisibleCondition: moonHover.hovered
                text: {
                    const info = root.moonInfo;
                    if (!info)
                        return "";
                    return root.moonPhaseLabel + " · " + String(Math.round(info.illumination * 100)) + "% " + Translation.tr("illuminated");
                }
            }
        }

        RippleButton {
            id: addButton
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            implicitWidth: 20
            implicitHeight: 20
            buttonRadius: Appearance.rounding.full
            colBackground: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.16)
            colBackgroundHover: Appearance.colors.colPrimary
            opacity: cellPointer.containsMouse || addButton.hovered ? 1 : 0
            visible: opacity > 0.01
            onClicked: root.createRequested(root.cellData.date)

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(addButton)
            }

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "add"
                iconSize: Appearance.font.pixelSize.small
                color: addButton.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary
            }

            StyledToolTip {
                extraVisibleCondition: addButton.hovered
                text: Translation.tr("New event")
            }
        }
    }

    // ─── Events and tasks ───
    Column {
        id: chipColumn
        visible: root.densityMode !== "dots"
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            topMargin: root.headerEventSpacing + root.recurrenceLaneOffset
            leftMargin: root.cellPadding - 2
            rightMargin: root.cellPadding - 2
        }
        spacing: root.chipSpacing

        Repeater {
            model: root.visibleEntries

            delegate: Item {
                required property var modelData
                required property int index

                width: chipColumn.width
                height: root.chipHeight

                MonthEventChip {
                    anchors.fill: parent
                    visible: parent.modelData.kind === "event" || parent.modelData.kind === "sport"
                    eventData: parent.modelData.data
                    allDay: CalendarService.isAllDayEvent(parent.modelData.data)
                    compact: root.compactChips
                    dragEnabled: parent.modelData.data?.readOnly !== true
                    coordinateRoot: root.coordinateRoot
                    dragging: root.draggedEvent === parent.modelData.data
                    entranceKey: root.entranceKey
                    entranceIndex: parent.index
                    opacity: root.inMonth ? 1 : 0.6

                    onActivated: {
                        if (parent.modelData.data?.sportEvent === true || parent.modelData.data?.readOnly !== true)
                            root.eventActivated(parent.modelData.data);
                    }
                    onDragBegan: (evt, x, y, w, h) => root.eventDragBegan(evt, x, y, w, h)
                    onDragMoved: (x, y) => root.eventDragMoved(x, y)
                    onDragEnded: root.eventDragEnded()
                    onDragCanceled: root.eventDragCanceled()
                }

                BirthdayChip {
                    anchors.fill: parent
                    visible: parent.modelData.kind === "birthday"
                    birthdayData: parent.modelData.data
                    compact: root.compactChips
                    opacity: root.inMonth ? 1 : 0.6
                    onActivated: birthday => root.eventActivated(birthday)
                }

                TaskChip {
                    anchors.fill: parent
                    visible: parent.modelData.kind === "task"
                    taskData: parent.modelData.data
                    compact: root.compactChips
                    opacity: root.inMonth ? 1 : 0.6
                    onCompletionRequested: task => root.taskCompletionRequested(task)
                }

                // One plate for the whole undated backlog: the count is the
                // information, the list belongs in the rail.
                RippleButton {
                    id: taskGroupChip
                    readonly property string label: root.entryTitle(parent.modelData)

                    anchors.fill: parent
                    visible: parent.modelData.kind === "taskGroup"
                    buttonRadius: Appearance.rounding.verysmall
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colRipple: Appearance.colors.colSecondaryContainerActive
                    opacity: root.inMonth ? 1 : 0.6
                    onClicked: root.undatedTasksActivated()

                    contentItem: Row {
                        anchors.fill: parent
                        anchors.leftMargin: 5
                        anchors.rightMargin: 6
                        spacing: 4

                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "checklist"
                            iconSize: root.compactChips ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - x)
                            text: taskGroupChip.label
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.pixelSize: root.compactChips ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }

        RippleButton {
            visible: root.hiddenCount > 0
            width: chipColumn.width
            implicitHeight: root.chipHeight
            buttonRadius: Math.min(root.chipHeight / 2, Appearance.rounding.small)
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer3Hover
            onClicked: root.dayActivated(root.cellData.date)

            contentItem: StyledText {
                anchors.fill: parent
                anchors.leftMargin: 11
                text: Translation.tr("%1 more").arg(String(root.hiddenCount))
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    Row {
        id: densityDots
        visible: root.densityMode === "dots" && root.entryCount > 0
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            topMargin: 5 + root.recurrenceLaneOffset
            leftMargin: root.cellPadding
            rightMargin: root.cellPadding
        }
        height: 16
        spacing: 4

        Repeater {
            model: root.dotEntries

            delegate: Rectangle {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: Appearance.rounding.full
                color: root.entryColor(modelData)
                opacity: root.inMonth ? 1 : 0.55
            }
        }

        StyledText {
            visible: root.hiddenDotCount > 0
            anchors.verticalCenter: parent.verticalCenter
            text: "+" + String(root.hiddenDotCount)
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnSurfaceVariant
        }

        HoverHandler {
            id: dotsHover
        }

        TapHandler {
            onTapped: root.dayActivated(root.cellData.date)
        }

        StyledToolTip {
            extraVisibleCondition: dotsHover.hovered
            text: Translation.tr("%1 items").arg(String(root.entryCount)) + "\n" + root.entries.map(entry => root.entryTitle(entry)).join("\n")
        }
    }

}
