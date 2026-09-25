import qs
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

    onOpenedChanged: {
        if (root.opened && (Config.options.time.worldClocks ?? []).length > 0)
            WorldClockService.refreshIfStale();
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

        property int _entranceGeneration: 0
        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        function resetContentEntrance() {
            _entranceGeneration++;

            clockHeroAnim.stop();
            worldClocksAnim.stop();
            infoColumnAnim.stop();
            localSendAnim.stop();
            alarmsCardAnim.stop();

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
        }

        function startContentEntrance() {
            const generation = _entranceGeneration;
            Qt.callLater(function() {
                if (!root.opened || !columnLayout.startAnim || generation !== _entranceGeneration)
                    return;

                clockHeroAnim.start();
                worldClocksAnim.start();
                infoColumnAnim.start();
                localSendAnim.start();
                alarmsCardAnim.start();
            });
        }

        onStartAnimChanged: {
            if (startAnim) {
                resetContentEntrance();
                startContentEntrance();
            }
        }

        Connections {
            target: root
            // Do not reset on close start: the cards must stay visible so they
            // shrink with the surface, like the other popups. The reset happens
            // once the close animation reaches progress 0.
            function onPopupOpenProgressChanged() {
                if (root.popupOpenProgress === 0.0) {
                    columnLayout.resetContentEntrance();
                }
            }
        }

        ClockHeaderCard {
            id: clockHero
            Layout.fillWidth: true
            Layout.minimumWidth: 400
            visible: Config.options.time.alarms.showAnalogClock
            startAnim: columnLayout.startAnim
            
            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: clockHeroTransform
                y: 25
            }
            
            MouseArea {
                id: clockHeroOpenArea
                anchors.fill: parent
                enabled: Config.options.clockApp?.enable ?? true
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    root.close();
                    GlobalStates.openClockApp("");
                }
            }

            Rectangle {
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: Appearance.rounding.normal / 2 + 4
                }
                visible: clockHeroOpenArea.enabled
                implicitWidth: openAppIcon.implicitWidth + 16
                implicitHeight: implicitWidth
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                opacity: clockHeroOpenArea.containsMouse ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MaterialSymbol {
                    id: openAppIcon
                    anchors.centerIn: parent
                    text: "open_in_full"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnPrimary
                }
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
            
            property bool startAnim: columnLayout.startAnim
            onStartAnimChanged: {
                if (startAnim) {
                    infoPill.startAnim = false;
                    localSendPill.startAnim = false;
                    Qt.callLater(function() {
                        infoPill.startAnim = true;
                        localSendPill.startAnim = true;
                    });
                }
            }
            
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
                id: infoPill
                visible: !root.compact ? LocalSend.currentTransfer == null || LocalSend.droppedFiles.length > 0 : false
                
                readonly property bool isTimerActive: TimerService.pomodoroRunning || TimerService.stopwatchRunning || root.stopwatchPaused || (TimerService.stopwatchTime > 0)

                textContent: Loader {
                    anchors.centerIn: parent
                    sourceComponent: TimerService.pomodoroRunning ? pomodoroText : (TimerService.stopwatchTime > 0 ? stopwatchText : timerOffText)
                }
                
                containerColor: TimerService.pomodoroBreak ? Appearance.colors.colTertiaryContainer : (infoPill.isTimerActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest)
                color: containerColor
                shapeColor: TimerService.pomodoroBreak ? Appearance.colors.colTertiary : (infoPill.isTimerActive ? Appearance.colors.colPrimary : Appearance.colors.colSecondary)
                symbolColor: TimerService.pomodoroBreak ? Appearance.colors.colOnTertiary : (infoPill.isTimerActive ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary)
                textColor: TimerService.pomodoroBreak ? Appearance.colors.colOnTertiaryContainer : (infoPill.isTimerActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer)
                
                leftInteractive: true
                icon: {
                    if (infoPill.isTimerActive) {
                        if (TimerService.pomodoroBreak) return "coffee";
                        if (TimerService.pomodoroRunning || TimerService.stopwatchRunning) return "pause";
                        return "play_arrow";
                    } else {
                        return infoPill.leftHovered ? "play_arrow" : "timer";
                    }
                }
                
                onLeftClicked: {
                    if (TimerService.pomodoroRunning) {
                        TimerService.togglePomodoro();
                    } else if (TimerService.stopwatchRunning || root.stopwatchPaused || TimerService.stopwatchTime > 0) {
                        TimerService.toggleStopwatch();
                    } else {
                        TimerService.toggleStopwatch();
                    }
                }

                showRightShape: infoPill.isTimerActive
                rightIcon: "stop"
                rightShapeColor: Appearance.colors.colErrorContainer
                rightSymbolColor: Appearance.colors.colOnErrorContainer
                
                onRightClicked: {
                    TimerService.stopwatchReset();
                    if (TimerService.pomodoroRunning) {
                        TimerService.resetPomodoro();
                    }
                }
            }

            LocalSendPill {
                id: localSendPill
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
            startAnim: columnLayout.startAnim
            
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
                timezoneOffsets: WorldClockService.offsets
                getTimezoneOffsetString: (tz, date) => WorldClockService.relativeOffsetLabel(tz, date)
                getUtcTimeForTz: (tz, date) => WorldClockService.zonedTime(tz, date)
                getFormattedTime: (tz, date) => WorldClockService.formatTime(tz, date, Config.options.time.secondPrecision)
                getFormattedDate: (tz, date) => WorldClockService.formatDate(tz, date)
                startAnim: columnLayout.startAnim
            }
        }


    }
}
