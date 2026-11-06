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
 * Intrusive bedtime: past the target a scrim takes every output and a centred card on
 * the focused one asks to turn the computer off. It can be snoozed a few times; once
 * the snoozes are spent it counts down to a forced shutdown (BedtimeService owns the
 * countdown, this only shows it). Built only while BedtimeService.intrusiveDue.
 */
Scope {
    id: root

    readonly property string focusedName: Hyprland.focusedMonitor?.name ?? ""

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window

            required property var modelData
            readonly property bool primary: root.focusedName.length > 0
                ? window.modelData.name === root.focusedName : window.modelData === Quickshell.screens[0]
            readonly property bool countingDown: BedtimeService.shutdownAt > 0
            property real nowMs: Date.now()
            readonly property int secondsLeft: window.countingDown
                ? Math.max(0, Math.ceil((BedtimeService.shutdownAt - window.nowMs) / 1000)) : 0
            property bool shown: false
            // Countdown card closed to save work: only a pill stays, input passes through.
            readonly property bool minimized: window.countingDown && BedtimeService.countdownMinimized

            readonly property color colHero: window.countingDown ? Appearance.colors.colErrorContainer : Appearance.colors.colTertiaryContainer
            readonly property color colOnHero: window.countingDown ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnTertiaryContainer
            readonly property color colAccent: window.countingDown ? Appearance.colors.colError : Appearance.colors.colTertiary
            readonly property color colOnAccent: window.countingDown ? Appearance.colors.colOnError : Appearance.colors.colOnTertiary

            screen: window.modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:bedtime"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: window.primary && !window.minimized ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: Region {
                item: !window.minimized ? scrim : window.primary ? pill : null
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Component.onCompleted: Qt.callLater(() => window.shown = true)

            Timer {
                interval: 1000
                repeat: true
                running: window.countingDown
                triggeredOnStart: true
                onTriggered: window.nowMs = Date.now()
            }

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.m3colors.m3scrim, 0.12)
                opacity: window.shown && !window.minimized ? 1 : 0
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
                opacity: window.shown && !window.minimized ? 1 : 0
                enabled: !window.minimized
                focus: window.primary

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.verticalCenterOffset {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                Keys.onPressed: event => event.accepted = true

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
                        color: window.colHero
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        ColumnLayout {
                            id: heroColumn
                            anchors.centerIn: parent
                            width: parent.width - 48
                            spacing: 14

                            // The moon on a scalloped shape; a draining ring once the
                            // shutdown countdown runs.
                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 148
                                implicitHeight: 148

                                ClockProgressRing {
                                    anchors.fill: parent
                                    visible: window.countingDown
                                    value: window.countingDown ? window.secondsLeft / BedtimeService.shutdownGraceSeconds : 0
                                    tickDuration: 1000
                                    thickness: 8
                                    wavy: true
                                    animateWave: true
                                    colIndicator: window.colAccent
                                    colTrack: ColorUtils.applyAlpha(window.colOnHero, 0.14)
                                }

                                MaterialShape {
                                    anchors.centerIn: parent
                                    implicitSize: 116
                                    shapeString: window.countingDown ? "Cookie12Sided" : "Cookie9Sided"
                                    color: window.colAccent
                                    rotation: window.shown ? 0 : -30
                                    Behavior on rotation {
                                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                    }
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: window.countingDown ? "power_settings_new" : "bedtime"
                                    iconSize: 56
                                    fill: 1
                                    color: window.colOnAccent
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: window.countingDown ? Translation.tr("Shutting down in %1 s").arg(window.secondsLeft)
                                    : Translation.tr("Time to sleep")
                                wrapMode: Text.WordWrap
                                font.family: ClockStyle.fontTitle
                                font.variableAxes: ClockStyle.axesTitle
                                font.pixelSize: 34
                                color: window.colOnHero
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: window.countingDown
                                    ? Translation.tr("No snoozes left tonight. Save your work and close your apps — the computer will be turned off.")
                                    : Translation.tr("You planned to stop at %1. Save your work and turn the computer off.")
                                        .arg(Qt.formatTime(BedtimeService.tonightTarget, "HH:mm"))
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: window.colOnHero
                                opacity: 0.9
                            }

                            // Tonight's figures in the clock's condensed digits.
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 10

                                Repeater {
                                    model: [
                                        { value: Qt.formatTime(BedtimeService.tonightTarget, "HH:mm"), label: Translation.tr("bedtime") },
                                        { value: BedtimeService.formatLate(BedtimeService.minutesLate), label: Translation.tr("late") },
                                        { value: `${BedtimeService.snoozesLeft}/${BedtimeService.maxSnoozes}`, label: Translation.tr("snoozes left") }
                                    ]

                                    Rectangle {
                                        id: figure
                                        required property var modelData
                                        implicitWidth: figureColumn.implicitWidth + 28
                                        implicitHeight: figureColumn.implicitHeight + 16
                                        radius: Appearance.rounding.normal
                                        color: ColorUtils.applyAlpha(window.colOnHero, 0.1)

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
                                                color: window.colOnHero
                                            }
                                            StyledText {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: figure.modelData.label
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: window.colOnHero
                                                opacity: 0.8
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── The way out ─────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 8

                        LimitsTintButton {
                            Layout.fillWidth: true
                            height_: 56
                            solid: true
                            colContent: window.colAccent
                            colSolidContent: window.colOnAccent
                            symbol: "power_settings_new"
                            label: Translation.tr("Shut down now")
                            onClicked: BedtimeService.shutdownNow()
                        }

                        LimitsTintButton {
                            visible: window.countingDown
                            Layout.fillWidth: true
                            height_: 52
                            colContent: Appearance.colors.colOnSurface
                            symbol: "close"
                            label: Translation.tr("Close to save my work")
                            onClicked: BedtimeService.countdownMinimized = true
                        }

                        LimitsTintButton {
                            visible: !window.countingDown && BedtimeService.snoozesLeft > 0
                            Layout.fillWidth: true
                            height_: 52
                            colContent: Appearance.colors.colOnSurface
                            symbol: "snooze"
                            label: BedtimeService.snoozesLeft === 1
                                ? Translation.tr("Snooze %1 min · last one").arg(BedtimeService.snoozeMinutes)
                                : Translation.tr("Snooze %1 min · %2 left").arg(BedtimeService.snoozeMinutes).arg(BedtimeService.snoozesLeft)
                            onClicked: BedtimeService.snooze()
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Intrusive bedtime · change it in Clock › Bedtime")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // ── Minimized countdown ─────────────────────────────────
            Rectangle {
                id: pill
                visible: window.primary && opacity > 0
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: window.minimized || ClockStyle.reducedMotion ? 12 : -implicitHeight
                implicitWidth: pillRow.implicitWidth + 16
                implicitHeight: pillRow.implicitHeight + 12
                radius: height / 2
                color: Appearance.colors.colErrorContainer
                opacity: window.minimized ? 1 : 0
                enabled: window.minimized

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on anchors.topMargin {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 8

                    MaterialSymbol {
                        Layout.leftMargin: 6
                        text: "power_settings_new"
                        iconSize: 22
                        fill: 1
                        color: Appearance.colors.colOnErrorContainer
                    }

                    StyledText {
                        text: Translation.tr("Shutting down in %1 s").arg(window.secondsLeft)
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnErrorContainer
                    }

                    LimitsTintButton {
                        height_: 40
                        solid: true
                        colContent: Appearance.colors.colError
                        colSolidContent: Appearance.colors.colOnError
                        symbol: "power_settings_new"
                        label: Translation.tr("Shut down now")
                        onClicked: BedtimeService.shutdownNow()
                    }

                    LimitsTintButton {
                        height_: 40
                        colContent: Appearance.colors.colOnErrorContainer
                        symbol: "open_in_full"
                        label: Translation.tr("Show")
                        onClicked: BedtimeService.countdownMinimized = false
                    }
                }
            }
        }
    }
}
