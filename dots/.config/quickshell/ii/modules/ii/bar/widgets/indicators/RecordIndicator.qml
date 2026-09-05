pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.ii.bar.shared
import "../../shared/cards"

/**
 * Screen recording indicator.
 *
 * This file is the **host**: it owns the recorder state, the size the widget
 * reserves in the bar, the pointer and the popup. It draws nothing. The three
 * design families live beside it and receive the state as plain properties:
 *
 *   default     `DefaultRecordIndicator`    — no surface, inside the bar chip
 *   expressive  `ExpressiveRecordIndicator` — capsule / badge / ribbon
 *   neural      `NeuralRecordIndicator`     — orbit / slab / meter
 *
 * Splitting them this way is what makes `minimal` mean one thing in all three:
 * the host decides *what* is on show, each family decides how it looks.
 */
Item {
    id: root

    property bool vertical: false

    // Handed over by BarComponent when the group is highlighted, which is what
    // the default family paints on. See AGENTS.md §5 — inside a filled primary
    // chip, an error colour would be a foreign body.
    property color onActivatedColor: Appearance.colors.colOnPrimary

    // ── State (fully reactive) ───────────────────────────────────────────────
    readonly property bool activelyRecording: (Persistent.states.screenRecord && Persistent.states.screenRecord.active) || false
    readonly property bool isLoading: (Persistent.states.screenRecord && Persistent.states.screenRecord.loading) || false
    readonly property bool isPaused: (Persistent.states.screenRecord && Persistent.states.screenRecord.paused) || false
    readonly property int elapsedSeconds: (Persistent.states.screenRecord && Persistent.states.screenRecord.seconds) || 0

    readonly property bool live: (root.activelyRecording && !root.isPaused) || root.isLoading

    // Read by BarComponent as a *binding* (`itemLoader.item?.activated`), which
    // is the whole point: the bar chip lights up while the capture runs, and the
    // default family paints `onActivatedColor` on it. This used to be pushed
    // over with `toggleHighlight()` from the change handlers, and it was always
    // one state behind — a handler for `isPaused` runs before `live` (a binding
    // that depends on it) has been re-evaluated, so the chip got the *previous*
    // answer: dark content on a lit chip, or lit content on a dark one. There is
    // no hover in this value, so it is not the case AGENTS.md §12 warns about.
    readonly property bool activated: root.live

    // Whether the widget has anything to say at all. Its own change handler is
    // the only safe place to report it, for the same reason.
    readonly property bool hasContent: root.activelyRecording || root.isLoading

    // ── Configuration ────────────────────────────────────────────────────────
    readonly property string style: Config.options.bar.styles.recordIndicator ?? "expressive"
    readonly property bool minimal: Config.options.bar.indicators.record.minimal ?? false
    readonly property bool showLabel: Config.options.bar.indicators.record.showLabel ?? true
    readonly property bool animateDigits: (Config.options.bar.indicators.record.animateDigits ?? true) && !Appearance.reducedMotion

    // ── Presentation of the state ────────────────────────────────────────────
    readonly property string stateIcon: {
        if (root.isLoading)
            return "progress_activity";
        if (root.showHoverState)
            return "stop";
        if (root.isPaused)
            return "pause";
        return "videocam";
    }
    readonly property string stateLabel: {
        if (root.showHoverState)
            return Translation.tr("STOP");
        if (root.isPaused)
            return Translation.tr("PAUSED");
        return Translation.tr("REC");
    }
    // The vertical bar is 36px of usable width. "PAUSED" does not fit there and
    // truncating it would be worse than saying it shorter.
    readonly property string stateLabelShort: {
        if (root.showHoverState)
            return Translation.tr("STOP");
        if (root.isPaused)
            return Translation.tr("PAUSE");
        return Translation.tr("REC");
    }
    readonly property string timeText: root.formatTime(root.elapsedSeconds)
    // Where the capture stands in the current minute. The Neural family draws
    // this; it is the one thing the digits cannot say on their own.
    readonly property real minuteProgress: root.isLoading ? 0 : (root.elapsedSeconds % 60) / 60

    // ── Pointer ──────────────────────────────────────────────────────────────
    // With click-to-show popups the popup opens off containsMouse turning true
    // on press, so hover must stay off — otherwise the popup shows on hover like
    // every other mode. containsMouse still flips on press with hover off, so
    // keep the stop-morph out of that mode too.
    readonly property bool clickToShowPopup: BarInteraction.clickToShow
    readonly property bool showHoverState: mouseArea.containsMouse && !root.clickToShowPopup && root.activelyRecording

    // ── Size ─────────────────────────────────────────────────────────────────
    // Edit Mode has to be able to reach a widget that is currently showing
    // nothing: with nothing to show this takes no room at all, so there would be
    // nothing to grab, drag or place. While the mode is on it is drawn as though
    // it were active. Rendering only — the stored visibility flag stays on the
    // real condition, and the bar ORs the mode in on its side.
    readonly property bool shown: root.activelyRecording || root.isLoading || GlobalStates.editMode

    readonly property real thickness: root.vertical
        ? Appearance.sizes.verticalBarWidth - 8
        : Appearance.sizes.baseBarHeight - 8

    readonly property real targetLength: root.vertical
        ? contentLoader.implicitHeight
        : contentLoader.implicitWidth
    property real animatedLength: root.targetLength

    // One driver for the slot and the surface both — see AGENTS.md §6.1. The
    // widget changes length whenever the minutes reach two digits, when minimal
    // mode is toggled and when the design is switched; all of them ride this.
    Behavior on animatedLength {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.barResize.numberAnimation.createObject(root)
    }

    implicitWidth: root.vertical
        ? Appearance.sizes.verticalBarWidth
        : (root.shown ? root.animatedLength : 0)
    implicitHeight: root.vertical
        ? (root.shown ? root.animatedLength : 0)
        : Appearance.sizes.baseBarHeight

    visible: root.shown

    // ── Bar plumbing ─────────────────────────────────────────────────────────
    // The stored visibility flag lives in the layout, so it has to be written,
    // not bound. Guarded because the Settings page instantiates these designs
    // for its live preview, where there is no BarComponent above them.
    function reportVisibility() {
        if (typeof rootItem === "undefined")
            return;
        if (typeof rootItem.toggleVisible === "function")
            rootItem.toggleVisible(root.hasContent);
    }

    Component.onCompleted: root.reportVisibility()
    onHasContentChanged: root.reportVisibility()

    function formatTime(s) {
        const total = Math.max(0, s);
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const seconds = total % 60;
        const mm = String(minutes).padStart(2, '0');
        const ss = String(seconds).padStart(2, '0');
        // Hours only once there are any: a capture that has been running for
        // forty seconds should not reserve room for a digit that reads zero.
        return hours > 0 ? `${String(hours).padStart(2, '0')}:${mm}:${ss}` : `${mm}:${ss}`;
    }

    // ── Design ───────────────────────────────────────────────────────────────
    Loader {
        id: contentLoader
        anchors.centerIn: parent
        sourceComponent: {
            if (root.style === "neural")
                return neuralDesign;
            if (root.style === "default")
                return defaultDesign;
            return expressiveDesign;
        }
    }

    Component {
        id: defaultDesign

        DefaultRecordIndicator {
            vertical: root.vertical
            minimal: root.minimal
            live: root.live
            loading: root.isLoading
            paused: root.isPaused
            hovering: root.showHoverState
            animateDigits: root.animateDigits
            timeText: root.timeText
            stateIcon: root.stateIcon
            colContent: root.live ? root.onActivatedColor : Appearance.colors.colOnLayer1
        }
    }

    Component {
        id: expressiveDesign

        ExpressiveRecordIndicator {
            vertical: root.vertical
            thickness: root.thickness
            minimal: root.minimal
            live: root.live
            loading: root.isLoading
            paused: root.isPaused
            hovering: root.showHoverState
            animateDigits: root.animateDigits
            showLabel: root.showLabel
            timeText: root.timeText
            label: root.vertical ? root.stateLabelShort : root.stateLabel
            stateIcon: root.stateIcon
        }
    }

    Component {
        id: neuralDesign

        NeuralRecordIndicator {
            vertical: root.vertical
            thickness: root.thickness
            minimal: root.minimal
            live: root.live
            loading: root.isLoading
            paused: root.isPaused
            hovering: root.showHoverState
            animateDigits: root.animateDigits
            showLabel: root.showLabel
            timeText: root.timeText
            label: root.vertical ? root.stateLabelShort : root.stateLabel
            stateIcon: root.stateIcon
            minuteProgress: root.minuteProgress
        }
    }

    // ── Pointer and popup ────────────────────────────────────────────────────
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: !root.clickToShowPopup
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton

        // In click-to-show mode the click belongs to the popup; stopping is done
        // from its Stop button.
        onClicked: {
            if (root.clickToShowPopup)
                return;
            if (!root.activelyRecording)
                return;
            Quickshell.execDetached(["bash", Directories.recordScriptPath]);
            controlsPopup.close();
        }

        StyledPopup {
            id: controlsPopup
            hoverTarget: mouseArea
            stickyHover: true
            popupRadius: Appearance.rounding.large

            contentItem: ColumnLayout {
                id: recLayout
                spacing: 16
                implicitWidth: 320

                readonly property bool startAnim: controlsPopup.opened && controlsPopup.popupOpenProgress > 0.6

                onStartAnimChanged: {
                    if (startAnim) {
                        recCard.opacity = 0.0;
                        recCard.scale = 0.85;
                        recCardTransform.y = 25;

                        controlsRow.opacity = 0.0;
                        controlsRow.scale = 0.85;
                        controlsRowTransform.y = 25;

                        Qt.callLater(function () {
                            recCardAnim.start();
                            controlsRowAnim.start();
                        });
                    }
                }

                Connections {
                    target: controlsPopup
                    function onPopupOpenProgressChanged() {
                        if (controlsPopup.popupOpenProgress === 0.0) {
                            recCardAnim.stop();
                            controlsRowAnim.stop();

                            recCard.opacity = 0.0;
                            recCard.scale = 0.85;
                            recCardTransform.y = 25;

                            controlsRow.opacity = 0.0;
                            controlsRow.scale = 0.85;
                            controlsRowTransform.y = 25;
                        }
                    }
                }

                HeroCard {
                    id: recCard
                    startAnim: recLayout.startAnim

                    opacity: 0.0
                    scale: 0.85
                    transform: Translate {
                        id: recCardTransform
                        y: 25
                    }

                    SequentialAnimation {
                        id: recCardAnim
                        PauseAnimation {
                            duration: 40
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: recCard
                                property: "opacity"
                                to: 1.0
                                duration: 300
                            }
                            NumberAnimation {
                                target: recCard
                                property: "scale"
                                to: 1.0
                                duration: 380
                                easing.type: Easing.OutBack
                            }
                            NumberAnimation {
                                target: recCardTransform
                                property: "y"
                                to: 0
                                duration: 380
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    icon: root.isLoading ? "progress_activity" : (root.isPaused ? "pause_circle" : "videocam")
                    compactMode: true
                    adaptiveWidth: true
                    implicitHeight: 125 // Breathing room, so nothing can overlap

                    titleSize: Appearance.font.pixelSize.larger
                    subtitleSize: Appearance.font.pixelSize.small

                    title: root.isLoading ? Translation.tr("Preparing...") : root.timeText
                    subtitle: root.isLoading
                        ? Translation.tr("Authorize screen sharing in portal")
                        : (root.isPaused ? Translation.tr("Recording Paused") : Translation.tr("Recording Screen"))

                    pillText: root.isLoading
                        ? Translation.tr("Loading")
                        : (root.isPaused ? Translation.tr("PAUSED") : Translation.tr("LIVE"))
                    pillIcon: root.isLoading ? "sync" : (root.isPaused ? "pause" : "radio_button_checked")

                    pillColor: root.isLoading
                        ? Appearance.colors.colSecondaryContainer
                        : (root.isPaused ? Appearance.colors.colSecondary : Appearance.colors.colError)
                    pillTextColor: Appearance.colors.colOnPrimary
                    pillIconColor: Appearance.colors.colOnPrimary
                }

                // Interactive Controls Row
                RowLayout {
                    id: controlsRow
                    Layout.fillWidth: true
                    spacing: 12
                    visible: !root.isLoading

                    opacity: 0.0
                    scale: 0.85
                    transform: Translate {
                        id: controlsRowTransform
                        y: 25
                    }

                    SequentialAnimation {
                        id: controlsRowAnim
                        PauseAnimation {
                            duration: 100
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: controlsRow
                                property: "opacity"
                                to: 1.0
                                duration: 300
                            }
                            NumberAnimation {
                                target: controlsRow
                                property: "scale"
                                to: 1.0
                                duration: 380
                                easing.type: Easing.OutBack
                            }
                            NumberAnimation {
                                target: controlsRowTransform
                                property: "y"
                                to: 0
                                duration: 380
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    // Keystroke display, for this recording only. It is re-seeded
                    // from the persistent setting whenever a recording starts, so
                    // switching it on here never carries over to the next one.
                    RippleButton {
                        id: keysBtn
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 38
                        buttonRadius: Appearance.rounding.full

                        readonly property bool showingKeys: KeypressService.recordingEnabled

                        toggled: keysBtn.showingKeys
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover

                        onClicked: KeypressService.toggleForRecording()

                        contentItem: Item {
                            implicitWidth: keysIcon.implicitWidth
                            implicitHeight: keysIcon.implicitHeight

                            MaterialSymbol {
                                id: keysIcon
                                anchors.centerIn: parent
                                text: keysBtn.showingKeys ? "keyboard" : "keyboard_off"
                                iconSize: 18
                                color: keysBtn.showingKeys ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        StyledToolTip {
                            text: keysBtn.showingKeys
                                ? Translation.tr("Stop showing keystrokes on screen")
                                : Translation.tr("Show keystrokes on screen for this recording")
                        }
                    }

                    // Pause / Resume
                    RippleButton {
                        id: pauseBtn
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        buttonRadius: Appearance.rounding.full

                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover

                        onClicked: {
                            Quickshell.execDetached([Directories.recordScriptPath, "--pause"]);
                        }

                        contentItem: Item {
                            implicitWidth: pauseContent.implicitWidth
                            implicitHeight: pauseContent.implicitHeight

                            Row {
                                id: pauseContent
                                spacing: 8
                                anchors.centerIn: parent

                                MaterialSymbol {
                                    text: root.isPaused ? "play_arrow" : "pause"
                                    color: Appearance.colors.colOnSecondaryContainer
                                    iconSize: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: root.isPaused ? Translation.tr("Resume") : Translation.tr("Pause")
                                    color: Appearance.colors.colOnSecondaryContainer
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    // Stop
                    RippleButton {
                        id: stopBtn
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        buttonRadius: Appearance.rounding.full

                        colBackground: Appearance.colors.colErrorContainer
                        colBackgroundHover: Appearance.colors.colErrorContainerHover

                        onClicked: {
                            Quickshell.execDetached([Directories.recordScriptPath]);
                            controlsPopup.close();
                        }

                        contentItem: Item {
                            implicitWidth: stopContent.implicitWidth
                            implicitHeight: stopContent.implicitHeight

                            Row {
                                id: stopContent
                                spacing: 8
                                anchors.centerIn: parent

                                MaterialSymbol {
                                    text: "stop"
                                    color: Appearance.colors.colOnErrorContainer
                                    iconSize: 18
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: Translation.tr("Stop")
                                    color: Appearance.colors.colOnErrorContainer
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
