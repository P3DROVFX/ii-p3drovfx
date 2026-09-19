pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.media
import qs.modules.ii.bar.widgets.indicators
import qs.modules.ii.bar.widgets.timer

/**
 * What an auxiliary bubble shows: a glance at an activity, never the activity itself.
 *
 * Each glance says how wide it wants to be (`preferredWidth`): a circle is the bubble's
 * own diameter, a pill asks for more. The bubble animates to that width and the shape
 * grows away from the island, so a glance only has to lay itself out at the width it
 * is given - it is clipped while the pill is still catching up.
 *
 *   media       the bar's vertical ring (cover in a scalloped rim sweeping with the
 *               track); on a track change it opens into a pill with part of the title,
 *               and while paused into a pill with a play button
 *   workspaces  the active-workspace indicator
 *   ai          the working agent's icon
 *   dictation   the microphone, breathing while it listens
 *   recording   a pill: a still error-coloured dot and the elapsed time, its digits
 *               rolling like the bar's record indicator
 *   timer       a pill: the expressive timer marker and the time left (pomodoro,
 *               countdown, or the stopwatch); paused, it folds to the marker alone
 *
 * Resting on the bubble opens it into its own expanded card; the only thing a glance
 * does itself is media's play button while paused.
 */
Item {
    id: root

    /** The activity on show; "" while the bubble is empty. */
    required property string activityId
    /** The bubble's settled height; circles are this wide. */
    required property real diameter
    /** Buttons on a glance (media's play) answer only while it is the glance on show. */
    property bool interactive: true

    /** How wide this glance wants the bubble to be. */
    readonly property real preferredWidth: glance.item ? glance.item.preferredWidth : root.diameter

    height: root.diameter
    // The pill animates towards `preferredWidth`; until it arrives, nothing may spill.
    clip: true

    /** Padding at a pill's ends: enough to clear the rounded caps. */
    readonly property real endPadding: Math.round(root.diameter * 0.32)
    readonly property color colText: Appearance.colors.colOnLayer0

    Loader {
        id: glance
        anchors.fill: parent
        sourceComponent: {
            switch (root.activityId) {
            case "media": return mediaGlance;
            case "workspaces": return workspaceGlance;
            case "ai": return aiGlance;
            case "dictation": return dictationGlance;
            case "recording": return recordingGlance;
            case "timer": return timerGlance;
            }
            return null;
        }
    }

    // ── Media ────────────────────────────────────────────────────────────────
    Component {
        id: mediaGlance

        Item {
            id: media

            /**
             * A track change is worth a word: for a few seconds the ring opens into a pill
             * with the start of the new title, then closes again. Kept short so the bar
             * beside it is pushed only a little and only briefly.
             */
            property bool showTitle: false
            readonly property real maxWidth: Math.round(root.diameter * 4.6)
            readonly property string title: StringUtils.cleanMusicTitle(MprisController.activePlayer?.trackTitle ?? "")
            /**
             * Paused, the ring opens into a pill with a play button beside it, so
             * resuming is one click away without opening anything.
             */
            readonly property bool paused: MprisController.activePlayer ? !MprisController.activePlayer.isPlaying : false
            readonly property real buttonWidth: Math.round(root.diameter * 1.3)
            readonly property real preferredWidth: {
                if (media.paused)
                    return root.diameter + media.buttonWidth + 4;
                if (media.showTitle && media.title !== "")
                    return Math.min(media.maxWidth, root.diameter + titleMetrics.advanceWidth + root.endPadding);
                return root.diameter;
            }

            // Measured apart from the label: the label is laid out at the width this
            // decides, and measuring the label itself would loop.
            TextMetrics {
                id: titleMetrics
                text: media.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                font.family: Appearance.font.family.main
            }

            Timer {
                id: titleTimer
                interval: 4000
                onTriggered: media.showTitle = false
            }

            Connections {
                target: MprisController
                function onTrackChanged() {
                    media.showTitle = true;
                    titleTimer.restart();
                }
            }

            // The ring always sits in the circle at the pill's inner end.
            Item {
                id: ringSlot
                width: root.diameter
                height: root.diameter

                RingMedia {
                    id: ring
                    anchors.centerIn: parent
                    vertical: true
                    // Outside the bar: must not move the media popup's anchor or open it.
                    previewMode: true
                    // The vertical ring is drawn for a bar column; scale it to the bubble.
                    scale: ring.ringSize > 0 ? (root.diameter - 6) / ring.ringSize : 1
                }
            }

            StyledText {
                id: titleText
                anchors.left: ringSlot.right
                anchors.right: parent.right
                anchors.rightMargin: root.endPadding
                anchors.verticalCenter: parent.verticalCenter
                text: media.title
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: root.colText
                opacity: media.showTitle && !media.paused ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(titleText)
                }
            }

            // Resume: a full-radius button in the island's accent, beside the ring.
            RippleButton {
                id: playButton
                x: root.diameter
                anchors.verticalCenter: parent.verticalCenter
                width: media.buttonWidth
                height: root.diameter - 8
                enabled: root.interactive && media.paused
                opacity: media.paused ? 1 : 0
                visible: opacity > 0
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: MprisController.activePlayer?.togglePlaying()
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(playButton)
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    fill: 1
                    iconSize: Math.round(root.diameter * 0.5)
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // ── Workspaces ───────────────────────────────────────────────────────────
    Component {
        id: workspaceGlance

        Item {
            readonly property real preferredWidth: root.diameter
            readonly property int workspaceId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
            readonly property var numberMap: Config.options.bar.workspaces.numberMap ?? []

            Rectangle {
                anchors.centerIn: parent
                width: root.diameter - 8
                height: width
                radius: width / 2
                color: Appearance.colors.colPrimary

                StyledText {
                    anchors.centerIn: parent
                    text: String(parent.parent.numberMap[parent.parent.workspaceId - 1] || parent.parent.workspaceId)
                    font.pixelSize: Math.max(10, Math.round(parent.height * 0.5))
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.numbers
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // ── AI ───────────────────────────────────────────────────────────────────
    Component {
        id: aiGlance

        Item {
            id: ai
            readonly property real preferredWidth: root.diameter
            readonly property var agent: AiStatusService.primaryAgent
            readonly property int agentCount: AiStatusService.agentCount

            CustomIcon {
                anchors.centerIn: parent
                width: Math.round(root.diameter * 0.5)
                height: width
                source: {
                    let name = ai.agent?.icon || "google-gemini-symbolic.svg";
                    return name.endsWith(".svg") ? name : name + ".svg";
                }
                colorize: true
                color: Appearance.colors.colPrimary
            }

            // More than one agent at work: how many, in the corner.
            Rectangle {
                visible: ai.agentCount > 1
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 2
                width: 14
                height: 14
                radius: 7
                color: Appearance.colors.colPrimary

                StyledText {
                    anchors.centerIn: parent
                    text: String(ai.agentCount)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // ── Dictation ────────────────────────────────────────────────────────────
    Component {
        id: dictationGlance

        Item {
            readonly property real preferredWidth: root.diameter
            readonly property bool transcribing: DictationService.transcribing

            Rectangle {
                anchors.centerIn: parent
                width: root.diameter - 8
                height: width
                radius: width / 2
                color: parent.transcribing ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: parent.parent.transcribing ? "graphic_eq" : "mic"
                    iconSize: Math.round(root.diameter * 0.45)
                    fill: 1
                    color: parent.parent.transcribing ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimaryContainer

                    // The microphone is open: the same breathing the bar's indicator has,
                    // and only while it is.
                    SequentialAnimation on opacity {
                        running: DictationService.recording
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.45; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                    onTextChanged: if (!DictationService.recording) opacity = 1.0
                }
            }
        }
    }

    // ── Recording ────────────────────────────────────────────────────────────
    Component {
        id: recordingGlance

        Item {
            id: recording
            readonly property int seconds: (Persistent.states.screenRecord && Persistent.states.screenRecord.seconds) || 0
            readonly property string timeText: {
                const s = recording.seconds;
                const hours = Math.floor(s / 3600);
                const clock = String(Math.floor((s % 3600) / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
                return hours > 0 ? String(hours) + ":" + clock : clock;
            }
            readonly property real preferredWidth: row.implicitWidth + 2 * root.endPadding

            Row {
                id: row
                anchors.centerIn: parent
                spacing: 7

                // Still on purpose: the digits are what move.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 9
                    radius: 4.5
                    color: Appearance.colors.colError
                }

                RecordTimerText {
                    anchors.verticalCenter: parent.verticalCenter
                    value: recording.timeText
                    pixelSize: Appearance.font.pixelSize.small
                    colText: root.colText
                    animate: !Appearance.reducedMotion
                }
            }
        }
    }

    // ── Timers ───────────────────────────────────────────────────────────────
    Component {
        id: timerGlance

        Item {
            id: timer

            // Pomodoro first, then the countdown that ends soonest, then the stopwatch:
            // the order the bar's timer widget lays its capsules out in, cut to one.
            readonly property string kind: timerState.hasPomodoro ? "pomodoro"
                : (timerState.hasCountdown ? "countdown" : "stopwatch")
            readonly property string value: timer.kind === "pomodoro" ? timerState.pomodoroText
                : (timer.kind === "countdown" ? timerState.countdownText
                    // Whole seconds: centiseconds in a glance are only flicker.
                    : timerState.formatClock(Math.floor(TimerService.stopwatchTime / 100)))
            readonly property bool running: timer.kind === "pomodoro" ? timerState.pomodoroRunning
                : (timer.kind === "countdown" ? !timerState.countdownPaused : timerState.stopwatchRunning)
            readonly property real markerSize: root.diameter - 10
            // Paused, the pill folds to the marker alone: nothing is counting.
            readonly property real preferredWidth: timer.running
                ? (root.diameter - timer.markerSize) / 2 + row.implicitWidth + root.endPadding
                : root.diameter

            TimerBarState {
                id: timerState
            }

            Row {
                id: row
                x: (root.diameter - timer.markerSize) / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                MaterialShapeWrappedMaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    shape: timer.kind === "pomodoro" ? MaterialShape.Shape.Cookie9Sided
                        : (timer.kind === "countdown" ? MaterialShape.Shape.Arch : MaterialShape.Shape.Circle)
                    implicitSize: timer.markerSize
                    iconSize: Appearance.font.pixelSize.normal
                    padding: 3
                    text: {
                        if (!timer.running)
                            return "pause_circle";
                        if (timer.kind === "pomodoro")
                            return "search_activity";
                        return timer.kind === "countdown" ? "hourglass_top" : "timer";
                    }
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                }

                StyledText {
                    id: timerText
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: timer.running ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(timerText)
                    }
                    text: timer.value
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    font.features: ({ "tnum": 1 })
                    color: root.colText
                }
            }
        }
    }
}
