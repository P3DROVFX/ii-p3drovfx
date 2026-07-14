import qs.modules.ii.bar.shared
import qs.modules.common
import qs.modules.common.widgets
import "../../shared/cards"
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

StyledPopup {
    id: root
    popupRadius: Appearance.rounding.large
    keyboardFocus: alarmsCard.mode !== "list" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property var timezoneOffsets: ({})
    property var worldClocksOption: Config.options.time.worldClocks
    onWorldClocksOptionChanged: {
        root.refreshTimezoneOffsets();
    }

    function refreshTimezoneOffsets() {
        let timezones = Config.options.time.worldClocks || [];
        if (timezones.length === 0) {
            root.timezoneOffsets = {};
            return;
        }

        let script = "";
        for (let i = 0; i < timezones.length; i++) {
            let tz = timezones[i].tz;
            if (tz) {
                let safeTz = tz.replace(/'/g, "'\\''");
                script += `TZ='${safeTz}' date +'%H:%M %z %Z ${safeTz}'; `;
            }
        }

        if (script === "") {
            root.timezoneOffsets = {};
            return;
        }

        _worldClocksProcess.offsetFetcher.command = ["bash", "-c", script];
        _worldClocksProcess.offsetFetcher.running = true;
    }

    property QtObject _worldClocksProcess: QtObject {
        property Process offsetFetcher: Process {
            stdout: StdioCollector {
                id: offsetCollector
                onStreamFinished: {
                    let lines = offsetCollector.text.split("\n");
                    let newOffsets = {};
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i].trim();
                        if (!line) continue;
                        let parts = line.split(" ");
                        if (parts.length >= 4) {
                            let timeStr = parts[0];
                            let offsetStr = parts[1];
                            let tzName = parts[2];
                            let tz = parts.slice(3).join(" ");

                            let sign = offsetStr.charAt(0) === "-" ? -1 : 1;
                            let hours = parseInt(offsetStr.substring(1, 3));
                            let mins = parseInt(offsetStr.substring(3, 5));
                            let offsetMins = sign * (hours * 60 + mins);

                            newOffsets[tz] = {
                                offsetMins: offsetMins,
                                tzName: tzName
                            };
                        }
                    }
                    root.timezoneOffsets = newOffsets;
                }
            }
        }
    }

    required property bool compact
    stickyHover: true

    property bool stopwatchPaused: !TimerService.stopwatchRunning && TimerService.stopwatchTime > 0

    function formatTimerDisplay(seconds) {
        let m = Math.floor(seconds / 60);
        let s = seconds % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    function getDayProgressPercent() {
        const date = DateTime.clock.date
        const secondsPassed = date.getHours() * 3600 + date.getMinutes() * 60 +date.getSeconds()

        return Math.floor((secondsPassed / 86400) * 100)
    }

    function getUtcTimeForTz(tz, date) {
        try {
            const data = root.timezoneOffsets[tz];
            if (!data) return NaN;
            return date.getTime() + (data.offsetMins * 60000);
        } catch (e) {
            return NaN;
        }
    }

    function getTimezoneOffsetString(tz, date) {
        try {
            const data = root.timezoneOffsets[tz];
            if (!data) return "";

            const localOffsetMins = -date.getTimezoneOffset();
            const targetOffsetMins = data.offsetMins;

            const diffMins = targetOffsetMins - localOffsetMins;
            if (diffMins === 0) {
                return "";
            }

            const diffHrs = diffMins / 60;
            const sign = diffHrs > 0 ? "+" : "";

            if (diffMins % 60 === 0) {
                return sign + diffHrs + "h";
            }

            const hrs = Math.floor(Math.abs(diffMins) / 60);
            const mins = Math.abs(diffMins) % 60;
            return `${sign}${diffHrs < 0 ? "-" : ""}${hrs}h ${mins}m`;
        } catch (e) {
            return "";
        }
    }

    function getFormattedTime(tz, date) {
        try {
            const data = root.timezoneOffsets[tz];
            if (!data) return "--:--";

            const offsetMins = data.offsetMins;
            const targetDate = new Date(date.getTime() + (offsetMins * 60000));

            const formatStr = Config.options?.time?.format ?? "hh:mm";
            const use12h = formatStr.includes("ap") || formatStr.includes("AP");
            const showSeconds = Config.options?.time?.secondPrecision ?? false;

            let hour = targetDate.getUTCHours();
            let minute = targetDate.getUTCMinutes();
            let second = targetDate.getUTCSeconds();

            let ampm = "";
            if (use12h) {
                ampm = hour >= 12 ? (formatStr.includes("AP") ? " PM" : " pm") : (formatStr.includes("AP") ? " AM" : " am");
                hour = hour % 12 || 12;
            }

            let hrStr = String(hour).padStart(2, "0");
            let minStr = String(minute).padStart(2, "0");
            let secStr = showSeconds ? ":" + String(second).padStart(2, "0") : "";

            return hrStr + ":" + minStr + secStr + ampm;
        } catch (e) {
            return "--:--";
        }
    }

    function getFormattedDate(tz, date) {
        try {
            const data = root.timezoneOffsets[tz];
            if (!data) return "";

            const offsetMins = data.offsetMins;
            const targetDate = new Date(date.getTime() + (offsetMins * 60000));

            const dateFormatStr = Config.options?.time?.dateFormat ?? "ddd dd/MM";
            const showMonthFirst = dateFormatStr.includes("MM/dd");

            const days = [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat")];
            const weekday = days[targetDate.getUTCDay()];

            const day = String(targetDate.getUTCDate()).padStart(2, "0");
            const month = String(targetDate.getUTCMonth() + 1).padStart(2, "0");

            if (showMonthFirst) {
                return `${weekday} ${month}/${day}`;
            } else {
                return `${weekday} ${day}/${month}`;
            }
        } catch (e) {
            return "";
        }
    }

    contentItem: ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        implicitWidth: 400
        spacing: 12

        // Delays computed dynamically based on visibility order to prevent stagger skipping
        readonly property var _visList: [
            clockHero.visible,
            worldClocksLoader.visible && worldClocksLoader.active,
            columnLayout.children[2].visible, // info column Layout
            localSendLoader.visible && localSendLoader.active,
            alarmsCard.visible
        ]

        function getDelay(index) {
            let visIndex = 0;
            for (let i = 0; i < index; i++) {
                if (_visList[i]) visIndex++;
            }
            const delays = [40, 100, 160, 220, 280];
            return delays[Math.min(visIndex, delays.length - 1)];
        }

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
        
        onStartAnimChanged: {
            if (startAnim) {
                // Reset all cards to initial state before animation
                clockHero.opacity = 0.0;
                clockHero.scale = 0.85;
                clockHeroTransform.y = 25;
                
                worldClocksLoader.opacity = 0.0;
                worldClocksLoader.scale = 0.85;
                worldClocksTransform.y = 25;
                
                infoColumn.opacity = 0.0;
                infoColumn.scale = 0.85;
                infoColumnTransform.y = 25;
                
                localSendLoader.opacity = 0.0;
                localSendLoader.scale = 0.85;
                localSendTransform.y = 25;
                
                alarmsCard.opacity = 0.0;
                alarmsCard.scale = 0.85;
                alarmsCardTransform.y = 25;
                
                // Start animations after reset
                Qt.callLater(function() {
                    clockHeroAnim.start();
                    worldClocksAnim.start();
                    infoColumnAnim.start();
                    localSendAnim.start();
                    alarmsCardAnim.start();
                });
            }
        }

        ClockHeaderCard {
            id: clockHero
            Layout.fillWidth: true
            Layout.minimumWidth: 400
            visible: Config.options.time.alarms.showAnalogClock
            
            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: clockHeroTransform
                y: 25
            }
            
            SequentialAnimation {
                id: clockHeroAnim
                
                PauseAnimation { duration: columnLayout.getDelay(0) }
                ParallelAnimation {
                    NumberAnimation { target: clockHero; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: clockHero; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: clockHeroTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }

        Loader {
            id: worldClocksLoader
            Layout.fillWidth: true
            Layout.minimumWidth: root.compact ? 320 : 360
            visible: active && Config.options.time.alarms.showWorldClocks
            active: Config.options.time.worldClocks && Config.options.time.worldClocks.length > 0
            sourceComponent: worldClocksComponent
            
            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: worldClocksTransform
                y: 25
            }
            
            SequentialAnimation {
                id: worldClocksAnim
                
                PauseAnimation { duration: columnLayout.getDelay(1) }
                ParallelAnimation {
                    NumberAnimation { target: worldClocksLoader; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: worldClocksLoader; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: worldClocksTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }

        ColumnLayout {
            id: infoColumn
            Layout.fillWidth: true
            spacing: 12
            
            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: infoColumnTransform
                y: 25
            }
            
            SequentialAnimation {
                id: infoColumnAnim
                
                PauseAnimation { duration: columnLayout.getDelay(2) }
                ParallelAnimation {
                    NumberAnimation { target: infoColumn; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: infoColumn; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: infoColumnTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            InfoPill {
                visible: !root.compact ? LocalSend.currentTransfer == null || LocalSend.droppedFiles.length > 0 : false
                textContent: Loader {
                    anchors.centerIn: parent
                    sourceComponent: TimerService.pomodoroRunning ? pomodoroText : (TimerService.stopwatchTime > 0 ? stopwatchText : timerOffText)
                }
                
                containerColor: TimerService.pomodoroBreak ? Appearance.colors.colTertiaryContainer : (TimerService.pomodoroRunning || TimerService.stopwatchRunning ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest)
                color: containerColor
                shapeColor: TimerService.pomodoroBreak ? Appearance.colors.colTertiary : (TimerService.pomodoroRunning || TimerService.stopwatchRunning ? Appearance.colors.colPrimary : Appearance.colors.colSecondary)
                symbolColor: TimerService.pomodoroBreak ? Appearance.colors.colOnTertiary : (TimerService.pomodoroRunning || TimerService.stopwatchRunning ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary)
                textColor: TimerService.pomodoroBreak ? Appearance.colors.colOnTertiaryContainer : (TimerService.pomodoroRunning || TimerService.stopwatchRunning ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer)
                icon: TimerService.pomodoroBreak ? "coffee" : root.stopwatchPaused ? "timer_pause" : TimerService.stopwatchRunning ? "timer_play" : "timer"
            }

            LocalSendPill {
                visible: LocalSend.available
            }
        }

        Component {
            id: transferCard
            LocalSendTransferCard {}
        }

        Component {
            id: sendCard
            LocalSendSendCard {}
        }

        Loader {
            id: localSendLoader
            Layout.fillWidth: true
            Layout.minimumWidth: root.compact ? 320 : 360
            visible: active
            active: LocalSend.currentTransfer !== null || LocalSend.droppedFiles.length > 0
            sourceComponent: LocalSend.currentTransfer !== null ? transferCard : sendCard
            
            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: localSendTransform
                y: 25
            }
            
            SequentialAnimation {
                id: localSendAnim
                
                PauseAnimation { duration: columnLayout.getDelay(3) }
                ParallelAnimation {
                    NumberAnimation { target: localSendLoader; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: localSendLoader; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: localSendTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }

        AlarmsCard {
            id: alarmsCard
            Layout.fillWidth: true
            Layout.minimumWidth: root.compact ? 320 : 360
            visible: Config.options.time.alarms.showAlarmsSection
            
            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: alarmsCardTransform
                y: 25
            }
            
            SequentialAnimation {
                id: alarmsCardAnim
                
                PauseAnimation { duration: columnLayout.getDelay(4) }
                ParallelAnimation {
                    NumberAnimation { target: alarmsCard; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: alarmsCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: alarmsCardTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }
        }

        Component {
            id: timerOffText
            StyledText {
                text: Translation.tr("Timer Off")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
            }
        }

        Component {
            id: pomodoroText
            StyledText {
                visible: TimerService.pomodoroRunning
                text: root.formatTimerDisplay(TimerService.pomodoroSecondsLeft)
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                font.weight: Font.Bold
            }
        }

        Component {
            id: stopwatchText
            RowLayout {
                id: textLayout
                visible: TimerService.stopwatchTime > 0
                width: 70 // To prevent shakiness
                anchors.centerIn: parent
                spacing: 0

                SequentialAnimation {
                    running: root.stopwatchPaused
                    loops: Animation.Infinite

                    ScriptAction { script: textLayout.visible = true }
                    PauseAnimation { duration: 700 }
                    ScriptAction { script: textLayout.visible = false }
                    PauseAnimation { duration: 700 }

                    onStopped: {
                        if (TimerService.stopwatchTime <= 0) return
                        textLayout.visible = true
                    }
                }

                StyledText {
                    color: Appearance.m3colors.m3onSurface
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold

                    text: {
                        let totalSeconds = Math.floor(TimerService.stopwatchTime) / 100
                        let minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                        let seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                        return `${minutes}:${seconds}`
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    font.weight: Font.Bold

                    text: {
                        return `:<sub>${(Math.floor(TimerService.stopwatchTime) % 100).toString().padStart(2, '0')}</sub>`
                    }
                }
            }
        }


        Component {
            id: worldClocksComponent
            WorldClocksCard {
                timezoneOffsets: root.timezoneOffsets
                getTimezoneOffsetString: root.getTimezoneOffsetString
                getUtcTimeForTz: root.getUtcTimeForTz
                getFormattedTime: root.getFormattedTime
                getFormattedDate: root.getFormattedDate
            }
        }


    }
}