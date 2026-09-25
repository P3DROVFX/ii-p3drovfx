pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Pomodoro: the phase as a chip, the time left inside a wavy ring in the phase's colour,
 * the cycle as a row of shapes, and reset / start-pause / skip. The same TimerService
 * pomodoro the sidebar, the bar and the island show.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property bool sideBySide: root.width >= ClockStyle.mediumMax
    readonly property real durationsWidth: Math.min(root.width * 0.38, ClockStyle.sheetMaxWidth)
    readonly property real ringSize: Math.max(ClockStyle.worldDialMin, Math.min(
        root.sideBySide ? root.width - root.durationsWidth - root.padding * 3 : root.width - root.padding * 2,
        root.height - ClockStyle.chipHeight - ClockStyle.gapSmall - root.cycleDot - ClockStyle.fabSizeLarge - ClockStyle.gapLarge * 4 - root.padding * 2))
    readonly property real ringThickness: Math.max(ClockStyle.gapSmall, root.ringSize * 0.04)
    readonly property real digitSize: root.ringSize * 0.24
    readonly property real cycleDot: ClockStyle.gapHuge

    readonly property bool running: TimerService.pomodoroRunning
    readonly property bool onBreak: TimerService.pomodoroBreak
    readonly property bool longBreak: TimerService.pomodoroLongBreak
    readonly property int cycle: TimerService.pomodoroCycle
    readonly property int cycles: Math.max(1, TimerService.cyclesBeforeLongBreak)
    readonly property color colPhase: root.onBreak ? ClockStyle.colBreak : ClockStyle.colFocus
    readonly property color colPhaseContainer: root.onBreak ? ClockStyle.colTertiaryContainer : ClockStyle.colPrimaryContainer
    readonly property color colOnPhaseContainer: root.onBreak ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnPrimaryContainer
    readonly property string phaseLabel: root.longBreak ? Translation.tr("Long break")
        : root.onBreak ? Translation.tr("Short break") : Translation.tr("Focus")
    readonly property string phaseIcon: root.longBreak ? "self_improvement" : root.onBreak ? "coffee" : "psychiatry"

    readonly property string pageSubtitle: Translation.tr("Cycle %1 of %2").arg(String(root.cycle + 1)).arg(String(root.cycles))

    function setMinutes(key: string, minutes: int): void {
        Config.options.time.pomodoro[key] = Math.max(1, minutes) * 60;
        if (!root.running)
            TimerService.pomodoroSecondsLeft = TimerService.pomodoroLapDuration;
    }

    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space) {
            TimerService.togglePomodoro();
            event.accepted = true;
        } else if (event.key === Qt.Key_N) {
            TimerService.skipPomodoroPhase();
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            TimerService.resetPomodoro();
            event.accepted = true;
        }
    }

    component PhaseTimer: ColumnLayout {
        spacing: ClockStyle.gapLarge

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: phaseRow.implicitWidth + ClockStyle.gapHuge * 2
            implicitHeight: ClockStyle.chipHeight + ClockStyle.gapSmall
            radius: height / 2
            color: root.colPhaseContainer

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }

            RowLayout {
                id: phaseRow
                anchors.centerIn: parent
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: root.phaseIcon
                    iconSize: ClockStyle.iconNormal
                    fill: 1
                    color: root.colOnPhaseContainer
                }

                StyledText {
                    text: root.phaseLabel
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                    color: root.colOnPhaseContainer
                    animateChange: !ClockStyle.reducedMotion
                }
            }
        }

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.ringSize
            implicitHeight: root.ringSize

            ClockProgressRing {
                anchors.fill: parent
                value: 1 - TimerService.pomodoroProgress
                thickness: root.ringThickness
                wavy: root.running
                colIndicator: root.colPhase
                colTrack: root.colPhaseContainer
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: ClockFormat.duration(TimerService.pomodoroSecondsLeft)
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: root.digitSize
                    color: ClockStyle.colOnBackground
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.running ? Translation.tr("of %1").arg(ClockFormat.shortDuration(TimerService.pomodoroLapDuration)) : Translation.tr("Paused")
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colSubtext
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: ClockStyle.gapSmall

            Repeater {
                model: root.cycles

                MaterialShape {
                    id: cycleShape
                    required property int index
                    readonly property bool done: cycleShape.index < root.cycle || (cycleShape.index === root.cycle && root.onBreak)
                    readonly property bool current: cycleShape.index === root.cycle
                    implicitSize: root.cycleDot
                    shapeString: cycleShape.done ? "Cookie4Sided" : "Circle"
                    color: cycleShape.done ? root.colPhase : cycleShape.current ? root.colPhaseContainer : ClockStyle.colSurfaceHighest
                    scale: cycleShape.current ? 1 : 0.72

                    Behavior on scale {
                        animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: ClockStyle.gapSmall
            spacing: ClockStyle.gapLarge

            ClockIconButton {
                symbol: "restart_alt"
                tooltip: Translation.tr("Reset")
                size: ClockStyle.fabSize
                iconSize: ClockStyle.iconLarge
                colBackground: ClockStyle.colSurfaceHighest
                onClicked: TimerService.resetPomodoro()
            }

            ClockPlayButton {
                running: root.running
                colIdle: root.colPhase
                colRunning: root.colPhaseContainer
                colOnRunning: root.colOnPhaseContainer
                onClicked: TimerService.togglePomodoro()
            }

            ClockIconButton {
                symbol: "skip_next"
                tooltip: Translation.tr("Skip to next phase")
                size: ClockStyle.fabSize
                iconSize: ClockStyle.iconLarge
                colBackground: ClockStyle.colSurfaceHighest
                onClicked: TimerService.skipPomodoroPhase()
            }
        }
    }

    component Durations: ColumnLayout {
        spacing: 2

        ClockSettingsRow {
            first: true
            symbol: "psychiatry"
            title: Translation.tr("Focus")
            ClockStepper {
                value: Math.round(TimerService.focusTime / 60)
                from: 1
                to: 180
                format: value => ClockFormat.shortDuration(value * 60)
                onMoved: value => root.setMinutes("focus", value)
            }
        }
        ClockSettingsRow {
            symbol: "coffee"
            title: Translation.tr("Short break")
            ClockStepper {
                value: Math.round(TimerService.breakTime / 60)
                from: 1
                to: 60
                format: value => ClockFormat.shortDuration(value * 60)
                onMoved: value => root.setMinutes("breakTime", value)
            }
        }
        ClockSettingsRow {
            symbol: "self_improvement"
            title: Translation.tr("Long break")
            ClockStepper {
                value: Math.round(TimerService.longBreakTime / 60)
                from: 1
                to: 120
                format: value => ClockFormat.shortDuration(value * 60)
                onMoved: value => root.setMinutes("longBreak", value)
            }
        }
        ClockSettingsRow {
            last: true
            symbol: "repeat"
            title: Translation.tr("Cycles before a long break")
            ClockStepper {
                value: root.cycles
                from: 1
                to: 12
                onMoved: value => Config.options.time.pomodoro.cyclesBeforeLongBreak = value
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.sideBySide
        sourceComponent: RowLayout {
            spacing: ClockStyle.gapHuge

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                PhaseTimer {
                    anchors.centerIn: parent
                }
            }

            Durations {
                Layout.fillWidth: false
                Layout.preferredWidth: root.durationsWidth
                Layout.maximumWidth: root.durationsWidth
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: root.padding
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: !root.sideBySide
        sourceComponent: StyledFlickable {
            id: stackFlick
            contentWidth: width
            contentHeight: stack.implicitHeight + ClockStyle.gapHuge * 2
            clip: true

            ColumnLayout {
                id: stack
                x: root.padding
                y: ClockStyle.gapLarge
                width: stackFlick.width - root.padding * 2
                spacing: ClockStyle.gapHuge

                PhaseTimer {
                    Layout.alignment: Qt.AlignHCenter
                }

                Durations {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
