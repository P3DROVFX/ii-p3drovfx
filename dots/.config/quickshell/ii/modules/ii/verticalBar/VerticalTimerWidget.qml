pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.timer
import qs.services

/** Default Timer widget for the vertical bar. */
Item {
    id: root

    property color colBackground: Appearance.colors.colPrimary
    readonly property bool compVisible: timerState.visible
    readonly property int contentRotation: Config.options.bar.bottom ? 90 : -90

    visible: root.compVisible
    implicitWidth: root.compVisible ? Appearance.sizes.verticalBarWidth : 0
    implicitHeight: root.compVisible ? readoutColumn.implicitHeight + 12 : 0

    Behavior on implicitHeight {
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    function syncBarState() {
        if (typeof rootItem === "undefined")
            return;
        if (rootItem?.toggleHighlight)
            rootItem.toggleHighlight(true);
        if (rootItem?.toggleVisible)
            rootItem.toggleVisible(root.compVisible);
    }

    onCompVisibleChanged: root.syncBarState()
    Component.onCompleted: root.syncBarState()

    TimerBarState {
        id: timerState
    }

    ColumnLayout {
        id: readoutColumn
        anchors.centerIn: parent
        spacing: 8

        Loader {
            active: timerState.showStopwatch && timerState.hasStopwatch
            visible: active
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: VerticalReadout {
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
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: VerticalReadout {
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
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: VerticalReadout {
                iconName: timerState.countdownPaused ? "pause_circle" : "hourglass_top"
                value: timerState.countdownText
                badgeCount: timerState.countdownCount
                tooltip: timerState.countdownTooltip
                onTriggered: timerState.toggleCountdown()
            }
        }
    }

    component VerticalReadout: RippleButton {
        id: readout

        property string iconName: ""
        property string value: ""
        property string tooltip: ""
        property int badgeCount: 0
        signal triggered

        implicitWidth: Math.max(iconItem.implicitWidth, timeHolder.implicitWidth,
            countBadge.visible ? countBadge.implicitWidth : 0) + 4
        implicitHeight: content.implicitHeight + 4
        buttonRadius: Appearance.rounding.full
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colBackgroundActive: Appearance.colors.colPrimaryActive
        colRipple: Appearance.colors.colPrimaryActive
        onPressed: readout.triggered()

        ColumnLayout {
            id: content
            anchors.centerIn: parent
            spacing: 3

            MaterialSymbol {
                id: iconItem
                Layout.alignment: Qt.AlignHCenter
                text: readout.iconName
                color: Appearance.colors.colOnPrimary
                iconSize: Appearance.font.pixelSize.large
            }

            Item {
                id: timeHolder
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: timeText.implicitHeight
                implicitHeight: timeText.implicitWidth

                StyledText {
                    id: timeText
                    anchors.centerIn: parent
                    rotation: root.contentRotation
                    text: readout.value
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.features: ({ "tnum": 1 })
                    color: Appearance.colors.colOnPrimary
                }
            }

            Rectangle {
                id: countBadge
                visible: readout.badgeCount > 1
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 18
                implicitHeight: 18
                radius: Appearance.rounding.full
                color: Appearance.colors.colOnPrimary

                StyledText {
                    anchors.centerIn: parent
                    text: String(readout.badgeCount)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colPrimary
                }
            }
        }

        StyledToolTip {
            text: readout.tooltip
            requireOverlay: false
        }
    }
}
