pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Timers: the keypad fills the page while there is nothing running; once there is, every
 * timer is a card in a grid and a new one is typed in the side sheet. These are
 * TimerService's countdowns, so timers started from the sidebar, search or the timetable
 * show up here too.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property ClockSidePanel panels: null

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real gridGap: ClockStyle.gap
    property real layoutWidth: root.width
    readonly property real contentWidth: root.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.layoutWidth - ClockStyle.gapTiny * 2
    readonly property int columns: Math.max(1, Math.floor((root.contentLayoutWidth + root.gridGap) / (ClockStyle.timerCardMinWidth + root.gridGap)))
    readonly property real cardWidth: Math.floor((root.contentWidth - root.gridGap * (root.columns - 1)) / root.columns)
    readonly property real cardLayoutWidth: (root.contentLayoutWidth - root.gridGap * (root.columns - 1)) / root.columns

    readonly property var countdowns: Array.from(TimerService.countdowns ?? [])
    readonly property int count: root.countdowns.length
    readonly property int running: root.countdowns.filter(timer => !timer.paused && !timer.notified).length
    readonly property int finishedCount: root.countdowns.filter(timer => timer.notified).length

    // With nothing running the keypad already fills the page; the rail's button returns
    // once there is a grid to add to.
    readonly property bool actionAvailable: root.count > 0
    readonly property string pageSubtitle: root.count === 0 ? ""
        : Translation.tr("%1 running").arg(String(root.running)) + (root.finishedCount > 0 ? " · " + Translation.tr("%1 finished").arg(String(root.finishedCount)) : "")

    function startTimer(seconds: int): void {
        TimerService.addCountdownSeconds(seconds);
        const draft = Persistent.states.timer.countdownDraft;
        draft.hours = Math.floor(seconds / 3600);
        draft.minutes = Math.floor((seconds % 3600) / 60);
        draft.seconds = seconds % 60;
    }

    function primaryAction(): void {
        if (root.count === 0)
            return;
        root.panels?.show(keypadSheet, {});
    }

    Component {
        id: keypadSheet
        TimerKeypadSheet {
            onStartRequested: seconds => root.startTimer(seconds)
        }
    }

    Component {
        id: renameSheet
        ClockTextPromptSheet {
            property string countdownId: ""
            title: Translation.tr("Timer label")
            caption: Translation.tr("Label")
            symbol: "label"
            onSubmitted: text => TimerService.renameCountdown(countdownId, text)
        }
    }

    Loader {
        anchors.fill: parent
        active: root.count === 0
        sourceComponent: StyledFlickable {
            id: keypadFlick
            contentWidth: width
            contentHeight: Math.max(height, keypad.implicitHeight)
            clip: true

            TimerKeypad {
                id: keypad
                width: keypadFlick.width
                height: Math.max(keypadFlick.height, keypad.implicitHeight)
                compact: root.compact
                onStartRequested: seconds => root.startTimer(seconds)
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: root.count > 0
        sourceComponent: StyledFlickable {
            id: listFlick
            contentWidth: width
            contentHeight: listColumn.implicitHeight + ClockStyle.fabClearance
            clip: true

            ColumnLayout {
                id: listColumn
                x: ClockStyle.gapTiny
                y: ClockStyle.gapTiny
                width: root.contentWidth
                spacing: ClockStyle.gap

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.finishedCount > 0
                    spacing: ClockStyle.gapSmall

                    Item {
                        Layout.fillWidth: true
                    }

                    ClockFormChip {
                        symbol: "clear_all"
                        label: Translation.tr("Clear finished")
                        onTriggered: TimerService.clearFinishedCountdowns()
                    }
                }

                Flow {
                    Layout.preferredWidth: Math.max(root.contentWidth, root.contentLayoutWidth)
                    spacing: root.gridGap

                    // Tiles keep their settled size and the flow animates where they land, so a
                    // sheet opening or the rail folding re-deals the tiles instead of
                    // stretching them frame by frame.
                    move: Transition {
                        enabled: !ClockStyle.reducedMotion
                        NumberAnimation {
                            properties: "x,y"
                            duration: ClockStyle.motionDefault.duration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                        }
                    }

                    Repeater {
                        model: root.count

                        TimerCard {
                            id: card
                            required property int index
                            width: Math.floor(root.cardLayoutWidth)
                            Behavior on width {
                                enabled: !ClockStyle.reducedMotion
                                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                            }
                            countdown: root.countdowns[card.index] ?? ({})
                            layoutWidth: root.cardLayoutWidth
                            onRenameRequested: root.panels?.show(renameSheet, {
                                countdownId: String(card.countdown.id ?? ""),
                                initialText: String(card.countdown.label ?? "")
                            })

                            StaggeredEntrance {
                                index: card.index
                                step: ClockStyle.staggerStep
                                active: !ClockStyle.reducedMotion
                            }
                        }
                    }
                }
            }
        }
    }
}
