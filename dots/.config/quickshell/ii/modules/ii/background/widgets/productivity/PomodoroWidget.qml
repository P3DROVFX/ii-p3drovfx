pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components
import qs.modules.ii.background.widgets

/*
 * Pomodoro (1x1), after the Clock app's tab: the wavy ring drains in the
 * phase's colour around the whole card, the phase's shape turns behind the
 * digits a quarter per phase (counted across phases, never unwinding), the
 * cycle shows as dots, and the keys sit inside the ring's foot.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "timer_pomodoro"
    designWidth: 240
    designHeight: 240

    readonly property real ringInset: 8
    readonly property real ringThickness: 8
    readonly property real digitSize: 60
    readonly property real playWidth: 52
    readonly property real sideKey: 36
    readonly property real keyHeight: 36

    readonly property bool running: TimerService.pomodoroRunning
    readonly property bool onBreak: TimerService.pomodoroBreak
    readonly property bool longBreak: TimerService.pomodoroLongBreak
    readonly property real progress: TimerService.pomodoroProgress
    readonly property int cycle: TimerService.pomodoroCycle
    readonly property int cycles: Math.max(1, TimerService.cyclesBeforeLongBreak)
    readonly property int secondsLeft: Math.max(0, TimerService.pomodoroSecondsLeft)
    readonly property bool wavy: root.options?.wavyRing ?? true

    readonly property color phaseColor: root.longBreak ? WidgetColorScheme.successColor
        : root.onBreak ? WidgetColorScheme.highlightCircleColor : WidgetColorScheme.accentColor
    readonly property color onPhaseColor: root.longBreak || root.onBreak ? WidgetColorScheme.highlightTextColor : WidgetColorScheme.onAccentColor
    readonly property string phaseLabel: root.longBreak ? Translation.tr("Long break")
        : root.onBreak ? Translation.tr("Break") : Translation.tr("Focus")
    readonly property string phaseIcon: root.longBreak ? "self_improvement" : root.onBreak ? "coffee" : "psychiatry"

    readonly property string timeText: {
        const minutes = Math.floor(root.secondsLeft / 60);
        const seconds = root.secondsLeft % 60;
        return String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0");
    }

    // ── The phase's shape, turning with the phase ──
    MaterialShape {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -8
        implicitSize: 150
        shape: root.longBreak ? MaterialShape.Shape.Flower
            : root.onBreak ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie12Sided
        color: ColorUtils.applyAlpha(root.phaseColor, 0.16)
        rotation: (root.cycle * 2 + (root.onBreak ? 1 : 0) + root.progress) * 90

        Behavior on rotation {
            enabled: !Appearance.reducedMotion
            NumberAnimation {
                duration: 1000
                easing.type: Easing.Linear
            }
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    ClockProgressRing {
        anchors.fill: parent
        anchors.margins: root.ringInset
        value: 1 - root.progress
        thickness: root.ringThickness
        wavy: root.wavy
        waves: 16
        tickDuration: root.running ? 1000 : 0
        colIndicator: root.phaseColor
        colTrack: WidgetColorScheme.pillBgColor
    }

    // ── Phase ──
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 44
        width: phaseRow.implicitWidth + 20
        height: 26
        radius: root.pill(height)
        color: root.phaseColor

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        Row {
            id: phaseRow
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phaseIcon
                iconSize: 16
                fill: 1
                color: root.onPhaseColor
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.phaseLabel
                color: root.onPhaseColor
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
            }
        }
    }

    // ── Time ──
    Text {
        id: digits
        anchors.horizontalCenter: parent.horizontalCenter
        y: 72
        text: root.timeText
        color: WidgetColorScheme.textColorOnBg
        font.family: Appearance.font.family.main
        font.pixelSize: root.digitSize
        // Bolder while it runs, lighter while it waits.
        font.variableAxes: ({ "wght": root.running ? 760 : 520, "wdth": 40, "ROND": 100, "opsz": 144 })
        renderType: Text.QtRendering
    }

    // ── Cycle ──
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 144
        spacing: 4

        Repeater {
            model: root.cycles

            delegate: Rectangle {
                id: dot
                required property int index
                readonly property bool current: dot.index === root.cycle
                readonly property bool past: dot.index < root.cycle
                width: dot.current ? 18 : 6
                height: 6
                radius: root.pill(height)
                color: dot.current || dot.past ? root.phaseColor : WidgetColorScheme.pillBgColor

                Behavior on width {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }
            }
        }
    }

    // ── Keys ──
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 160
        spacing: 6

        WidgetButton {
            width: root.sideKey
            height: root.keyHeight
            symbol: "restart_alt"
            symbolSize: 18
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: TimerService.resetPomodoro()
        }

        WidgetButton {
            width: root.playWidth
            height: root.keyHeight
            symbol: root.running ? "pause" : "play_arrow"
            symbolSize: 22
            colFill: root.phaseColor
            colContent: root.onPhaseColor
            // Circle while it waits, rounded square while it runs.
            restRadius: root.running ? Appearance.rounding.small : root.pill(height)
            onClicked: TimerService.togglePomodoro()
        }

        WidgetButton {
            width: root.sideKey
            height: root.keyHeight
            symbol: "skip_next"
            symbolSize: 18
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: TimerService.skipPomodoroPhase()
        }
    }
}
