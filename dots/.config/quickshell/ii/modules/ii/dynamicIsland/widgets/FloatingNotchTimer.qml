import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property bool pomodoroActive: TimerService.pomodoroRunning
    readonly property bool stopwatchActive: TimerService.stopwatchRunning

    readonly property bool isPomodoro: pomodoroActive || (TimerService.pomodoroSecondsLeft < TimerService.focusTime && TimerService.pomodoroSecondsLeft > 0)

    // Format Pomodoro Time (HH:MM:SS or MM:SS)
    readonly property string pomodoroText: {
        const totalSecs = TimerService.pomodoroSecondsLeft;
        const hours = Math.floor(totalSecs / 3600);
        const mins = Math.floor((totalSecs % 3600) / 60);
        const secs = totalSecs % 60;
        if (hours > 0) {
            return String(hours).padStart(2, '0') + ":" + String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
        }
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
    }

    // Format Stopwatch Time (HH:MM:SS.CC or MM:SS.CC)
    readonly property string stopwatchText: {
        const totalCentis = TimerService.stopwatchTime;
        const totalSecs = Math.floor(totalCentis / 100);
        const hours = Math.floor(totalSecs / 3600);
        const mins = Math.floor((totalSecs % 3600) / 60);
        const secs = totalSecs % 60;
        const centis = totalCentis % 100;
        if (hours > 0) {
            return String(hours).padStart(2, '0') + ":" + String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0');
        }
        return String(mins).padStart(2, '0') + ":" + String(secs).padStart(2, '0') + "." + String(centis).padStart(2, '0');
    }

    // Format Stopwatch Time for Expanded (displays hours, minutes, seconds, centiseconds clearly)
    readonly property string expandedTimeText: {
        if (root.isPomodoro) {
            return root.pomodoroText;
        } else {
            return root.stopwatchText;
        }
    }

    readonly property string timerLabel: {
        if (root.isPomodoro) {
            return TimerService.pomodoroLongBreak ? Translation.tr("Long break") : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus");
        }
        return Translation.tr("Stopwatch");
    }

    // ==========================================
    // 1. CONTRACTED MODE (Wide premium pill display)
    // ==========================================
    RowLayout {
        id: contractedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8
        visible: !root.isExpanded

        // Left side: Rounded Pill with the Timer
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.height - 8
            Layout.alignment: Qt.AlignVCenter
            radius: height / 2
            color: root.isPomodoro
                ? (TimerService.pomodoroBreak ? Appearance.colors.colPrimaryContainer : Appearance.colors.colErrorContainer)
                : Appearance.colors.colSecondaryContainer

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    text: root.isPomodoro ? "timer" : "schedule"
                    iconSize: 14
                    color: root.isPomodoro
                        ? (TimerService.pomodoroBreak ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer)
                        : Appearance.colors.colOnSecondaryContainer
                }

                StyledText {
                    text: root.isPomodoro ? root.pomodoroText : root.stopwatchText
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: root.isPomodoro
                        ? (TimerService.pomodoroBreak ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnErrorContainer)
                        : Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        // Right side: Active state label
        StyledText {
            text: root.timerLabel
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Black
            color: Appearance.colors.colOnSurfaceVariant
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: 60
            elide: Text.ElideRight
        }
    }

    // ==========================================
    // 2. EXPANDED MODE (Actions dashboard)
    // ==========================================
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 8
        anchors.bottomMargin: 8
        spacing: 4
        visible: root.isExpanded

        // Top Row: Title + State info
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            MaterialSymbol {
                text: root.isPomodoro ? "timer" : "schedule"
                iconSize: 14
                color: Appearance.colors.colPrimary
            }

            StyledText {
                text: root.isPomodoro ? Translation.tr("Focus Timer") : Translation.tr("Stopwatch")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: root.isPomodoro 
                    ? (Translation.tr("Cycle %1").arg(TimerService.pomodoroCycle + 1) + " • " + root.timerLabel)
                    : (TimerService.stopwatchLaps.length > 0 ? Translation.tr("Lap %1").arg(TimerService.stopwatchLaps.length + 1) : root.timerLabel)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        // Middle Row: Bold Big Time Text
        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.expandedTimeText
            font.family: Appearance.font.family.title
            font.pixelSize: 26
            font.weight: Font.Black
            color: Appearance.colors.colOnSurface
        }

        // Bottom Row: Action Controls
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Toggle play/pause button
            Rectangle {
                id: playPauseBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: Appearance.rounding.full
                color: {
                    const active = root.isPomodoro ? TimerService.pomodoroRunning : TimerService.stopwatchRunning;
                    if (playPauseMa.containsMouse) {
                        return active ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colPrimaryHover;
                    }
                    return active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary;
                }

                scale: playPauseMa.pressed ? 0.95 : (playPauseMa.containsMouse ? 1.02 : 1.0)

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on scale { NumberAnimation { duration: 150 } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: {
                            const active = root.isPomodoro ? TimerService.pomodoroRunning : TimerService.stopwatchRunning;
                            return active ? "pause" : "play_arrow";
                        }
                        iconSize: 12
                        color: {
                            const active = root.isPomodoro ? TimerService.pomodoroRunning : TimerService.stopwatchRunning;
                            return active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary;
                        }
                    }
                    StyledText {
                        text: {
                            const active = root.isPomodoro ? TimerService.pomodoroRunning : TimerService.stopwatchRunning;
                            return active ? Translation.tr("Pause") : (TimerService.stopwatchTime === 0 && !root.isPomodoro ? Translation.tr("Start") : Translation.tr("Resume"));
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        color: {
                            const active = root.isPomodoro ? TimerService.pomodoroRunning : TimerService.stopwatchRunning;
                            return active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary;
                        }
                    }
                }

                MouseArea {
                    id: playPauseMa
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: {
                        if (root.isPomodoro) {
                            TimerService.togglePomodoro();
                        } else {
                            TimerService.toggleStopwatch();
                        }
                    }
                }
            }

            // Secondary action button (Reset / Lap)
            Rectangle {
                id: actionBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: Appearance.rounding.full
                color: {
                    const isStopwatchRunning = !root.isPomodoro && TimerService.stopwatchRunning;
                    const containerColor = isStopwatchRunning ? Appearance.colors.colSurfaceContainerHighest : Appearance.m3colors.m3errorContainer;
                    const hoverColor = isStopwatchRunning ? Appearance.colors.colSurfaceContainerHighestHover : Appearance.colors.colErrorContainerHover;
                    return actionMa.containsMouse ? hoverColor : containerColor;
                }

                scale: actionMa.pressed ? 0.95 : (actionMa.containsMouse ? 1.02 : 1.0)
                enabled: {
                    if (root.isPomodoro) {
                        return (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration) || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak;
                    } else {
                        return TimerService.stopwatchTime > 0 || TimerService.stopwatchLaps.length > 0;
                    }
                }
                opacity: enabled ? 1.0 : 0.4

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on scale { NumberAnimation { duration: 150 } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: {
                            if (root.isPomodoro) return "restart_alt";
                            return TimerService.stopwatchRunning ? "flag" : "restart_alt";
                        }
                        iconSize: 12
                        color: {
                            const isStopwatchRunning = !root.isPomodoro && TimerService.stopwatchRunning;
                            return isStopwatchRunning ? Appearance.colors.colOnSurface : Appearance.m3colors.m3onErrorContainer;
                        }
                    }
                    StyledText {
                        text: {
                            if (root.isPomodoro) return Translation.tr("Reset");
                            return TimerService.stopwatchRunning ? Translation.tr("Lap") : Translation.tr("Reset");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        color: {
                            const isStopwatchRunning = !root.isPomodoro && TimerService.stopwatchRunning;
                            return isStopwatchRunning ? Appearance.colors.colOnSurface : Appearance.m3colors.m3onErrorContainer;
                        }
                    }
                }

                MouseArea {
                    id: actionMa
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: {
                        if (root.isPomodoro) {
                            TimerService.resetPomodoro();
                        } else {
                            if (TimerService.stopwatchRunning) {
                                TimerService.stopwatchRecordLap();
                            } else {
                                TimerService.stopwatchReset();
                            }
                        }
                    }
                }
            }
        }
    }
}
