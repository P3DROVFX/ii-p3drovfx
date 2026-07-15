import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    property real _ringAnimValue: 0.0
    readonly property real _realRingValue: TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration
    property int entranceTrigger: -1

    onEntranceTriggerChanged: {
        circularProgress.enableAnimation = false;
        _ringAnimValue = 0.0;
        contentTranslate.y = 20;
        Qt.callLater(function() {
            ringOpenSeq.start();
            contentEntranceAnim.start();
        });
    }

    SequentialAnimation {
        id: contentEntranceAnim
        PauseAnimation { duration: 50 }
        NumberAnimation { target: contentTranslate; property: "y"; from: 20; to: 0; duration: 380; easing.type: Easing.OutCubic }
    }

    SequentialAnimation {
        id: ringOpenSeq
        PauseAnimation { duration: 50 }
        NumberAnimation {
            target: root
            property: "_ringAnimValue"
            from: 0.0
            to: root._realRingValue
            duration: 800
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                circularProgress.enableAnimation = true;
                _ringAnimValue = Qt.binding(function() {
                    return TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration;
                });
            }
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        transform: Translate {
            id: contentTranslate
            y: 20
        }

        // The Pomodoro timer circle
        CircularProgress {
            id: circularProgress
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 8
            value: root._ringAnimValue
            implicitSize: 200
            enableAnimation: false

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        let minutes = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                        let seconds = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                        return `${minutes}:${seconds}`;
                    }
                    font.pixelSize: 40
                    color: Appearance.m3colors.m3onSurface
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
                implicitWidth: 36
                implicitHeight: implicitWidth

                StyledText {
                    id: cycleText
                    anchors.centerIn: parent
                    color: Appearance.colors.colOnLayer2
                    text: TimerService.pomodoroCycle + 1
                }
            }
        }

        // The Start/Stop and Reset buttons
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.pomodoroRunning ? Translation.tr("Pause") : (TimerService.pomodoroSecondsLeft === TimerService.focusTime) ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.pomodoroRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.togglePomodoro()
                colBackground: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90

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
        }
    }
}
