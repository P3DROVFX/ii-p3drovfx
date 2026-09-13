pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/** Default horizontal Timer & Pomodoro widget. */
Item {
    id: root

    readonly property bool compVisible: timerState.visible

    visible: root.compVisible
    implicitWidth: root.compVisible ? readoutRow.implicitWidth + 16 : 0
    implicitHeight: root.compVisible ? Appearance.sizes.baseBarHeight : 0

    function syncBarVisibility() {
        if (typeof rootItem !== "undefined" && rootItem?.toggleVisible)
            rootItem.toggleVisible(root.compVisible);
    }

    onCompVisibleChanged: root.syncBarVisibility()
    Component.onCompleted: root.syncBarVisibility()

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    TimerBarState {
        id: timerState
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimaryContainer
    }

    RowLayout {
        id: readoutRow
        anchors.centerIn: parent
        spacing: 8

        Loader {
            active: timerState.showStopwatch && timerState.hasStopwatch
            visible: active
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: TimerReadout {
                iconName: timerState.stopwatchRunning ? "timer" : "timer_pause"
                value: timerState.stopwatchText
                tooltip: timerState.stopwatchRunning
                    ? Translation.tr("Pause stopwatch")
                    : Translation.tr("Resume stopwatch")
                onTriggered: TimerService.toggleStopwatch()
            }
        }

        Loader {
            active: timerState.showPomodoro && timerState.hasPomodoro
            visible: active
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: TimerReadout {
                iconName: timerState.pomodoroRunning ? "search_activity" : "pause_circle"
                value: timerState.pomodoroText
                tooltip: timerState.pomodoroRunning
                    ? Translation.tr("Pause pomodoro")
                    : Translation.tr("Resume pomodoro")
                onTriggered: TimerService.togglePomodoro()
            }
        }

        Loader {
            active: timerState.showCountdowns && timerState.hasCountdown
            visible: active
            Layout.alignment: Qt.AlignVCenter
            sourceComponent: TimerReadout {
                iconName: timerState.countdownPaused ? "pause_circle" : "hourglass_top"
                value: timerState.countdownText
                badgeCount: timerState.countdownCount
                tooltip: timerState.countdownTooltip
                onTriggered: timerState.toggleCountdown()
            }
        }
    }

    component TimerReadout: RippleButton {
        id: readout

        property string iconName: ""
        property string value: ""
        property string tooltip: ""
        property int badgeCount: 0
        signal triggered

        implicitWidth: content.implicitWidth + 6
        implicitHeight: content.implicitHeight + 4
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        colBackgroundActive: Appearance.colors.colPrimaryContainerActive
        colRipple: Appearance.colors.colPrimaryContainerActive
        onPressed: readout.triggered()

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: readout.iconName
                color: Appearance.colors.colOnPrimaryContainer
                iconSize: Appearance.font.pixelSize.large
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.topMargin: 2
                text: readout.value
                font.features: ({ "tnum": 1 })
                color: Appearance.colors.colOnPrimaryContainer
            }

            Rectangle {
                visible: readout.badgeCount > 1
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 18
                implicitHeight: 18
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary

                StyledText {
                    anchors.centerIn: parent
                    text: String(readout.badgeCount)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        StyledToolTip {
            text: readout.tooltip
            requireOverlay: false
        }
    }
}
