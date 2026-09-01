pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property int displayClockTick: 0
    property string noticeText: ""

    readonly property int gridColumns: 2
    readonly property real timerCardHeight: Appearance.sizes.elevationMargin * 9
    readonly property var countdowns: Array.from(TimerService.countdowns ?? [])
    readonly property real typedMinutes: root.minutesFromQuery(root.searchQuery)
    readonly property var rows: root.filteredRows()
    readonly property var selectedRow: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length
        ? root.rows[root.selectedIndex]
        : null
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : (root.typedMinutes > 0
            ? Translation.tr("Press Enter to start a %1 minute timer").arg(root.prettyMinutes(root.typedMinutes))
            : (root.selectedRow
                ? String(root.selectedRow.title) + " · " + root.valueFor(root.selectedRow)
                : Translation.tr("No timers match")))

    implicitWidth: Config.options.search.appearance.panelWidth
    implicitHeight: scaffold.implicitHeight

    function formatSeconds(seconds) {
        const safe = Math.max(0, Number(seconds) || 0);
        return String(Math.floor(safe / 60)).padStart(2, "0") + ":" + String(Math.floor(safe % 60)).padStart(2, "0");
    }

    function prettyMinutes(minutes) {
        const numeric = Number(minutes) || 0;
        return Number.isInteger(numeric) ? String(numeric) : numeric.toFixed(1);
    }

    function minutesFromQuery(value) {
        const query = String(value ?? "").trim().toLocaleLowerCase();
        if (query.length === 0)
            return 0;
        const plain = query.match(/^(\d+(?:[.,]\d+)?)\s*(m|min|mins|minute|minutes)?$/i);
        if (plain)
            return Number(plain[1].replace(",", "."));
        const duration = query.match(/^(?:(\d+)\s*(?:h|hr|hour|hours))?\s*(?:(\d+)\s*(?:m|min|mins|minute|minutes))?$/i);
        if (!duration || (!duration[1] && !duration[2]))
            return 0;
        return Number(duration[1] ?? 0) * 60 + Number(duration[2] ?? 0);
    }

    function allRows() {
        const output = [];
        if (Config.options.search.modules.timers.showPomodoro) {
            output.push({
                id: "pomodoro", kind: "pomodoro",
                icon: TimerService.pomodoroRunning ? "pause_circle" : "timelapse",
                title: TimerService.pomodoroLongBreak
                    ? Translation.tr("Long break")
                    : (TimerService.pomodoroBreak ? Translation.tr("Pomodoro break") : Translation.tr("Pomodoro focus")),
                subtitle: Translation.tr("Cycle %1 of %2").arg(String(TimerService.pomodoroCycle + 1)).arg(String(TimerService.cyclesBeforeLongBreak)),
                action: TimerService.pomodoroRunning ? Translation.tr("Pause") : Translation.tr("Start"),
                searchable: "pomodoro focus break cycle"
            });
        }
        if (Config.options.search.modules.timers.showStopwatch) {
            output.push({
                id: "stopwatch", kind: "stopwatch",
                icon: TimerService.stopwatchRunning ? "pause_circle" : "timer",
                title: Translation.tr("Stopwatch"),
                subtitle: TimerService.stopwatchRunning ? Translation.tr("Running") : Translation.tr("Paused"),
                action: TimerService.stopwatchRunning ? Translation.tr("Pause") : Translation.tr("Start"),
                searchable: "stopwatch chronometer cronometro"
            });
        }
        for (const countdown of root.countdowns) {
            output.push({
                id: String(countdown.id), kind: "countdown", countdown: countdown,
                icon: countdown.notified ? "notifications_off" : countdown.paused ? "pause_circle" : "hourglass_top",
                title: String(countdown.label ?? Translation.tr("Timer")),
                subtitle: countdown.notified ? Translation.tr("Finished") : countdown.paused ? Translation.tr("Paused") : Translation.tr("Countdown"),
                action: countdown.notified ? Translation.tr("Dismiss") : Translation.tr("Cancel"),
                searchable: String(countdown.label ?? "") + " countdown timer"
            });
        }
        if (Config.options.search.modules.timers.showAlarms) {
            const alarms = Array.from(AlarmService.alarms ?? []);
            for (let index = 0; index < alarms.length; index++) {
                const alarm = alarms[index];
                output.push({
                    id: "alarm-" + String(index), kind: "alarm", alarmIndex: index,
                    icon: alarm.enabled ? "alarm" : "alarm_off",
                    title: String(alarm.label ?? Translation.tr("Alarm")),
                    subtitle: alarm.enabled ? Translation.tr("Alarm enabled") : Translation.tr("Alarm disabled"),
                    action: alarm.enabled ? Translation.tr("Disable") : Translation.tr("Enable"),
                    value: String(alarm.time ?? ""),
                    searchable: String(alarm.label ?? "") + " " + String(alarm.time ?? "") + " alarm"
                });
            }
        }
        return output;
    }

    function valueFor(row) {
        if (!row)
            return "";
        const tick = root.displayClockTick;
        if (row.kind === "pomodoro")
            return root.formatSeconds(TimerService.pomodoroSecondsLeft);
        if (row.kind === "stopwatch")
            return root.formatSeconds(Math.floor((TimerService.stopwatchRunning
                ? TimerService.getCurrentTimeIn10ms() - TimerService.stopwatchStart
                : TimerService.stopwatchTime) / 100));
        if (row.kind === "countdown")
            return root.formatSeconds(TimerService.countdownSecondsLeft(row.countdown));
        return String(row.value ?? "");
    }

    function filteredRows() {
        const terms = root.searchQuery.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
        const values = root.allRows();
        if (terms.length === 0 || root.typedMinutes > 0)
            return values;
        return values.filter(row => {
            const text = [row.title, row.subtitle, row.value, row.searchable].join(" ").toLocaleLowerCase();
            return terms.every(term => text.includes(term));
        });
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    function createTimer(minutes) {
        const countdown = TimerService.addCountdown(minutes);
        if (!countdown)
            return false;
        root.searchQuery = "";
        root.showNotice(Translation.tr("%1 minute timer started").arg(root.prettyMinutes(minutes)));
        Qt.callLater(() => {
            const index = root.rows.findIndex(row => row.id === countdown.id);
            if (index >= 0)
                root.selectedIndex = index;
        });
        return true;
    }

    function clampSelection() {
        root.selectedIndex = root.rows.length === 0 ? -1 : Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
    }
    function navigateUp(): bool {
        if (root.selectedIndex >= root.gridColumns) {
            root.selectedIndex -= root.gridColumns;
            timerGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
        }
        return true;
    }
    function navigateDown(): bool {
        if (root.selectedIndex + root.gridColumns < root.rows.length) {
            root.selectedIndex += root.gridColumns;
            timerGrid.positionViewAtIndex(root.selectedIndex, GridView.Contain);
        }
        return true;
    }
    function navigateLeft(): bool {
        if (root.selectedIndex > 0)
            root.selectedIndex--;
        return true;
    }
    function navigateRight(): bool {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.rows.length - 1)
            root.selectedIndex++;
        return true;
    }

    function activateSelected(): bool {
        if (root.typedMinutes > 0)
            return root.createTimer(root.typedMinutes);
        const row = root.selectedRow;
        if (!row)
            return false;
        if (row.kind === "pomodoro") {
            TimerService.togglePomodoro();
            root.showNotice(TimerService.pomodoroRunning ? Translation.tr("Pomodoro started") : Translation.tr("Pomodoro paused"));
        } else if (row.kind === "stopwatch") {
            TimerService.toggleStopwatch();
            root.showNotice(TimerService.stopwatchRunning ? Translation.tr("Stopwatch started") : Translation.tr("Stopwatch paused"));
        } else if (row.kind === "countdown") {
            TimerService.removeCountdown(row.countdown.id);
            root.showNotice(Translation.tr("Timer removed"));
        } else if (row.kind === "alarm") {
            AlarmService.toggleAlarm(row.alarmIndex);
            root.showNotice(Translation.tr("Alarm updated"));
        } else {
            return false;
        }
        return true;
    }

    function secondaryActivateSelected(): bool {
        const row = root.selectedRow;
        if (!row)
            return false;
        if (row.kind === "pomodoro") {
            TimerService.resetPomodoro();
            root.showNotice(Translation.tr("Pomodoro reset"));
            return true;
        }
        if (row.kind === "stopwatch") {
            TimerService.stopwatchReset();
            root.showNotice(Translation.tr("Stopwatch reset"));
            return true;
        }
        return false;
    }

    function createFromQuery(): bool {
        if (root.typedMinutes <= 0) {
            root.showNotice(Translation.tr("Type a duration, for example 25m or 1h 30m"));
            return false;
        }
        return root.createTimer(root.typedMinutes);
    }
    function focusInput(): bool { return false; }

    onRowsChanged: root.clampSelection()
    onSearchQueryChanged: root.selectedIndex = 0

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.displayClockTick++
    }
    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Timers")
        icon: "timer"
        accent: true
        showStatus: true
        statusText: root.statusText
        primaryHint: ({ label: root.typedMinutes > 0 ? Translation.tr("Create") : (root.selectedRow?.action ?? Translation.tr("Run")), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("Reset"), actionId: "secondary", keys: ["Ctrl", "↵"] },
            { label: Translation.tr("Create typed duration"), actionId: "create", keys: ["Ctrl", "N"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin / 2

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: createContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                visible: root.typedMinutes > 0
                radius: Appearance.rounding.large
                color: Appearance.colors.colPrimaryContainer

                RowLayout {
                    id: createContent
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.elevationMargin
                    spacing: Appearance.sizes.elevationMargin
                    Rectangle {
                        implicitWidth: Appearance.sizes.elevationMargin * 4
                        implicitHeight: implicitWidth
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSurfaceContainerHighest
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "timer"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colPrimary
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: Translation.tr("Start a %1 minute timer").arg(root.prettyMinutes(root.typedMinutes))
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        StyledText {
                            text: Translation.tr("It will appear here and in the sidebar dashboard")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                    KeyHint {
                        keys: ["↵"]
                        surface: Appearance.colors.colPrimaryContainer
                        onSurface: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2
                StyledText {
                    text: Translation.tr("Quick timers")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurfaceVariant
                }
                Repeater {
                    model: Config.options.search.modules.timers.quickPresets
                    delegate: RippleButton {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Appearance.sizes.elevationMargin * 3
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: root.createTimer(Number(modelData))
                        StyledText {
                            anchors.centerIn: parent
                            text: Translation.tr("%1m").arg(String(modelData))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }
            }

            GridView {
                id: timerGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: width / root.gridColumns
                cellHeight: root.timerCardHeight
                model: root.rows

                delegate: Item {
                    required property int index
                    required property var modelData
                    width: timerGrid.cellWidth
                    height: timerGrid.cellHeight

                    RippleButton {
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin / 4
                        buttonRadius: root.selectedIndex === index ? Appearance.rounding.large : Appearance.rounding.normal
                        colBackground: root.selectedIndex === index ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHigh
                        colBackgroundHover: root.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSurfaceContainerHighestHover
                        colRipple: root.selectedIndex === index ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colSurfaceContainerHighestActive
                        onClicked: root.selectedIndex = index
                        onDoubleClicked: root.activateSelected()

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Appearance.sizes.elevationMargin
                            spacing: Appearance.sizes.elevationMargin
                            Rectangle {
                                implicitWidth: Appearance.sizes.elevationMargin * 4
                                implicitHeight: implicitWidth
                                radius: modelData.kind === "pomodoro" ? Appearance.rounding.full : Appearance.rounding.normal
                                color: root.selectedIndex === index ? Appearance.colors.colSurfaceContainerHighest : Appearance.colors.colSecondaryContainer
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.large
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Appearance.sizes.elevationMargin / 4
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    elide: Text.ElideRight
                                    font.weight: Font.DemiBold
                                    color: root.selectedIndex === index ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.subtitle
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: root.selectedIndex === index ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                                }
                                StyledText {
                                    text: root.valueFor(modelData)
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.large
                                    color: root.selectedIndex === index ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                                }
                            }
                            ColumnLayout {
                                spacing: Appearance.sizes.elevationMargin / 4

                                StyledText {
                                    Layout.alignment: Qt.AlignRight
                                    text: modelData.action
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.selectedIndex === index ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                                }

                                ConfiguredKeyHint {
                                    visible: root.selectedIndex === index && Config.options.search.appearance.showKeyHints
                                    actionId: "activate"
                                    fallbackKeys: ["↵"]
                                    surface: Appearance.colors.colSecondaryContainer
                                    onSurface: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    visible: root.rows.length === 0
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "timer_off"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("No timers match this search")
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
