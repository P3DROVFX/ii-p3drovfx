import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarDashboard
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    // A 200px dial plus a 35px button row does not fit the 260px bottom group
    // the sidebar banner leaves room for, and the overflow is clipped rather
    // than scrolled - the buttons simply vanish. The dial is the elastic part.
    readonly property real ringGap: 10
    readonly property real ringSize: {
        if (root.height <= 0)
            return 200;
        return Math.max(110, Math.min(200, root.height - buttonsRow.implicitHeight - root.ringGap));
    }

    readonly property real _realRingValue: TimerService.pomodoroLapDuration > 0 ? (TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration) : 0
    property real _ringAnimValue: _realRingValue
    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations

    function finishEntrance() {
        if (entranceController.item)
            entranceController.item.stop();
        contentTranslate.y = 0;
        _ringAnimValue = Qt.binding(function() { return root._realRingValue; });
    }

    function beginEntrance() {
        if (!entranceAnimationsEnabled || entranceTrigger < 0) {
            finishEntrance();
            return;
        }
        _ringAnimValue = 0;
        contentTranslate.y = 20;
        Qt.callLater(function() {
            if (root.entranceAnimationsEnabled && entranceController.item)
                entranceController.item.restart();
        });
    }

    onEntranceTriggerChanged: beginEntrance()
    onEntranceAnimationsEnabledChanged: entranceAnimationsEnabled ? beginEntrance() : finishEntrance()
    Component.onCompleted: beginEntrance()

    Loader {
        id: entranceController
        active: root.entranceAnimationsEnabled
        sourceComponent: Item {
            function restart() { animation.restart(); }
            function stop() { animation.stop(); }
            SequentialAnimation {
                id: animation
                PauseAnimation { duration: Math.round(Appearance.animation.elementMove.duration * 0.1) }
                ParallelAnimation {
                    SidebarGroupAnimation { target: contentTranslate; property: "y"; from: 20; to: 0; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: root; property: "_ringAnimValue"; from: 0; to: root._realRingValue; animationSpec: Appearance.animation.elementMove }
                }
                ScriptAction {
                    script: root._ringAnimValue = Qt.binding(function() { return root._realRingValue; })
                }
            }
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.centerIn: parent
        spacing: root.ringGap
        transform: Translate { id: contentTranslate; y: 0 }

        // The Pomodoro timer circle
        CircularProgress {
            id: circularProgress
            Layout.alignment: Qt.AlignHCenter
            lineWidth: Math.max(5, Math.round(root.ringSize / 25))
            value: root._ringAnimValue
            implicitSize: root.ringSize
            // The service changes in one-second steps. Interpolating every
            // step for 800ms kept the Shape layer rendering almost constantly.
            enableAnimation: false

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                Item {
                    id: timeClickableArea
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: timeText.implicitWidth + 16
                    implicitHeight: timeText.implicitHeight + 6

                    Rectangle {
                        id: timeHoverBg
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: timeMouseArea.containsMouse ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.12) : "transparent"
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(timeHoverBg)
                        }
                    }

                    StyledText {
                        id: timeText
                        anchors.centerIn: parent
                        text: {
                            let totalSecs = Math.max(0, TimerService.pomodoroSecondsLeft);
                            let hours = Math.floor(totalSecs / 3600);
                            let minutes = Math.floor((totalSecs % 3600) / 60).toString().padStart(2, '0');
                            let seconds = Math.floor(totalSecs % 60).toString().padStart(2, '0');
                            if (hours > 0) {
                                return `${hours.toString().padStart(2, '0')}:${minutes}:${seconds}`;
                            }
                            return `${minutes}:${seconds}`;
                        }
                        font.pixelSize: {
                            let totalSecs = Math.max(0, TimerService.pomodoroSecondsLeft);
                            let hours = Math.floor(totalSecs / 3600);
                            return Math.round(Math.max(20, Math.min(hours > 0 ? 30 : 40, root.ringSize * (hours > 0 ? 0.19 : 0.25))));
                        }
                        font.weight: Font.Bold
                        color: timeMouseArea.containsMouse ? Appearance.colors.colPrimary : Appearance.m3colors.m3onSurface
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(timeText)
                        }
                    }

                    MouseArea {
                        id: timeMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let currentSeconds = TimerService.pomodoroSecondsLeft > 0 ? TimerService.pomodoroSecondsLeft : TimerService.pomodoroLapDuration;
                            let startHour = Math.floor(currentSeconds / 3600);
                            let startMinute = Math.floor((currentSeconds % 3600) / 60);
                            let title = TimerService.pomodoroLongBreak ? Translation.tr("Long break time") : TimerService.pomodoroBreak ? Translation.tr("Break time") : Translation.tr("Focus time");
                            TimerService.requestCustomTime(startHour, startMinute, title);
                        }
                    }

                    StyledToolTip {
                        extraVisibleCondition: timeMouseArea.containsMouse
                        text: Translation.tr("Click to set custom time")
                    }
                }

                StyledText {
                    id: modeLabel
                    Layout.alignment: Qt.AlignHCenter
                    text: TimerService.pomodoroLongBreak ? Translation.tr("Long break") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext

                    property string _lastMode: ""
                    readonly property string _currentMode: TimerService.pomodoroLongBreak ? "long" : TimerService.pomodoroBreak ? "break" : "focus"

                    transform: Scale {
                        id: modeScale
                        origin.y: modeLabel.height / 2
                        yScale: 1.0
                    }

                    on_CurrentModeChanged: {
                        if (_lastMode !== "" && _lastMode !== _currentMode) {
                            modeFlip.restart();
                        }
                        _lastMode = _currentMode;
                    }

                    SequentialAnimation {
                        id: modeFlip
                        NumberAnimation { target: modeScale; property: "yScale"; from: 1.0; to: 0.0; duration: 120; easing.type: Easing.InCubic }
                        NumberAnimation { target: modeScale; property: "yScale"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutBack }
                    }
                }
            }

            Rectangle {
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                }
                implicitWidth: Math.round(Math.max(26, Math.min(36, root.ringSize * 0.18)))
                implicitHeight: implicitWidth

                StyledText {
                    id: cycleText
                    anchors.centerIn: parent
                    color: Appearance.colors.colOnLayer2
                    text: TimerService.pomodoroCycle + 1
                }
            }
        }

        // The Start/Stop, Reset and Edit buttons
        RowLayout {
            id: buttonsRow
            Layout.alignment: Qt.AlignHCenter
            spacing: 8

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.pomodoroRunning ? Translation.tr("Pause") : (TimerService.pomodoroSecondsLeft === TimerService.pomodoroLapDuration) ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.pomodoroRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 84
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.togglePomodoro()
                colBackground: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover
                colRipple: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 84

                onClicked: TimerService.resetPomodoro()
                enabled: (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration) || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak

                font.pixelSize: Appearance.font.pixelSize.larger
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive

                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.colors.colOnErrorContainer
                }
            }

            RippleButton {
                id: editTimeButton
                implicitHeight: 35
                implicitWidth: 35
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: {
                    let currentSeconds = TimerService.pomodoroSecondsLeft > 0 ? TimerService.pomodoroSecondsLeft : TimerService.pomodoroLapDuration;
                    let startHour = Math.floor(currentSeconds / 3600);
                    let startMinute = Math.floor((currentSeconds % 3600) / 60);
                    let title = TimerService.pomodoroLongBreak ? Translation.tr("Long break time") : TimerService.pomodoroBreak ? Translation.tr("Break time") : Translation.tr("Focus time");
                    TimerService.requestCustomTime(startHour, startMinute, title);
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSecondaryContainer
                }

                StyledToolTip {
                    extraVisibleCondition: editTimeButton.hovered
                    text: Translation.tr("Set custom time")
                }
            }
        }
    }
}
