pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import "calendar"

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property date selectedDate: new Date()
    property bool upcomingMode: true
    property bool createPageOpen: false
    property string noticeText: ""

    readonly property string calendarSource: String(Config.options.search.modules.calendar.source ?? "khal")
    readonly property var sourceEvents: {
        const khal = Array.from(CalendarService.events ?? []);
        const google = Array.from(GoogleCalendarService.events ?? []);
        if (root.calendarSource === "google")
            return google;
        if (root.calendarSource === "both") {
            const seen = ({});
            return khal.concat(google).filter(event => {
                const key = String(event?.uid ?? event?.id ?? "") || String(event?.content ?? "") + String(event?.startDate ?? "");
                if (seen[key])
                    return false;
                seen[key] = true;
                return true;
            });
        }
        return khal;
    }
    readonly property var rows: root.filteredEvents()
    readonly property var selectedEvent: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length ? root.rows[root.selectedIndex] : null
    readonly property var parsedCreate: Config.options.search.modules.calendar.allowCreate ? DateUtils.parseNaturalEvent(root.searchQuery) : null
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : (root.selectedEvent
        ? String(root.selectedEvent.content ?? root.selectedEvent.title ?? "") + " · " + String(root.selectedEvent.calendar ?? "")
        : (root.calendarSource === "khal" && !CalendarService.khalAvailable
            ? Translation.tr("Calendar is not configured")
            : Translation.tr("%1 events").arg(String(root.rows.length))))

    implicitWidth: 720
    implicitHeight: scaffold.implicitHeight

    function filteredEvents() {
        const query = root.searchQuery.trim().toLocaleLowerCase();
        const day = Qt.formatDate(root.selectedDate, "yyyy-MM-dd");
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        return root.sourceEvents.filter(event => {
            const start = event?.startDate instanceof Date ? event.startDate : new Date(event?.startDate);
            if (isNaN(start.getTime()))
                return false;
            if (root.upcomingMode ? start < todayStart : Qt.formatDate(start, "yyyy-MM-dd") !== day)
                return false;
            if (!Config.options.search.modules.calendar.showDeclined && String(event?.status ?? "") === "cancelled")
                return false;
            if (query.length === 0)
                return true;
            return [event?.content, event?.title, event?.description, event?.calendar, event?.location]
                .join(" ").toLocaleLowerCase().includes(query);
        }).sort((left, right) => new Date(left?.startDate) - new Date(right?.startDate));
    }

    function clampSelection() {
        root.selectedIndex = root.rows.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
    }

    function changeDay(offset) {
        if (root.upcomingMode)
            root.selectedDate = new Date();
        root.upcomingMode = false;
        root.selectedDate = new Date(root.selectedDate.getFullYear(), root.selectedDate.getMonth(), root.selectedDate.getDate() + offset);
        root.selectedIndex = 0;
    }

    function showUpcoming() {
        root.selectedDate = new Date();
        root.upcomingMode = true;
        root.selectedIndex = 0;
    }

    function navigateUp(): bool {
        if (root.selectedIndex <= 0)
            return false;
        root.selectedIndex--;
        agenda.positionViewAtIndex(root.selectedIndex);
        return true;
    }

    function navigateDown(): bool {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length - 1)
            return false;
        root.selectedIndex++;
        agenda.positionViewAtIndex(root.selectedIndex);
        return true;
    }

    function navigateLeft(): bool { root.changeDay(-1); return true; }
    function navigateRight(): bool { root.changeDay(1); return true; }

    function openEvent(event = root.selectedEvent): bool {
        const url = String(event?.url ?? event?.htmlLink ?? "");
        if (url.length === 0)
            return false;
        Quickshell.execDetached(["xdg-open", url]);
        return true;
    }

    function activateSelected(): bool { return root.openEvent(); }
    function secondaryActivateSelected(): bool { return root.openEvent(); }
    function copySelected(): bool {
        const url = String(root.selectedEvent?.url ?? root.selectedEvent?.htmlLink ?? "");
        if (url.length === 0)
            return false;
        Quickshell.clipboardText = url;
        return true;
    }

    function createFromQuery(): bool {
        if (!root.createPageOpen) {
            root.createPageOpen = true;
            createForm.reset();
            Qt.callLater(createForm.focusFirst);
            return true;
        }
        return createForm.submit();
    }

    function submitFields(fields): bool {
        const prefersGoogle = root.calendarSource === "google" || root.calendarSource === "both";
        const created = prefersGoogle && GoogleCalendarService.available
            ? GoogleCalendarService.createEvent(Config.options.search.modules.calendar.defaultCalendarId || "primary", fields)
            : (CalendarService.khalAvailable
                ? CalendarService.createEventFields("", fields, reply => {
                    root.noticeText = reply?.ok
                        ? Translation.tr("Event created")
                        : String(reply?.error ?? Translation.tr("Could not create event"));
                    noticeTimer.restart();
                })
                : false);
        if (created) {
            root.noticeText = Translation.tr("Creating event…");
            noticeTimer.restart();
            root.createPageOpen = false;
            root.searchQuery = "";
        } else {
            createForm.errorText = Translation.tr("No writable calendar is available");
        }
        return created;
    }

    function navigateBack(): bool {
        if (!root.createPageOpen)
            return false;
        root.createPageOpen = false;
        Qt.callLater(() => root.forceActiveFocus());
        return true;
    }

    function focusInput(): bool { return false; }

    onRowsChanged: root.clampSelection()
    onSearchQueryChanged: root.selectedIndex = 0

    Component.onCompleted: {
        if ((root.calendarSource === "google" || root.calendarSource === "both") && GoogleCalendarService.available)
            GoogleCalendarService.refresh();
    }

    Connections {
        target: GoogleCalendarService
        function onMutationRevisionChanged() {
            root.noticeText = GoogleCalendarService.mutationMessage;
            noticeTimer.restart();
        }
    }

    Timer {
        id: noticeTimer
        interval: 4000
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Calendar")
        icon: "calendar_month"
        accent: true
        statusText: root.statusText
        showStatus: true
        primaryHint: root.createPageOpen
            ? ({ label: Translation.tr("Create"), actionId: "create", keys: ["Ctrl", "N"] })
            : ({ label: Translation.tr("Open"), actionId: "activate", keys: ["↵"] })
        hints: root.createPageOpen
            ? [{ label: Translation.tr("Back"), keys: ["Esc"] }]
            : [
                { label: Translation.tr("Day"), keys: ["←", "→"] },
                { label: Translation.tr("Create"), actionId: "create", keys: ["Ctrl", "N"] }
            ]

        StackLayout {
            width: parent.width
            height: parent.height
            currentIndex: root.createPageOpen ? 1 : 0

            ColumnLayout {
                spacing: Appearance.sizes.elevationMargin

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.sizes.elevationMargin / 2

                    RippleButton {
                        implicitWidth: Appearance.sizes.elevationMargin * 3
                        implicitHeight: implicitWidth
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: root.changeDay(-1)
                        MaterialSymbol { anchors.centerIn: parent; text: "chevron_left"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnSurface }
                    }

                    RippleButton {
                        implicitWidth: dateLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                        implicitHeight: dateLabel.implicitHeight + Appearance.sizes.elevationMargin
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: root.showUpcoming()
                        StyledText {
                            id: dateLabel
                            anchors.centerIn: parent
                            text: root.upcomingMode ? Translation.tr("Upcoming") : Qt.formatDate(root.selectedDate, "ddd dd MMM")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    RippleButton {
                        implicitWidth: Appearance.sizes.elevationMargin * 3
                        implicitHeight: implicitWidth
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: root.changeDay(1)
                        MaterialSymbol { anchors.centerIn: parent; text: "chevron_right"; iconSize: Appearance.font.pixelSize.normal; color: Appearance.colors.colOnSurface }
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        visible: root.calendarSource !== "khal" && !GoogleCalendarService.available
                        implicitWidth: setupLabel.implicitWidth + Appearance.sizes.elevationMargin * 2
                        implicitHeight: setupLabel.implicitHeight + Appearance.sizes.elevationMargin
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: GoogleCalendarService.startOAuth()
                        StyledText {
                            id: setupLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Connect Google")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }

                CalendarQuickCreate {
                    Layout.fillWidth: true
                    parsed: root.parsedCreate
                    onCreateRequested: root.createFromQuery()
                }

                CalendarAgendaList {
                    id: agenda
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    rows: root.rows
                    selectedIndex: root.selectedIndex
                    showDate: root.upcomingMode
                    emptyText: root.upcomingMode ? Translation.tr("No upcoming events") : Translation.tr("No events for this day")
                    onSelected: index => root.selectedIndex = index
                    onActivated: index => {
                        root.selectedIndex = index;
                        root.activateSelected();
                    }
                }
            }

            CalendarCreateForm {
                id: createForm
                Layout.fillWidth: true
                Layout.fillHeight: true
                initialDate: root.selectedDate
                defaultDurationMinutes: Config.options.search.modules.calendar.defaultDurationMin
                busy: GoogleCalendarService.mutationState === "saving"
                onSubmitted: fields => root.submitFields(fields)
                onCancelled: root.navigateBack()
            }
        }
    }
}
