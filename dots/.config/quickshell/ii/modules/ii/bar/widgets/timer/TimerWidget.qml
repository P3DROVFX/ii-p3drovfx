import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    readonly property bool pRunning: TimerService.pomodoroRunning ?? false
    readonly property bool sRunning: TimerService.stopwatchRunning ?? false
    readonly property bool hasStop: TimerService.stopwatchTime > 0
    readonly property bool hasPomo: TimerService.pomodoroSecondsLeft > 0 && (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration || pRunning)

    property bool showPomodoro: Config.options.bar.timers.showPomodoro
    property bool showStopwatch: Config.options.bar.timers.showStopwatch

    property bool compVisible: ((hasStop || sRunning) && root.showStopwatch) || ((pRunning || hasPomo) && root.showPomodoro)

    visible: compVisible
    implicitWidth: compVisible ? (rowLayout.implicitWidth + (rowLayout.implicitWidth > 0 ? rowLayout.spacing * 5 : 0)) : 0
    implicitHeight: compVisible ? Appearance.sizes.baseBarHeight : 0

    onCompVisibleChanged: rootItem.toggleVisible(compVisible)

    Behavior on implicitWidth {
        animation: Appearance.animation.barResize.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimaryContainer
    }

    function formatTime(time) {
        const sec = Math.floor(time / 100);
        return Math.floor(sec / 60).toString().padStart(2, '0') + ":" + (sec % 60).toString().padStart(2, '0') + "." + (time % 100).toString().padStart(2, '0');
    }

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4

        Loader {
            active: hasStop && showStopwatch
            visible: active
            Layout.preferredWidth: 90 // we have to enter a fixed size or else it will jitter as the time changes
            sourceComponent: RowLayout {
                MaterialSymbol {
                    text: root.sRunning ? "timer" : "timer_pause"
                    color: Appearance.colors.colOnPrimaryContainer
                    iconSize: Appearance.font.pixelSize.large
                }

                StyledText {
                    Layout.topMargin: 3
                    text: formatTime(TimerService.stopwatchTime)
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    TimerService.toggleStopwatch();
                }
            }
        }

        Item {
            visible: hasStop && hasPomo
            Layout.preferredWidth: hasStop && hasPomo ? 2 : 0
        }

        Loader {
            active: hasPomo && showPomodoro
            visible: active
            Layout.preferredWidth: 60
            Layout.rightMargin: 5
            sourceComponent: RowLayout {
                MaterialSymbol {
                    text: root.pRunning ? "search_activity" : "pause_circle"
                    color: Appearance.colors.colOnPrimaryContainer
                    iconSize: Appearance.font.pixelSize.large
                }

                StyledText {
                    Layout.topMargin: 3
                    text: {
                        const t = TimerService.pomodoroSecondsLeft;
                        return Math.floor(t / 60).toString().padStart(2, '0') + ":" + (t % 60).toString().padStart(2, '0');
                    }
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    TimerService.togglePomodoro();
                }
            }
        }
    }
}
