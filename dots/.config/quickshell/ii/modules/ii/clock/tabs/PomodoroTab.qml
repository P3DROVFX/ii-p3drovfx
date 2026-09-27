pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Pomodoro: the phase, the time left inside a wavy ring in the phase's colour, the cycle
 * as a row of segments, and reset / start-pause / skip. The durations sit on a pane of
 * their own beside it. The same TimerService pomodoro the sidebar, the bar and the
 * island show.
 *
 * Motion follows the time rather than decorating it: the ring drains over each second,
 * the shape behind the digits turns with the phase's progress (a quarter turn per phase),
 * and the current cycle's segment widens into place instead of popping between shapes.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property bool sideBySide: root.layoutWidth >= ClockStyle.mediumMax - 80
    readonly property real durationsWidth: Math.round(Math.max(300, Math.min(root.layoutWidth * 0.32, 400)))
    readonly property real stageWidth: root.sideBySide ? root.layoutWidth - root.durationsWidth - ClockStyle.paneGap : root.layoutWidth
    readonly property real ringSize: Math.round(Math.max(ClockStyle.worldDialMin, Math.min(root.stageWidth - ClockStyle.gapHuge * 2,
        (root.sideBySide ? root.height : root.height * 0.9) - ClockStyle.chipHeight - ClockStyle.fabSizeLarge - 12 - ClockStyle.gapHuge * 5)))
    readonly property real ringThickness: Math.max(ClockStyle.gapSmall, root.ringSize * 0.038)
    readonly property real digitSize: root.ringSize * 0.23

    readonly property bool running: TimerService.pomodoroRunning
    readonly property bool onBreak: TimerService.pomodoroBreak
    readonly property bool longBreak: TimerService.pomodoroLongBreak
    readonly property int cycle: TimerService.pomodoroCycle
    readonly property int cycles: Math.max(1, TimerService.cyclesBeforeLongBreak)
    readonly property real phaseProgress: TimerService.pomodoroProgress
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

        // ── Phase ───────────────────────────────────────────────────────
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: phaseRow.implicitWidth + ClockStyle.gapHuge * 2
            implicitHeight: ClockStyle.chipHeight + ClockStyle.gapSmall
            radius: height / 2
            color: root.colPhaseContainer

            Behavior on color {
                animation: ClockStyle.motionFast.colorAnimation.createObject(this)
            }
            Behavior on implicitWidth {
                animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
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
                    animateChange: !ClockStyle.reducedMotion
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

        // ── Ring ────────────────────────────────────────────────────────
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.ringSize
            implicitHeight: root.ringSize

            MaterialShape {
                id: phaseShape
                anchors.centerIn: parent
                width: root.ringSize * 0.72
                height: width
                shapeString: root.onBreak ? "SoftBurst" : "Cookie12Sided"
                color: root.colPhaseContainer
                opacity: root.running ? 1 : 0.55
                // Counted across phases, so a new phase keeps turning forward instead of
                // unwinding the quarter the last one made.
                rotation: (root.cycle * 2 + (root.onBreak ? 1 : 0) + root.phaseProgress) * 90

                Behavior on rotation {
                    enabled: !ClockStyle.reducedMotion
                    NumberAnimation {
                        duration: 1000
                        easing.type: Easing.Linear
                    }
                }
                Behavior on opacity {
                    animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                }
            }

            ClockProgressRing {
                anchors.fill: parent
                value: 1 - root.phaseProgress
                thickness: root.ringThickness
                wavy: root.running
                tickDuration: root.running ? 1000 : 0
                colIndicator: root.colPhase
                colTrack: ClockStyle.colField
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
                    color: root.colOnPhaseContainer
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.running ? Translation.tr("of %1").arg(ClockFormat.shortDuration(TimerService.pomodoroLapDuration)) : Translation.tr("Paused")
                    font.pixelSize: ClockStyle.textNormal
                    color: root.colOnPhaseContainer
                    opacity: 0.8
                }
            }
        }

        // ── Cycle ───────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            Repeater {
                model: root.cycles

                Rectangle {
                    id: segment
                    required property int index
                    readonly property bool done: segment.index < root.cycle || (segment.index === root.cycle && root.onBreak)
                    readonly property bool current: segment.index === root.cycle

                    implicitWidth: segment.current ? 44 : 14
                    implicitHeight: 14
                    radius: 7
                    color: segment.done ? root.colPhase : segment.current ? root.colPhaseContainer : ClockStyle.colField

                    Behavior on implicitWidth {
                        animation: ClockStyle.motionSpatial.numberAnimation.createObject(this)
                    }
                    Behavior on color {
                        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                    }

                    // The current segment fills with the phase, so the row itself is a
                    // second progress bar for the whole cycle.
                    Rectangle {
                        visible: segment.current && !root.onBreak
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        width: Math.max(parent.height, parent.width * root.phaseProgress)
                        radius: parent.radius
                        color: root.colPhase

                        Behavior on width {
                            enabled: root.running && !ClockStyle.reducedMotion
                            NumberAnimation {
                                duration: 1000
                                easing.type: Easing.Linear
                            }
                        }
                    }
                }
            }
        }

        // ── Controls ────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: ClockStyle.gapTiny
            spacing: ClockStyle.gapLarge

            ClockIconButton {
                symbol: "restart_alt"
                tooltip: Translation.tr("Reset")
                size: ClockStyle.fabSize
                iconSize: ClockStyle.iconLarge
                colBackground: ClockStyle.colSecondaryContainer
                colIcon: ClockStyle.colOnSecondaryContainer
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
                colBackground: ClockStyle.colSecondaryContainer
                colIcon: ClockStyle.colOnSecondaryContainer
                onClicked: TimerService.skipPomodoroPhase()
            }
        }
    }

    component DurationRow: Rectangle {
        id: row
        property string symbol: ""
        property int shapeKind: MaterialShape.Shape.Cookie7Sided
        property string label: ""
        property bool active: false
        property alias value: stepper.value
        property alias from: stepper.from
        property alias to: stepper.to
        property alias format: stepper.format
        signal moved(int value)

        Layout.fillWidth: true
        implicitHeight: 62
        radius: Appearance.rounding.small
        color: row.active ? ClockStyle.colSecondaryContainer : ClockStyle.colField

        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 10

            MaterialShapeWrappedMaterialSymbol {
                text: row.symbol
                iconSize: 18
                padding: 9
                shape: row.shapeKind
                color: row.active ? root.colPhase : ClockStyle.colPrimaryContainer
                colSymbol: row.active ? (root.onBreak ? ClockStyle.colOnTertiary : ClockStyle.colOnPrimary) : ClockStyle.colOnPrimaryContainer
                rotation: row.active ? 30 : 0
            }

            StyledText {
                Layout.fillWidth: true
                text: row.label
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Bold
                color: row.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
            }

            ClockStepper {
                id: stepper
                onMoved: value => row.moved(value)
            }
        }
    }

    component Durations: Rectangle {
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPane
        implicitHeight: durationsColumn.implicitHeight + 28

        ColumnLayout {
            id: durationsColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 14
            }
            spacing: 10

            StyledText {
                text: Translation.tr("Durations")
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Bold
                color: ClockStyle.colOnSurface
            }

            DurationRow {
                symbol: "psychiatry"
                shapeKind: MaterialShape.Shape.Cookie12Sided
                label: Translation.tr("Focus")
                active: !root.onBreak
                value: Math.round(TimerService.focusTime / 60)
                from: 1
                to: 180
                format: value => ClockFormat.shortDuration(value * 60)
                onMoved: value => root.setMinutes("focus", value)
            }
            DurationRow {
                symbol: "coffee"
                shapeKind: MaterialShape.Shape.SoftBurst
                label: Translation.tr("Short break")
                active: root.onBreak && !root.longBreak
                value: Math.round(TimerService.breakTime / 60)
                from: 1
                to: 60
                format: value => ClockFormat.shortDuration(value * 60)
                onMoved: value => root.setMinutes("breakTime", value)
            }
            DurationRow {
                symbol: "self_improvement"
                shapeKind: MaterialShape.Shape.Flower
                label: Translation.tr("Long break")
                active: root.longBreak
                value: Math.round(TimerService.longBreakTime / 60)
                from: 1
                to: 120
                format: value => ClockFormat.shortDuration(value * 60)
                onMoved: value => root.setMinutes("longBreak", value)
            }
            DurationRow {
                symbol: "repeat"
                shapeKind: MaterialShape.Shape.Cookie4Sided
                label: Translation.tr("Cycles before a long break")
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
            spacing: ClockStyle.paneGap

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: ClockStyle.radiusLarge
                color: ClockStyle.colPane

                PhaseTimer {
                    anchors.centerIn: parent
                }
            }

            ColumnLayout {
                Layout.preferredWidth: root.durationsWidth
                Layout.maximumWidth: root.durationsWidth
                Layout.fillHeight: true
                spacing: ClockStyle.paneGap

                Durations {
                    Layout.fillWidth: true
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: !root.sideBySide
        sourceComponent: StyledFlickable {
            id: stackFlick
            contentWidth: width
            contentHeight: stack.implicitHeight + ClockStyle.gapHuge
            clip: true

            ColumnLayout {
                id: stack
                width: stackFlick.width
                spacing: ClockStyle.paneGap

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: stackTimer.implicitHeight + ClockStyle.gapHuge * 2
                    radius: ClockStyle.radiusLarge
                    color: ClockStyle.colPane

                    PhaseTimer {
                        id: stackTimer
                        anchors.centerIn: parent
                    }
                }

                Durations {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
