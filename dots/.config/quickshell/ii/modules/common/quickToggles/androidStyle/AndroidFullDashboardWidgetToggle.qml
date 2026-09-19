pragma ComponentBehavior: Bound

import QtQuick

import qs
import qs.services
import qs.modules.common
import qs.modules.common.dashboardWidgets.calendar
import qs.modules.common.dashboardWidgets.timer
import qs.modules.common.dashboardWidgets.todo
import qs.modules.common.dashboardWidgets.notes
import qs.modules.common.models.quickToggles

/**
 * Hosts the complete BottomWidgetGroup tools without replacing the compact
 * dashboard-summary cards. The outer Material card remains owned by the
 * quick-toggle system; only its padded content viewport changes per type.
 *
 * Supports responsive 2x2, 2x4, and 4x2 grid sizes.
 */
AndroidQuickToggleButton {
    id: root

    readonly property string widgetType: String(root.buttonData?.type ?? "")
    readonly property bool isCalendar: root.widgetType === "fullCalendarWidget"
    readonly property bool isTasks: root.widgetType === "fullTasksWidget"
    readonly property bool isTimer: root.widgetType === "fullTimerWidget"
    readonly property bool isCountdown: root.widgetType === "fullCountdownWidget"
    readonly property bool isPomodoro: root.widgetType === "fullPomodoroWidget"
    readonly property bool isNotes: root.widgetType === "fullNotesWidget"

    readonly property var currentCountdown: {
        const timers = Array.from(TimerService.countdowns ?? []);
        return timers.find(countdown => countdown && countdown.notified !== true) ?? null;
    }

    readonly property string widgetName: {
        if (root.isCalendar)
            return Translation.tr("Full calendar");
        if (root.isTasks)
            return Translation.tr("Full tasks");
        if (root.isTimer)
            return Translation.tr("Full stopwatch");
        if (root.isCountdown)
            return Translation.tr("Full countdown");
        if (root.isNotes)
            return Translation.tr("Full notes");
        return Translation.tr("Full pomodoro");
    }

    readonly property string widgetIcon: root.isCalendar ? "calendar_month"
        : root.isTasks ? "task_alt"
        : root.isTimer ? "timer"
        : root.isCountdown ? "hourglass_top"
        : root.isNotes ? "note_stack"
        : "search_activity"

    readonly property bool widgetActive: root.isCalendar
        ? (CalendarService.eventsForDay(DateTime.clock.date)?.length ?? 0) > 0
        : root.isTasks
            ? Array.from(Todo.list ?? []).some(task => task && task.done !== true)
            : root.isTimer
                ? TimerService.stopwatchRunning
                : root.isCountdown
                    ? root.currentCountdown !== null && root.currentCountdown.paused !== true
                    : root.isNotes
                        ? (NotesService.notes?.length ?? 0) > 0
                        : TimerService.pomodoroRunning

    function openFullTool() {
        if (root.isNotes) {
            GlobalStates.openNotes();
            GlobalStates.sidebarRightOpen = false;
            return;
        }
        const panelId = root.isCalendar ? "calendar" : (root.isTasks ? "tasks" : "timers");
        GlobalStates.sidebarRightOpen = false;
        Qt.callLater(function() {
            if (PanelFamily.nativeAppWindows)
                GlobalStates.openAppDrawerTool("", panelId);
            else
                GlobalStates.openSearchPanel(panelId);
        });
    }

    function triggerFallback() {
        if (root.isCalendar || root.isTasks || root.isNotes) {
            root.openFullTool();
        } else if (root.isTimer) {
            TimerService.toggleStopwatch();
        } else if (root.isCountdown) {
            if (root.currentCountdown)
                TimerService.toggleCountdown(root.currentCountdown.id);
            else if (TimerService.draftCountdownSeconds() > 0)
                TimerService.startDraftCountdown();
        } else {
            TimerService.togglePomodoro();
        }
    }

    toggleModel: QuickToggleModel {
        name: root.widgetName
        tooltipText: Translation.tr("Complete dashboard widget. Hold to open the full tool.")
        icon: root.widgetIcon
        toggled: false
        hasMenu: true
        mainAction: () => root.triggerFallback()
        altAction: () => root.openFullTool()
    }

    tall1x2OverrideComponent: widgetHost
    wide2x2OverrideComponent: widgetHost

    Component {
        id: widgetHost

        Item {
            anchors.fill: parent
            anchors.margins: root.scaled(6)
            clip: true

            Loader {
                anchors.fill: parent
                sourceComponent: root.isCalendar ? calendarContent
                    : root.isTasks ? tasksContent
                    : root.isTimer ? stopwatchContent
                    : root.isCountdown ? countdownContent
                    : (root.isNotes ? notesContent : pomodoroContent)
            }
        }
    }

    Component {
        id: calendarContent
        CalendarWidget {
            entranceTrigger: root.entranceTrigger
            sizeW: root.effectiveSizeW
            sizeH: root.effectiveSizeH
        }
    }

    Component {
        id: tasksContent
        TodoWidget {
            entranceTrigger: root.entranceTrigger
            sizeW: root.effectiveSizeW
            sizeH: root.effectiveSizeH
        }
    }

    Component {
        id: stopwatchContent
        Stopwatch {
            entranceTrigger: root.entranceTrigger
            sizeW: root.effectiveSizeW
            sizeH: root.effectiveSizeH
        }
    }

    Component {
        id: countdownContent
        CountdownTimer {
            entranceTrigger: root.entranceTrigger
            sizeW: root.effectiveSizeW
            sizeH: root.effectiveSizeH
        }
    }

    Component {
        id: pomodoroContent
        PomodoroTimer {
            entranceTrigger: root.entranceTrigger
            sizeW: root.effectiveSizeW
            sizeH: root.effectiveSizeH
        }
    }

    Component {
        id: notesContent
        NotesDashboardWidget {
            entranceTrigger: root.entranceTrigger
            sizeW: root.effectiveSizeW
            sizeH: root.effectiveSizeH
        }
    }
}
