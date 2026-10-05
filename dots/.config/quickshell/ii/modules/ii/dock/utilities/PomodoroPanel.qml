import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * The pomodoro panel: the phase on a big wavy ring, reset / play / skip, the
 * set as segments (the current one fills with the phase), today's count, and
 * the durations as timetable-style rows.
 */
ColumnLayout {
    id: panel

    property var host: null

    readonly property bool running: TimerService.pomodoroRunning
    readonly property bool isBreak: TimerService.pomodoroBreak
    readonly property bool isLongBreak: TimerService.pomodoroLongBreak
    readonly property int secondsLeft: Math.max(0, TimerService.pomodoroSecondsLeft)
    readonly property int lapDuration: Math.max(1, TimerService.pomodoroLapDuration)
    readonly property int cycles: Math.max(1, TimerService.cyclesBeforeLongBreak)
    readonly property int cycle: TimerService.pomodoroCycle
    readonly property color accent: panel.isBreak ? ClockStyle.colTertiary : ClockStyle.colPrimary
    readonly property color accentContainer: panel.isBreak ? ClockStyle.colTertiaryContainer : ClockStyle.colPrimaryContainer
    readonly property color onAccentContainer: panel.isBreak ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnPrimaryContainer

    spacing: 8

    // The phase on a large wavy ring: time on top, the phase chip under it.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 232
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField

        ClockProgressRing {
            anchors.centerIn: parent
            width: 204
            height: 204
            value: panel.secondsLeft / panel.lapDuration
            thickness: 10
            waves: 18
            maxAmplitude: 2.5
            wavy: panel.running
            tickDuration: 1000
            colIndicator: panel.accent
            colTrack: ColorUtils.applyAlpha(panel.accent, 0.18)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: TimerService.formatCountdownDuration(panel.secondsLeft)
                color: ClockStyle.colOnSurface
                font.family: ClockStyle.fontMain
                font.variableAxes: ClockStyle.axesDigitsBold
                font.pixelSize: 54
            }
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: phaseLabel.implicitWidth + 24
                implicitHeight: 28
                radius: 14
                color: panel.accentContainer
                StyledText {
                    id: phaseLabel
                    anchors.centerIn: parent
                    text: panel.isLongBreak ? Translation.tr("Long break") : panel.isBreak ? Translation.tr("Break") : Translation.tr("Focus")
                    color: panel.onAccentContainer
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Bold
                }
            }
        }
    }

    // Segmented set: the current segment widens and fills with progress.
    RowLayout {
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: panel.cycles
            delegate: Rectangle {
                id: segment
                required property int index
                readonly property bool current: segment.index === panel.cycle
                readonly property bool done: segment.index < panel.cycle || (segment.current && panel.isBreak)
                Layout.fillWidth: true
                Layout.preferredWidth: segment.current ? 2 : 1
                implicitHeight: 8
                radius: 4
                color: ColorUtils.applyAlpha(ClockStyle.colPrimary, 0.18)
                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: ClockStyle.colPrimary
                    width: segment.done ? parent.width
                        : segment.current && !panel.isBreak ? parent.width * (1 - panel.secondsLeft / panel.lapDuration) : 0
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        ClockButton {
            Layout.fillWidth: true
            Layout.preferredWidth: 2
            symbol: "restart_alt"
            label: Translation.tr("Reset")
            onClicked: TimerService.resetPomodoro()
        }
        ClockPlayButton {
            size: 56
            running: panel.running
            colRunning: panel.accentContainer
            colOnRunning: panel.onAccentContainer
            onClicked: TimerService.togglePomodoro()
        }
        ClockButton {
            Layout.fillWidth: true
            Layout.preferredWidth: 2
            symbol: "skip_next"
            label: Translation.tr("Skip")
            onClicked: TimerService.skipPomodoroPhase()
        }
    }

    StyledText {
        Layout.leftMargin: 4
        Layout.topMargin: 4
        text: TimerService.pomodoroFocusToday === 1 ? Translation.tr("1 focus session today")
            : Translation.tr("%1 focus sessions today").arg(TimerService.pomodoroFocusToday)
        color: ClockStyle.colOnSurfaceVariant
        font.pixelSize: ClockStyle.textSmall
        font.weight: Font.DemiBold
    }

    // ── Durations ───────────────────────────────────────────────────────
    Repeater {
        model: [
            { key: "focus", label: Translation.tr("Focus"), symbol: "target", seconds: true, from: 5, to: 120, step: 5 },
            { key: "breakTime", label: Translation.tr("Break"), symbol: "coffee", seconds: true, from: 1, to: 60, step: 1 },
            { key: "longBreak", label: Translation.tr("Long break"), symbol: "self_improvement", seconds: true, from: 5, to: 90, step: 5 },
            { key: "cyclesBeforeLongBreak", label: Translation.tr("Sessions per set"), symbol: "repeat", seconds: false, from: 2, to: 8, step: 1 }
        ]
        delegate: Rectangle {
            id: durationRow
            required property var modelData
            required property int index
            readonly property int stored: Config.options.time.pomodoro[durationRow.modelData.key] ?? 0
            readonly property int shown: durationRow.modelData.seconds ? Math.round(durationRow.stored / 60) : durationRow.stored
            Layout.fillWidth: true
            implicitHeight: 52
            radius: durationRow.index === 0 ? ClockStyle.radiusNormal : ClockStyle.radiusSmall
            color: ClockStyle.colField

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 10
                MaterialShapeWrappedMaterialSymbol {
                    text: durationRow.modelData.symbol
                    iconSize: 16
                    padding: 7
                    shape: [MaterialShape.Shape.Cookie9Sided, MaterialShape.Shape.Flower, MaterialShape.Shape.Clover4Leaf, MaterialShape.Shape.SoftBurst][durationRow.index]
                    color: ClockStyle.colPrimaryContainer
                    colSymbol: ClockStyle.colOnPrimaryContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    text: durationRow.modelData.label
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                }
                ClockStepper {
                    value: durationRow.shown
                    from: durationRow.modelData.from
                    to: durationRow.modelData.to
                    stepSize: durationRow.modelData.step
                    format: value => durationRow.modelData.seconds ? Translation.tr("%1 min").arg(value) : String(value)
                    onMoved: value => Config.options.time.pomodoro[durationRow.modelData.key] = durationRow.modelData.seconds ? value * 60 : value
                }
            }
        }
    }
}
