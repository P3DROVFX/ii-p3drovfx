pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar.widgets.media
import qs.modules.ii.bar.widgets.indicators
import qs.modules.ii.bar.widgets.timer
import qs.modules.ii.modes

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
 *   update      the update glyph, with how many commits behind in the corner
 *   privacy     one glyph per sensor held, in the phones' colours
 *   discordVoice  whoever is talking (else yourself) in a ring that lights while
 *               anyone talks and turns red while you are muted, with the headcount
 *   phoneLink   the phone's camera and/or microphone glyph while they stream here
 *   systemTray  the tray's own chevron, the count of programs in a badge
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
    /**
     * How much of the glance the pill currently uncovers, from its inner end. Parts
     * beyond it are masked away by the bubble; this lets them also fade in as they
     * are reached rather than pop in at the edge.
     */
    property real revealedWidth: root.width
    /**
     * Hosted inside the island itself (its resting face): no pill growth for media -
     * no title, no play button - and no pill padding at the ends of the others.
     */
    property bool glanceOnly: false

    /** How wide this glance wants the bubble to be. */
    readonly property real preferredWidth: glance.item ? glance.item.preferredWidth : root.diameter

    height: root.diameter

    /** Padding at a pill's ends: enough to clear the rounded caps. */
    // Inside the island a glance sits between its neighbours, which give it air.
    readonly property real endPadding: root.glanceOnly ? 0 : Math.round(root.diameter * 0.32)
    readonly property color colText: Appearance.colors.colOnLayer0

    /**
     * A count in the bubble's lower right.
     *
     * The glance is a square and the bubble a circle cut out of it, so a badge anchored
     * to the square's corner sat in the part the circle removes and lost half its
     * number. This one is placed on the circle instead: its outer end cap rests just
     * inside the rim on the diagonal, and a wider count grows inwards from there.
     */
    component CountBadge: Rectangle {
        id: badge
        required property real diameter
        property string label: ""

        readonly property real reach: Math.max(0, badge.diameter / 2 - badge.height / 2 - 1) / Math.SQRT2

        x: badge.diameter / 2 + badge.reach + badge.height / 2 - badge.width
        y: badge.diameter / 2 + badge.reach - badge.height / 2
        width: Math.max(badge.height, badgeText.implicitWidth + 6)
        height: 14
        radius: badge.height / 2
        color: Appearance.colors.colPrimary

        StyledText {
            id: badgeText
            anchors.centerIn: parent
            text: badge.label
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.Bold
            color: Appearance.colors.colOnPrimary
        }
    }

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
            case "mode": return modeGlance;
            case "update": return updateGlance;
            case "privacy": return privacyGlance;
            case "discordVoice": return discordGlance;
            case "phoneMirror": return phoneMirrorGlance;
            case "phoneLink": return phoneLinkGlance;
            case "systemTray": return systemTrayGlance;
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
                if (root.glanceOnly)
                    return root.diameter;
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
                opacity: media.showTitle && !media.paused && !root.glanceOnly ? 1 : 0
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
                enabled: root.interactive && media.paused && !root.glanceOnly
                // Uncovered by the growing pill, and fading in as it is: no pop at the
                // pill's edge on the way out, none on the way back in.
                readonly property real revealed: Math.max(0, Math.min(1,
                    (root.revealedWidth - playButton.x - playButton.width * 0.3) / (playButton.width * 0.7)))
                opacity: media.paused && !root.glanceOnly ? playButton.revealed : 0
                scale: 0.85 + 0.15 * playButton.revealed
                visible: opacity > 0
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: MprisController.activePlayer?.togglePlaying()

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
            // Resting sessions sort last, so the first one resting means they all are.
            readonly property bool resting: (ai.agent?.startedAtEpoch ?? 0) <= 0
                && ai.agent?.requiresAttention !== true

            CustomIcon {
                anchors.centerIn: parent
                // Up and left a touch while the count is there, so it covers less of it.
                anchors.horizontalCenterOffset: ai.agentCount > 1 ? -2 : 0
                anchors.verticalCenterOffset: ai.agentCount > 1 ? -2 : 0
                width: Math.round(root.diameter * 0.5)
                height: width
                source: {
                    let name = ai.agent?.icon || "google-gemini-symbolic.svg";
                    return name.endsWith(".svg") ? name : name + ".svg";
                }
                colorize: true
                color: ai.resting ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colPrimary
            }

            // More than one agent at work: how many, in the corner.
            CountBadge {
                visible: ai.agentCount > 1
                diameter: root.diameter
                label: String(ai.agentCount)
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
                    // The saturated red; plain `colError` is the pale tone meant for text.
                    color: Appearance.colors.colErrorContainer
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

    // ── Modes ────────────────────────────────────────────────────────────────
    Component {
        id: modeGlance

        Item {
            id: modeItem
            readonly property real preferredWidth: root.diameter
            readonly property var mode: Modes.activeMode
            readonly property string colorKey: modeItem.mode?.color ?? ""
            readonly property real shapeSize: Math.max(16, root.diameter - 8)

            MaterialShape {
                id: shape
                anchors.centerIn: parent
                implicitWidth: modeItem.shapeSize
                implicitHeight: modeItem.shapeSize
                shapeString: (modeItem.mode && modeItem.mode.shape) ? modeItem.mode.shape : "Cookie12Sided"
                color: ModeUi.container(modeItem.colorKey)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: modeItem.mode?.icon ?? "tune"
                    iconSize: Math.round(shape.implicitHeight * 0.52)
                    fill: 1
                    color: ModeUi.onContainer(modeItem.colorKey)
                }
            }
        }
    }

    // ── Shell update ─────────────────────────────────────────────────────────
    Component {
        id: updateGlance

        Item {
            id: update
            readonly property real preferredWidth: root.diameter
            // 0 is "unknown" (offline, rate-limited, not a GitHub remote), not "level".
            readonly property int behind: ShellUpdates.commitsBehind

            MaterialSymbol {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: update.behind > 0 ? -2 : 0
                anchors.verticalCenterOffset: update.behind > 0 ? -2 : 0
                text: "deployed_code_update"
                iconSize: Math.round(root.diameter * 0.56)
                color: Appearance.colors.colPrimary
            }

            CountBadge {
                visible: update.behind > 0
                diameter: root.diameter
                label: update.behind > 99 ? "99+" : String(update.behind)
            }
        }
    }

    // ── Privacy ──────────────────────────────────────────────────────────────
    // One glyph per held sensor, in the bar indicator's own colour. A single sensor is
    // a circle like every other bubble; a video call (camera and microphone) widens it.
    Component {
        id: privacyGlance

        Item {
            id: privacy
            readonly property var kinds: Privacy.activeKinds
            readonly property int iconSize: Math.round(root.diameter * 0.5)
            readonly property real preferredWidth: privacy.kinds.length <= 1 ? root.diameter
                : privacyRow.implicitWidth + 2 * Math.max(root.endPadding, Math.round(root.diameter * 0.26))

            Row {
                id: privacyRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: privacy.kinds

                    MaterialSymbol {
                        required property var modelData
                        text: Privacy.iconFor(String(modelData))
                        fill: 1
                        iconSize: privacy.iconSize
                        color: Appearance.colors.colTertiary
                    }
                }
            }
        }
    }

    // ── Discord voice ────────────────────────────────────────────────────────
    // Only loaded while a call is on, which is also the only time DiscordVoice runs.
    Component {
        id: discordGlance

        Item {
            id: discord
            readonly property real preferredWidth: root.diameter

            readonly property var participants: DiscordVoice.participants ?? []
            readonly property bool anyoneSpeaking: discord.participants.some(user => user?.speaking === true)
            readonly property bool muted: DiscordVoice.muted || DiscordVoice.deafened
            readonly property var speaker: {
                const talking = discord.participants.find(user => user?.speaking === true);
                if (talking)
                    return talking;
                const selfId = String(DiscordVoice.currentUser?.id ?? "");
                return discord.participants.find(user => String(user?.id ?? "") === selfId)
                    ?? discord.participants[0] ?? null;
            }
            readonly property real ringWidth: Math.max(2, Math.round(root.diameter * 0.07))
            readonly property real avatarSize: root.diameter - 2 * (discord.ringWidth + 1)

            Rectangle {
                anchors.centerIn: parent
                width: root.diameter
                height: root.diameter
                radius: width / 2
                color: "transparent"
                border.width: discord.ringWidth
                border.color: discord.muted ? Appearance.colors.colError
                    : (discord.anyoneSpeaking ? Appearance.colors.colPrimary : "transparent")
            }

            Rectangle {
                anchors.centerIn: parent
                width: discord.avatarSize
                height: discord.avatarSize
                radius: width / 2
                color: "#5865F2"
                visible: speakerImage.status !== Image.Ready

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: discord.muted ? (DiscordVoice.deafened ? "headset_off" : "mic_off") : "headset_mic"
                    fill: 1
                    iconSize: Math.round(parent.width * 0.55)
                    color: "#FFFFFF"
                }
            }

            Image {
                id: speakerImage
                anchors.centerIn: parent
                width: discord.avatarSize
                height: discord.avatarSize
                source: DiscordVoice.avatarUrl(discord.speaker, 64)
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: false
            }

            Rectangle {
                id: speakerMask
                anchors.centerIn: parent
                width: discord.avatarSize
                height: discord.avatarSize
                radius: width / 2
                visible: false
                layer.enabled: speakerImage.status === Image.Ready
            }

            MultiEffect {
                anchors.fill: speakerImage
                source: speakerImage
                visible: speakerImage.status === Image.Ready
                maskEnabled: true
                maskSource: speakerMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            CountBadge {
                diameter: root.diameter
                visible: discord.participants.length > 1
                label: String(discord.participants.length)
            }
        }
    }

    // ── Phone camera & microphone ────────────────────────────────────────────
    // Read from the flags the phone services publish, so the glance never constructs
    // them. One stream is a circle; both widen it, like privacy.
    Component {
        id: phoneLinkGlance

        Item {
            id: phoneLink
            readonly property var streams: [GlobalStates.phoneCameraRunning ? "videocam" : "",
                GlobalStates.phoneMicRunning ? "mic" : ""].filter(glyph => glyph !== "")
            readonly property int iconSize: Math.round(root.diameter * 0.5)
            readonly property real preferredWidth: phoneLink.streams.length <= 1 ? root.diameter
                : phoneLinkRow.implicitWidth + 2 * Math.max(root.endPadding, Math.round(root.diameter * 0.26))

            Row {
                id: phoneLinkRow
                anchors.centerIn: parent
                spacing: 3

                Repeater {
                    model: phoneLink.streams

                    MaterialSymbol {
                        required property var modelData
                        text: String(modelData)
                        fill: 1
                        iconSize: phoneLink.iconSize
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

    // ── Phone screen mirror ──────────────────────────────────────────────────
    Component {
        id: phoneMirrorGlance

        Item {
            id: phoneMirror
            readonly property real preferredWidth: root.diameter

            readonly property string deviceImageSource: BluetoothDeviceImages.sourceForPhone(KdeConnectService.activeDeviceDisplayName)

            Rectangle {
                anchors.centerIn: parent
                width: Math.round(root.diameter * 0.82)
                height: width
                radius: width / 2
                color: Appearance.colors.colPrimaryContainer
                clip: true

                Image {
                    id: glanceDeviceImg
                    anchors.fill: parent
                    anchors.margins: 2
                    source: phoneMirror.deviceImageSource
                    fillMode: Image.PreserveAspectFit
                    visible: phoneMirror.deviceImageSource !== "" && status === Image.Ready
                    smooth: true
                    mipmap: true
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !glanceDeviceImg.visible || phoneMirror.deviceImageSource === ""
                    text: "smartphone"
                    fill: 1
                    iconSize: Math.round(parent.width * 0.6)
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }
    }

    // ── System tray ──────────────────────────────────────────────────────────
    // The chevron the bar's tray overflow button wears — the tray's own mark, not one
    // program's icon — and a badge saying how many programs wait inside the card.
    Component {
        id: systemTrayGlance

        Item {
            id: tray
            readonly property var items: TrayService.pinnedItems.concat(TrayService.unpinnedItems)
            readonly property real preferredWidth: root.diameter

            MaterialSymbol {
                anchors.centerIn: parent
                text: "expand_more"
                fill: 1
                iconSize: Math.round(root.diameter * 0.55)
                color: Appearance.colors.colPrimary
            }

            CountBadge {
                diameter: root.diameter
                visible: tray.items.length > 1
                label: String(tray.items.length)
            }
        }
    }
}

