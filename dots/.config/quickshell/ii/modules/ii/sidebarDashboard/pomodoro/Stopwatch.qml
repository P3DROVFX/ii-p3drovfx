import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: stopwatchTab
    Layout.fillWidth: true
    Layout.fillHeight: true

    property int _openCountdown: 5900
    property bool _openingDone: false
    property int entranceTrigger: -1

    function beginEntrance() {
        stopwatchTab.opacity = 0;
        stopwatchTab._openingDone = false;
        stopwatchTab._openCountdown = 5900;
        countdownTimer.restart();
        Qt.callLater(function() {
            entranceAnim.start();
        });
    }

    Component.onCompleted: {
        beginEntrance();
    }

    onEntranceTriggerChanged: {
        stopwatchTab.opacity = 0;
        elapsedEntranceTranslate.y = 30;
        beginEntrance();
    }

    Timer {
        id: countdownTimer
        interval: 18
        repeat: true
        onTriggered: {
            stopwatchTab._openCountdown -= 70;
            if (stopwatchTab._openCountdown <= 0) {
                stopwatchTab._openCountdown = 0;
                stopwatchTab._openingDone = true;
                countdownTimer.stop();
            }
        }
    }

    SequentialAnimation {
        id: entranceAnim
        PauseAnimation { duration: 50 }
        ParallelAnimation {
            NumberAnimation { target: stopwatchTab; property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.OutCubic }
            NumberAnimation { target: elapsedEntranceTranslate; property: "y"; from: 30; to: 0; duration: 300; easing.type: Easing.OutCubic }
        }
    }

    Item {
        anchors {
            fill: parent
            topMargin: 8
            leftMargin: 16
            rightMargin: 16
        }

        RowLayout { // Elapsed
            id: elapsedIndicator

            transform: Translate {
                id: elapsedEntranceTranslate
                y: 30
            }
            
            anchors {
                top: undefined
                verticalCenter: parent.verticalCenter
                left: controlButtons.left
                leftMargin: 6
            }

            states: State {
                name: "hasLaps"
                when: TimerService.stopwatchLaps.length > 0
                AnchorChanges {
                    target: elapsedIndicator
                    anchors.top: parent.top
                    anchors.verticalCenter: undefined
                    anchors.left: controlButtons.left
                }
            }

            transitions: Transition {
                AnchorAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            spacing: 0
            StyledText {
                font.pixelSize: 40
                color: Appearance.m3colors.m3onSurface
                text: {
                    if (!stopwatchTab._openingDone) {
                        let total = stopwatchTab._openCountdown;
                        let m = Math.floor(total / 6000).toString().padStart(2, '0');
                        let s = Math.floor((total % 6000) / 100).toString().padStart(2, '0');
                        return m + ":" + s;
                    }
                    let totalSeconds = Math.floor(TimerService.stopwatchTime) / 100
                    let minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                    let seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                    return `${minutes}:${seconds}`
                }
            }
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: 40
                color: Appearance.colors.colSubtext
                text: {
                    if (!stopwatchTab._openingDone) {
                        let c = stopwatchTab._openCountdown % 100;
                        return `:<sub>${c.toString().padStart(2, '0')}</sub>`;
                    }
                    return `:<sub>${(Math.floor(TimerService.stopwatchTime) % 100).toString().padStart(2, '0')}</sub>`
                }
            }
        }

        // Laps
        StyledListView {
            id: lapsList
            property int entranceTrigger: stopwatchTab.entranceTrigger
            anchors {
                top: elapsedIndicator.bottom
                bottom: controlButtons.top
                left: parent.left
                right: parent.right
                topMargin: 16
                bottomMargin: 16
            }
            spacing: 4
            clip: true
            popin: true

            model: ScriptModel {
                values: TimerService.stopwatchLaps.map((v, i, arr) => arr[arr.length - 1 - i])
            }

            delegate: Rectangle {
                id: lapItem
                required property int index
                required property var modelData
                property int entranceTrigger: lapsList.entranceTrigger
                property var horizontalPadding: 10
                property var verticalPadding: 6
                property real _entranceOffset: -20

                width: lapsList.width
                implicitHeight: lapRow.implicitHeight + verticalPadding * 2
                implicitWidth: lapRow.implicitWidth + horizontalPadding * 2
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.small
                opacity: 0

                transform: Translate {
                    y: lapItem._entranceOffset
                }

                Component.onCompleted: {
                    lapItem.opacity = 0;
                    lapItem._entranceOffset = -20;
                    Qt.callLater(function() {
                        lapEntranceAnim.start();
                    });
                }

                onEntranceTriggerChanged: {
                    lapItem.opacity = 0;
                    lapItem._entranceOffset = -20;
                    Qt.callLater(function() {
                        lapEntranceAnim.start();
                    });
                }

                SequentialAnimation {
                    id: lapEntranceAnim
                    PauseAnimation { duration: Math.min(lapItem.index, 15) * 35 }
                    ParallelAnimation {
                        NumberAnimation { target: lapItem; property: "opacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
                        NumberAnimation { target: lapItem; property: "_entranceOffset"; from: -20; to: 0; duration: 300; easing.type: Easing.OutCubic }
                    }
                }

                RowLayout {
                    id: lapRow
                    anchors {
                        fill: parent
                        leftMargin: lapItem.horizontalPadding
                        rightMargin: lapItem.horizontalPadding
                        topMargin: lapItem.verticalPadding
                        bottomMargin: lapItem.verticalPadding
                    }

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        text: `${TimerService.stopwatchLaps.length - lapItem.index}.`
                    }

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: {
                            const lapTime = lapItem.modelData
                            const _10ms = (Math.floor(lapTime) % 100).toString().padStart(2, '0')
                            const totalSeconds = Math.floor(lapTime) / 100
                            const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                            const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                            return `${minutes}:${seconds}.${_10ms}`
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colPrimary
                        text: {
                            const originalIndex = TimerService.stopwatchLaps.length - lapItem.index - 1
                            const lastTime = originalIndex > 0 ? TimerService.stopwatchLaps[originalIndex - 1] : 0
                            const lapTime = lapItem.modelData - lastTime
                            const _10ms = (Math.floor(lapTime) % 100).toString().padStart(2, '0')
                            const totalSeconds = Math.floor(lapTime) / 100
                            const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, '0')
                            const seconds = Math.floor(totalSeconds % 60).toString().padStart(2, '0')
                            return `+${minutes == "00" ? "" : minutes + ":"}${seconds}.${_10ms}`
                        }
                    }
                }
            }
        }

        RowLayout {
            id: controlButtons
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
                bottomMargin: 6
            }
            spacing: 4

            RippleButton {
                Layout.preferredHeight: 35
                Layout.preferredWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger

                onClicked: {
                    TimerService.toggleStopwatch()
                }

                colBackground: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary 
                colBackgroundHover: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover 
                colRipple: TimerService.stopwatchRunning ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colPrimaryActive 

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    color: TimerService.stopwatchRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                    text: TimerService.stopwatchRunning ? Translation.tr("Pause") : TimerService.stopwatchTime === 0 ? Translation.tr("Start") : Translation.tr("Resume")
                }
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger

                onClicked: {
                    if (TimerService.stopwatchRunning) 
                        TimerService.stopwatchRecordLap()
                    else 
                        TimerService.stopwatchReset()
                }
                enabled: TimerService.stopwatchTime > 0 || Persistent.states.timer.stopwatch.laps.length > 0

                colBackground: TimerService.stopwatchRunning ? Appearance.colors.colLayer2 : Appearance.colors.colErrorContainer
                colBackgroundHover: TimerService.stopwatchRunning ? Appearance.colors.colLayer2Hover : Appearance.colors.colErrorContainerHover
                colRipple: TimerService.stopwatchRunning ? Appearance.colors.colLayer2Active : Appearance.colors.colErrorContainerActive

                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.stopwatchRunning ? Translation.tr("Lap") : Translation.tr("Reset")
                    color: TimerService.stopwatchRunning ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnErrorContainer
                }
            }
        }
    }
}