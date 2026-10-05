import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Pomodoro. The phase is the colour family — focus primary, breaks tertiary —
 * and the ring drains with it. Square: ring + minutes left, nothing else (at
 * rest, the target on a nine-sided cookie). Wide: ring + control, the time
 * over the phase, the cycles of the set as pips, and skip.
 */
UtilityTile {
    id: tile

    readonly property bool running: TimerService.pomodoroRunning
    readonly property bool isBreak: TimerService.pomodoroBreak
    readonly property bool isLongBreak: TimerService.pomodoroLongBreak
    readonly property int secondsLeft: Math.max(0, TimerService.pomodoroSecondsLeft)
    readonly property int lapDuration: Math.max(1, TimerService.pomodoroLapDuration)
    readonly property bool started: tile.running || tile.secondsLeft < tile.lapDuration
    readonly property int cycles: Math.max(1, TimerService.cyclesBeforeLongBreak)
    readonly property int cycle: TimerService.pomodoroCycle
    readonly property int today: TimerService.pomodoroFocusToday
    readonly property string timeText: TimerService.formatCountdownDuration(tile.secondsLeft)
    readonly property string shortText: tile.secondsLeft >= 600 ? String(Math.ceil(tile.secondsLeft / 60))
        : Math.floor(tile.secondsLeft / 60) + ":" + ClockFormat.pad(tile.secondsLeft % 60)
    readonly property string phaseName: tile.isLongBreak ? Translation.tr("Long break")
        : tile.isBreak ? Translation.tr("Break") : Translation.tr("Focus")

    // The surface stays quiet; the phase colour is carried by the ring and
    // the digits (the timer is the one that fills its container).
    surfaceColor: tile.started && !tile.running ? ClockStyle.colSecondaryContainer : ClockStyle.colSurfaceHigh
    contentColor: tile.started && !tile.running ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
    readonly property color accent: tile.isBreak ? ClockStyle.colTertiary : ClockStyle.colPrimary
    readonly property color onAccent: tile.isBreak ? ClockStyle.colOnTertiary : ClockStyle.colOnPrimary

    tooltipText: tile.started
        ? Translation.tr("%1 · %2 left").arg(tile.phaseName).arg(tile.timeText)
        : Translation.tr("Pomodoro")
    panelSubtitle: Translation.tr("%1 · %2 today").arg(tile.phaseName).arg(tile.today)
    menuActions: [
        { id: "toggle", icon: tile.running ? "pause" : "play_arrow", text: tile.running ? Translation.tr("Pause") : Translation.tr("Start") },
        { id: "skip", icon: "skip_next", text: Translation.tr("Skip phase") },
        { id: "reset", icon: "restart_alt", text: Translation.tr("Reset"), visible: tile.started }
    ]

    function activate() {
        if (tile.wide || !(Config.options?.dock?.utilities?.pomodoro?.clickToggles ?? true))
            return false;
        TimerService.togglePomodoro();
        return true;
    }

    function menuAction(actionId) {
        if (actionId === "toggle")
            TimerService.togglePomodoro();
        else if (actionId === "skip")
            TimerService.skipPomodoroPhase();
        else if (actionId === "reset")
            TimerService.resetPomodoro();
    }

    // ── Square ──────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: !tile.wide

        ClockProgressRing {
            anchors.fill: parent
            anchors.margins: Math.round(tile.side * 0.08)
            visible: tile.started
            value: tile.secondsLeft / tile.lapDuration
            thickness: Math.max(3, Math.round(tile.side * 0.075))
            wavy: tile.running && !Appearance.reducedMotion
            waves: 9
            tickDuration: 1000
            colIndicator: tile.accent
            colTrack: ColorUtils.applyAlpha(tile.contentColor, 0.14)
        }
        TileValue {
            anchors.centerIn: parent
            visible: tile.started
            text: tile.shortText
            color: tile.running ? tile.accent : tile.contentColor
            font.pixelSize: Math.round(tile.side * (tile.shortText.length > 3 ? 0.27 : 0.36))
        }
        TileBadge {
            anchors.centerIn: parent
            visible: !tile.started
            width: Math.round(tile.side * 0.74)
            height: width
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Cookie9Sided
            color: ClockStyle.colPrimaryContainer
            colSymbol: ClockStyle.colOnPrimaryContainer
            text: "target"
            iconScale: 0.52
        }
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        visible: tile.wide
        spacing: tile.pad

        Item {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            ClockProgressRing {
                anchors.fill: parent
                value: tile.secondsLeft / tile.lapDuration
                thickness: Math.max(3, Math.round(tile.badgeSize * 0.09))
                wavy: tile.running && !Appearance.reducedMotion
                waves: 8
                tickDuration: 1000
                colIndicator: tile.accent
                colTrack: ColorUtils.applyAlpha(tile.contentColor, 0.14)
            }
            TileButton {
                anchors.centerIn: parent
                width: Math.round(tile.badgeSize * 0.64)
                height: width
                symbol: tile.running ? "pause" : "play_arrow"
                filled: true
                colFilled: tile.accent
                colOnFilled: tile.onAccent
                active: tile.running
                iconScale: 0.6
                onClicked: TimerService.togglePomodoro()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            TileValue {
                Layout.fillWidth: true
                text: tile.timeText
                color: tile.running ? tile.accent : tile.contentColor
                font.pixelSize: tile.valueSize
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Math.max(4, Math.round(tile.pad * 0.8))
                TileCaption {
                    text: tile.phaseName
                    color: tile.captionColor
                    font.pixelSize: tile.captionSize
                }
                // The set: done, current (wider), still to come.
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Math.max(2, Math.round(tile.captionSize * 0.3))
                    Repeater {
                        model: tile.cycles
                        delegate: Rectangle {
                            required property int index
                            readonly property bool current: index === tile.cycle && !tile.isBreak
                            readonly property bool done: index < tile.cycle || (index === tile.cycle && tile.isBreak)
                            width: current ? Math.round(tile.captionSize * 1.4) : Math.round(tile.captionSize * 0.5)
                            height: Math.round(tile.captionSize * 0.5)
                            radius: height / 2
                            color: done || current ? tile.accent : ColorUtils.applyAlpha(tile.contentColor, 0.25)
                            Behavior on width {
                                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                            }
                        }
                    }
                }
            }
        }

        TileButton {
            implicitWidth: Math.round(tile.badgeSize * 0.84)
            implicitHeight: implicitWidth
            symbol: "skip_next"
            tip: Translation.tr("Skip phase")
            colContent: tile.contentColor
            onClicked: TimerService.skipPomodoroPhase()
        }
    }
}
