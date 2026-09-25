pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Timers: the keypad when there is nothing running (or when adding one), otherwise every
 * timer as a card. These are TimerService's countdowns, so timers started from the
 * sidebar, search or the timetable show up here too.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false

    // ── Tokens ──────────────────────────────────────────────────────────
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide
    readonly property real gridGap: ClockStyle.gap
    readonly property int columns: Math.max(1, Math.floor((root.width - root.padding * 2 + root.gridGap) / (ClockStyle.timerCardMinWidth + root.gridGap)))

    readonly property var countdowns: Array.from(TimerService.countdowns ?? [])
    readonly property int count: root.countdowns.length
    readonly property int running: root.countdowns.filter(timer => !timer.paused && !timer.notified).length
    readonly property int finishedCount: root.countdowns.filter(timer => timer.notified).length
    property bool adding: false
    readonly property bool showKeypad: root.adding || root.count === 0

    readonly property string pageSubtitle: root.count === 0 ? ""
        : Translation.tr("%1 running").arg(String(root.running)) + (root.finishedCount > 0 ? " · " + Translation.tr("%1 finished").arg(String(root.finishedCount)) : "")

    property string renameId: ""

    function startTimer(seconds: int): void {
        TimerService.addCountdownSeconds(seconds);
        const draft = Persistent.states.timer.countdownDraft;
        draft.hours = Math.floor(seconds / 3600);
        draft.minutes = Math.floor((seconds % 3600) / 60);
        draft.seconds = seconds % 60;
        root.adding = false;
    }

    Loader {
        id: keypadLoader
        anchors.fill: parent
        active: root.showKeypad
        opacity: active ? 1 : 0
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
                canCancel: root.count > 0
                onStartRequested: seconds => root.startTimer(seconds)
                onCancelRequested: root.adding = false
            }
        }

        Behavior on opacity {
            animation: ClockStyle.motionFast.numberAnimation.createObject(this)
        }
    }

    Loader {
        anchors.fill: parent
        active: !root.showKeypad
        sourceComponent: StyledFlickable {
            id: listFlick
            contentWidth: width
            contentHeight: grid.implicitHeight + ClockStyle.gapSmall + ClockStyle.fabSize + ClockStyle.gapHuge * 3
            clip: true

            GridLayout {
                id: grid
                x: root.padding
                y: ClockStyle.gapSmall
                width: listFlick.width - root.padding * 2
                columns: root.columns
                rowSpacing: root.gridGap
                columnSpacing: root.gridGap

                Repeater {
                    model: root.count

                    TimerCard {
                        id: card
                        required property int index
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: ClockStyle.timerCardMinWidth
                        countdown: root.countdowns[card.index] ?? ({})
                        onRenameRequested: {
                            root.renameId = String(card.countdown.id ?? "");
                            renameLoader.active = true;
                            renameLoader.item.openWith(String(card.countdown.label ?? ""));
                        }

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

    RowLayout {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: ClockStyle.gapHuge
        }
        visible: !root.showKeypad
        spacing: ClockStyle.gap

        ClockButton {
            visible: root.finishedCount > 0
            variant: "tonal"
            symbol: "clear_all"
            label: Translation.tr("Clear finished")
            onClicked: TimerService.clearFinishedCountdowns()
        }

        ClockFab {
            symbol: "add"
            label: root.wide ? Translation.tr("Add timer") : ""
            onClicked: root.adding = true
        }
    }

    Loader {
        id: renameLoader
        anchors.fill: parent
        active: false
        sourceComponent: ClockTextPromptSheet {
            title: Translation.tr("Timer label")
            placeholder: Translation.tr("Label")
            onSubmitted: text => TimerService.renameCountdown(root.renameId, text)
            onFullyClosed: renameLoader.active = false
        }
    }
}
