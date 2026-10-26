pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.usage.limits
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * A Pomodoro phase change or a finished timer, in the intrusive-bedtime card: a scrim
 * on every output and a centred card on the focused one, dismissed by the button or
 * Esc/Enter/Space. No sound. Built only while TimerService.alert is set.
 */
Scope {
    id: root

    readonly property string focusedName: Hyprland.focusedMonitor?.name ?? ""
    readonly property var alert: TimerService.alert
    readonly property string kind: root.alert?.kind ?? "focus"
    readonly property bool isCountdown: root.kind === "countdown"
    readonly property int minutes: root.alert?.minutes ?? 0

    readonly property string symbol: root.kind === "focus" ? "target"
        : root.kind === "break" ? "coffee"
        : root.kind === "longBreak" ? "spa" : "timer"
    readonly property string shape: root.kind === "focus" ? "Cookie9Sided"
        : root.kind === "break" ? "Cookie12Sided"
        : root.kind === "longBreak" ? "Flower" : "Sunny"
    readonly property string title: root.kind === "focus" ? Translation.tr("Time to focus")
        : root.kind === "break" ? Translation.tr("Time for a break")
        : root.kind === "longBreak" ? Translation.tr("Time for a long break")
        : Translation.tr("Time's up")
    readonly property string subtitle: root.kind === "focus"
        ? Translation.tr("Break is over. Focus for the next %1 minutes.").arg(root.minutes)
        : root.kind === "break" ? Translation.tr("Focus session done. Rest for %1 minutes.").arg(root.minutes)
        : root.kind === "longBreak" ? Translation.tr("Cycle complete. Enjoy a long break of %1 minutes.").arg(root.minutes)
        : Translation.tr("%1 has finished.").arg(root.alert?.label ?? Translation.tr("Timer"))

    // Focus keeps the tertiary hero of bedtime, breaks and timers take their own hue.
    readonly property color colHero: root.kind === "break" ? Appearance.colors.colSecondaryContainer
        : root.kind === "focus" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colTertiaryContainer
    readonly property color colOnHero: root.kind === "break" ? Appearance.colors.colOnSecondaryContainer
        : root.kind === "focus" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnTertiaryContainer
    readonly property color colAccent: root.kind === "break" ? Appearance.colors.colSecondary
        : root.kind === "focus" ? Appearance.colors.colPrimary : Appearance.colors.colTertiary
    readonly property color colOnAccent: root.kind === "break" ? Appearance.colors.colOnSecondary
        : root.kind === "focus" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnTertiary

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window

            required property var modelData
            readonly property bool primary: root.focusedName.length > 0
                ? window.modelData.name === root.focusedName : window.modelData === Quickshell.screens[0]
            property bool shown: false

            screen: window.modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:timerAlert"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: window.primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Component.onCompleted: Qt.callLater(() => window.shown = true)

            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.12)
                opacity: window.shown ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // Swallows every click: nothing behind is to be used from here.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onWheel: wheel => wheel.accepted = true
                }
            }

            Rectangle {
                id: card
                visible: window.primary
                anchors.centerIn: parent
                anchors.verticalCenterOffset: window.shown || ClockStyle.reducedMotion ? 0 : ClockStyle.enterOffset
                width: Math.min(560, (window.modelData?.width ?? 1200) - 64)
                implicitHeight: cardColumn.implicitHeight + 24
                radius: Appearance.rounding.verylarge
                color: Appearance.m3colors.m3surfaceContainerHigh
                opacity: window.shown ? 1 : 0
                focus: window.primary

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.verticalCenterOffset {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                        TimerService.dismissAlert();
                    event.accepted = true;
                }

                ColumnLayout {
                    id: cardColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 12

                    // ── Hero ────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: heroColumn.implicitHeight + 48
                        radius: Appearance.rounding.large
                        color: root.colHero
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        ColumnLayout {
                            id: heroColumn
                            anchors.centerIn: parent
                            width: parent.width - 48
                            spacing: 14

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 148
                                implicitHeight: 148

                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: 116
                                    shapeString: root.shape
                                    color: root.colAccent
                                    rotation: window.shown ? 0 : -30
                                    Behavior on rotation {
                                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.symbol
                                    iconSize: 56
                                    fill: 1
                                    color: root.colOnAccent
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.title
                                wrapMode: Text.WordWrap
                                font.family: ClockStyle.fontTitle
                                font.variableAxes: ClockStyle.axesTitle
                                font.pixelSize: 34
                                color: root.colOnHero
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: root.subtitle
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: root.colOnHero
                                opacity: 0.9
                            }

                            // The phase's figures in the clock's condensed digits.
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                visible: !root.isCountdown
                                spacing: 10

                                Repeater {
                                    model: [
                                        { value: `${root.minutes}`, label: Translation.tr("minutes") },
                                        { value: `${TimerService.pomodoroCycle + 1}/${TimerService.cyclesBeforeLongBreak}`, label: Translation.tr("cycle") },
                                        { value: `${TimerService.pomodoroFocusToday}`, label: Translation.tr("focus today") }
                                    ]

                                    Rectangle {
                                        id: figure
                                        required property var modelData
                                        implicitWidth: figureColumn.implicitWidth + 28
                                        implicitHeight: figureColumn.implicitHeight + 16
                                        radius: Appearance.rounding.normal
                                        color: ColorUtils.applyAlpha(root.colOnHero, 0.1)

                                        ColumnLayout {
                                            id: figureColumn
                                            anchors.centerIn: parent
                                            spacing: 0

                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: figure.modelData.value
                                                font.family: ClockStyle.fontMain
                                                font.variableAxes: ClockStyle.axesDigitsBold
                                                font.pixelSize: 24
                                                color: root.colOnHero
                                            }
                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: figure.modelData.label
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: root.colOnHero
                                                opacity: 0.8
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── The way out ─────────────────────────────────────
                    LimitsTintButton {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        height_: 56
                        solid: true
                        colContent: root.colAccent
                        colSolidContent: root.colOnAccent
                        symbol: "check"
                        label: Translation.tr("Dismiss")
                        onClicked: TimerService.dismissAlert()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Esc or Enter to dismiss")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
