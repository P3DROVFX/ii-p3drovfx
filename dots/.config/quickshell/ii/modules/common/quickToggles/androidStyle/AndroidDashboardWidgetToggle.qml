pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.models.quickToggles
import qs.modules.common.widgets

/**
 * Compact, fixed-footprint adaptations of the dashboard's calendar, tasks and timer tools.
 *
 * A tap performs the useful immediate action; right-click or touch hold opens the complete
 * tool. The five variants share one visual contract so they remain a coherent row in the
 * quick-toggle drawer without importing anything from a panel family.
 */
AndroidQuickToggleButton {
    id: root

    readonly property string widgetType: String(root.buttonData?.type ?? "")
    readonly property bool isCalendar: root.widgetType === "calendarWidget"
    readonly property bool isTasks: root.widgetType === "tasksWidget"
    readonly property bool isTimer: root.widgetType === "timerWidget"
    readonly property bool isCountdown: root.widgetType === "countdownWidget"
    readonly property bool isPomodoro: root.widgetType === "pomodoroWidget"

    readonly property var unfinishedTasks: Array.from(Todo.list ?? [])
        .filter(task => task && task.done !== true)
    readonly property var currentCountdown: {
        const timers = Array.from(TimerService.countdowns ?? []);
        return timers.find(countdown => countdown && countdown.notified !== true) ?? null;
    }

    // Countdowns and the compact stopwatch value need one-second presentation updates.
    // The service keeps its own accurate clock; this is only the visible sampling cadence.
    property int displayTick: 0
    Timer {
        interval: 1000
        repeat: true
        running: GlobalStates.sidebarRightOpen
            && (root.isCountdown || (root.isTimer && TimerService.stopwatchRunning))
        onTriggered: root.displayTick++
    }

    function formatDuration(totalSeconds) {
        const safe = Math.max(0, Math.floor(Number(totalSeconds) || 0));
        const hours = Math.floor(safe / 3600);
        const minutes = Math.floor((safe % 3600) / 60);
        const seconds = safe % 60;
        const shortValue = String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0");
        return hours > 0 ? String(hours) + ":" + shortValue : shortValue;
    }

    function stopwatchSeconds() {
        const tick = root.displayTick;
        if (TimerService.stopwatchRunning)
            return Math.max(0, Math.floor((TimerService.getCurrentTimeIn10ms() - TimerService.stopwatchStart) / 100));
        return Math.max(0, Math.floor(TimerService.stopwatchTime / 100));
    }

    readonly property string widgetName: {
        if (root.isCalendar)
            return Translation.tr("Calendar");
        if (root.isTasks)
            return Translation.tr("Tasks");
        if (root.isTimer)
            return Translation.tr("Timer");
        if (root.isCountdown)
            return Translation.tr("Countdown");
        return Translation.tr("Pomodoro");
    }

    readonly property string widgetIcon: {
        if (root.isCalendar)
            return "calendar_month";
        if (root.isTasks)
            return "task_alt";
        if (root.isTimer)
            return TimerService.stopwatchRunning ? "pause" : "timer";
        if (root.isCountdown)
            return root.currentCountdown && !root.currentCountdown.paused ? "pause" : "hourglass_top";
        return TimerService.pomodoroRunning ? "pause" : "search_activity";
    }

    readonly property bool widgetActive: {
        if (root.isCalendar)
            return (CalendarService.eventsForDay(DateTime.clock.date)?.length ?? 0) > 0;
        if (root.isTasks)
            return root.unfinishedTasks.length > 0;
        if (root.isTimer)
            return TimerService.stopwatchRunning;
        if (root.isCountdown)
            return root.currentCountdown !== null && root.currentCountdown.paused !== true;
        return TimerService.pomodoroRunning;
    }

    readonly property string primaryValue: {
        if (root.isCalendar)
            return DateTime.dayOfMonthPadded;
        if (root.isTasks)
            return String(root.unfinishedTasks.length);
        if (root.isTimer)
            return root.formatDuration(root.stopwatchSeconds());
        if (root.isCountdown) {
            const tick = root.displayTick;
            return root.currentCountdown
                ? root.formatDuration(TimerService.countdownSecondsLeft(root.currentCountdown))
                : "--:--";
        }
        return root.formatDuration(TimerService.pomodoroSecondsLeft);
    }

    readonly property string secondaryValue: {
        if (root.isCalendar) {
            const count = CalendarService.eventsForDay(DateTime.clock.date)?.length ?? 0;
            return count > 0
                ? Translation.tr("%1 today").arg(String(count))
                : DateTime.monthNameShort;
        }
        if (root.isTasks)
            return Translation.tr("remaining");
        if (root.isTimer)
            return TimerService.stopwatchRunning ? Translation.tr("Running") : Translation.tr("Paused");
        if (root.isCountdown)
            return root.currentCountdown
                ? String(root.currentCountdown.label ?? Translation.tr("Timer"))
                : Translation.tr("Tap to create");
        if (TimerService.pomodoroLongBreak)
            return Translation.tr("Long break");
        return TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus");
    }

    function openFullTool() {
        const panelId = root.isCalendar ? "calendar" : (root.isTasks ? "tasks" : "timers");
        GlobalStates.sidebarRightOpen = false;
        Qt.callLater(function() {
            if (PanelFamily.nativeAppWindows)
                GlobalStates.openAppDrawerTool("", panelId);
            else
                GlobalStates.openSearchPanel(panelId);
        });
    }

    function triggerPrimary() {
        if (root.isCalendar || root.isTasks) {
            root.openFullTool();
            return;
        }
        if (root.isTimer) {
            TimerService.toggleStopwatch();
            return;
        }
        if (root.isCountdown) {
            if (root.currentCountdown) {
                TimerService.toggleCountdown(root.currentCountdown.id);
            } else if (TimerService.draftCountdownSeconds() > 0) {
                TimerService.startDraftCountdown();
            } else {
                root.openFullTool();
            }
            return;
        }
        TimerService.togglePomodoro();
    }

    toggleModel: QuickToggleModel {
        name: root.widgetName
        statusText: root.secondaryValue
        tooltipText: root.isCalendar || root.isTasks
            ? Translation.tr("Open %1").arg(root.widgetName)
            : Translation.tr("Tap to start or pause. Hold to open timers.")
        icon: root.widgetIcon
        toggled: root.widgetActive
        mainAction: () => root.triggerPrimary()
        altAction: () => root.openFullTool()
    }

    tall1x2OverrideComponent: widgetLayout

    Component {
        id: widgetLayout

        Item {
            anchors.fill: parent
            anchors.margins: root.scaled(10)

            ColumnLayout {
                anchors.fill: parent
                spacing: root.scaled(3)

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: root.scaled(48)
                    implicitHeight: implicitWidth
                    radius: Appearance.rounding.full
                    color: root.widgetActive
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colLayer3

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.widgetIcon
                        fill: root.widgetActive ? 1 : 0
                        iconSize: root.scaled(25)
                        color: root.widgetActive
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer3
                    }
                }

                Item { Layout.fillHeight: true }

                StyledText {
                    Layout.fillWidth: true
                    text: root.primaryValue
                    font.pixelSize: root.scaled(Appearance.font.pixelSize.huge)
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.secondaryValue
                    font.pixelSize: root.scaled(Appearance.font.pixelSize.smaller)
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.widgetName
                    font.pixelSize: root.scaled(Appearance.font.pixelSize.smallie)
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    color: Appearance.colors.colOnLayer2
                    elide: Text.ElideRight
                }
            }
        }
    }
}
