import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarDashboard
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: stopwatchTab
    Layout.fillWidth: true
    Layout.fillHeight: true
    property int entranceTrigger: -1
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations

    function finishEntrance() {
        if (entranceController.item)
            entranceController.item.stop();
        stopwatchTab.opacity = 1;
        elapsedEntranceTranslate.y = 0;
    }

    function beginEntrance() {
        if (!entranceAnimationsEnabled || entranceTrigger < 0) {
            finishEntrance();
            return;
        }
        stopwatchTab.opacity = 0;
        elapsedEntranceTranslate.y = 30;
        Qt.callLater(function() {
            if (stopwatchTab.entranceAnimationsEnabled && entranceController.item)
                entranceController.item.restart();
        });
    }

    onEntranceTriggerChanged: beginEntrance()
    onEntranceAnimationsEnabledChanged: entranceAnimationsEnabled ? beginEntrance() : finishEntrance()
    Component.onCompleted: beginEntrance()

    Loader {
        id: entranceController
        active: stopwatchTab.entranceAnimationsEnabled
        sourceComponent: Item {
            function restart() { animation.restart(); }
            function stop() { animation.stop(); }
            SequentialAnimation {
                id: animation
                PauseAnimation { duration: Math.round(Appearance.animation.elementMove.duration * 0.1) }
                ParallelAnimation {
                    SidebarGroupAnimation { target: stopwatchTab; property: "opacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                    SidebarGroupAnimation { target: elapsedEntranceTranslate; property: "y"; from: 30; to: 0; animationSpec: Appearance.animation.elementMove }
                }
            }
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
            transform: Translate { id: elapsedEntranceTranslate; y: 0 }

            anchors {
                top: undefined
                // Centred in what is left above the buttons, not in the whole
                // box: the button row is anchored to the bottom, so centring on
                // the box parks the time low, against them.
                verticalCenter: parent.verticalCenter
                verticalCenterOffset: -(controlButtons.height + 6) / 2
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
                text: `:<sub>${(Math.floor(TimerService.stopwatchTime) % 100).toString().padStart(2, '0')}</sub>`
            }
        }

        // Laps
        StyledListView {
            id: lapsList
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
                property var horizontalPadding: 10
                property var verticalPadding: 6
                property real _entranceOffset: 0
                property bool _entranceDone: true

                opacity: _entranceDone ? 1 : 0
                transform: Translate { y: lapItem._entranceDone ? 0 : lapItem._entranceOffset }

                function finishEntrance() {
                    if (lapEntranceController.item)
                        lapEntranceController.item.stop();
                    _entranceDone = true;
                    _entranceOffset = 0;
                }

                function beginEntrance() {
                    if (!stopwatchTab.entranceAnimationsEnabled || stopwatchTab.entranceTrigger < 0) {
                        finishEntrance();
                        return;
                    }
                    _entranceDone = false;
                    _entranceOffset = -20;
                    Qt.callLater(function() {
                        if (stopwatchTab.entranceAnimationsEnabled && lapEntranceController.item)
                            lapEntranceController.item.restart();
                    });
                }

                Component.onCompleted: beginEntrance()

                Connections {
                    target: stopwatchTab
                    function onEntranceTriggerChanged() { lapItem.beginEntrance(); }
                    function onEntranceAnimationsEnabledChanged() {
                        if (!stopwatchTab.entranceAnimationsEnabled)
                            lapItem.finishEntrance();
                    }
                }

                Loader {
                    id: lapEntranceController
                    active: stopwatchTab.entranceAnimationsEnabled
                    sourceComponent: Item {
                        function restart() { animation.restart(); }
                        function stop() { animation.stop(); }
                        SequentialAnimation {
                            id: animation
                            PauseAnimation {
                                duration: Math.round(Math.min(lapItem.index, 15)
                                    * Appearance.animation.elementMove.duration * 0.08)
                            }
                            ParallelAnimation {
                                SidebarGroupAnimation { target: lapItem; property: "opacity"; from: 0; to: 1; animationSpec: Appearance.animation.elementMove }
                                SidebarGroupAnimation { target: lapItem; property: "_entranceOffset"; from: -20; to: 0; animationSpec: Appearance.animation.elementMove }
                            }
                            ScriptAction { script: lapItem._entranceDone = true }
                        }
                    }
                }

                width: lapsList.width
                implicitHeight: lapRow.implicitHeight + verticalPadding * 2
                implicitWidth: lapRow.implicitWidth + horizontalPadding * 2
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.small
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
