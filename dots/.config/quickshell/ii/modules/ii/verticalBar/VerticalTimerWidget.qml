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

    property color colBackground: Appearance.colors.colPrimary // to be used from BarComponent

    property bool showPomodoro: Config.options.bar.timers.showPomodoro
    property bool showStopwatch: Config.options.bar.timers.showStopwatch

    implicitWidth: Appearance.sizes.verticalBarWidth
    implicitHeight: columnLayout.implicitHeight + columnLayout.spacing * 4

    property bool compVisible: ((hasStop || sRunning) && root.showStopwatch) || ((pRunning || hasPomo) && root.showPomodoro)

    onCompVisibleChanged: rootItem.toggleVisible(compVisible)
    Component.onCompleted: {
        rootItem.toggleHighlight(true)
        rootItem.toggleVisible(compVisible)
    }

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    function formatTime(time) {
        const sec = Math.floor(time/100)
        const min = Math.floor(sec/60)
        if (min > 0) {
            return min.toString().padStart(2,'0') + ":" + (sec%60).toString().padStart(2,'0') + "\n" +
                   (time%100).toString().padStart(2,'0')
        }
        return (sec%60).toString().padStart(2,'0') + "\n" +
               (time%100).toString().padStart(2,'0')
    }

    ColumnLayout {
        id: columnLayout
        anchors.centerIn: parent
        spacing: 4

        Loader {
            active: hasStop && showStopwatch
            visible: active
            Layout.alignment: Qt.AlignHCenter
            sourceComponent: ColumnLayout {
                MaterialSymbol {
                    text: root.sRunning ? "timer" : "timer_pause"
                    color: Appearance.colors.colOnPrimary
                    iconSize: Appearance.font.pixelSize.large
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: formatTime(TimerService.stopwatchTime)
                    color: Appearance.colors.colOnPrimary
                }
            }  
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    TimerService.toggleStopwatch()
                }
            } 
        }

        Item {
            visible: hasStop && hasPomo
            Layout.preferredHeight: hasStop && hasPomo ? 2 : 0
        }

        Loader {
            active: hasPomo && showPomodoro
            visible: active
            Layout.preferredHeight: 50
            Layout.bottomMargin: 10
            Layout.alignment: Qt.AlignHCenter
            Layout.leftMargin: 2
            
            sourceComponent: ColumnLayout {
                MaterialSymbol {
                    text: root.pRunning ? "search_activity" : "pause_circle"
                    color: Appearance.colors.colOnPrimary
                    iconSize: Appearance.font.pixelSize.large
                }

                StyledText {
                    text: {
                        const t = TimerService.pomodoroSecondsLeft
                        return Math.floor(t/60).toString().padStart(2,'0') + "\n" + (t%60).toString().padStart(2,'0')
                    }
                    color: Appearance.colors.colOnPrimary
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    TimerService.togglePomodoro()
                }
            } 
        }

    }
}