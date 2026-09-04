pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "TabletHubModeState.js" as HubState

/**
 * What the tablet becomes when it is charging and nobody is using it.
 *
 * The Pixel Tablet's defining trick is that docking it stops it being a tablet: it turns
 * into a photo frame and a smart display, useful from across the room. That is the one
 * feature of the reference product this family had no answer to at all — plugged in and
 * idle, it just sat on the home screen at full brightness.
 *
 * The trigger is charging plus idle, because "docked" is not something this shell can know.
 * A charging cable is the closest honest proxy: it is the state where the device is parked
 * somewhere rather than in your hands, and it is also the state where an always-on screen
 * costs nothing.
 *
 * Deliberately not the OLED saver, which blanks the screen. This is the opposite request —
 * the screen stays on and shows something worth looking at — so the two are separate
 * surfaces, and Hub Mode stands down whenever the saver is up on that monitor rather than
 * fighting it for the same output.
 */
Scope {
    id: root

    readonly property var opts: Config.options?.tablet?.hubMode ?? null
    readonly property bool enabled: Config.ready && (root.opts?.enable ?? false)
    readonly property int idleSeconds: root.opts?.idleSeconds ?? 120

    /**
     * Everything that decides whether hub mode *can* happen, without anything that says
     * whether it is happening now.
     *
     * Split from `hubState` on purpose: the idle monitor's `enabled` is bound to `armed`,
     * so folding `isIdle` in here would have the monitor's arming depend on its own
     * output. It settles — the boolean does not change, so nothing re-notifies — but it is
     * a loop waiting for the first condition that makes it oscillate.
     */
    readonly property var armingState: ({
        enable: root.enabled,
        requireCharging: root.opts?.requireCharging ?? true,
        batteryAvailable: Battery.available,
        pluggedIn: Battery.isPluggedIn,
        screenLocked: GlobalStates.screenLocked
    })

    // One record, so the conditions below can be exercised without a battery, an idle
    // seat and a two-minute wait. See TabletHubModeState.js.
    readonly property var hubState: Object.assign({}, root.armingState, {
        idle: idleMonitor.isIdle,
        dismissed: root.dismissed,
        pauseWhilePlaying: root.opts?.pauseWhilePlaying ?? true,
        mediaPlaying: MprisController.isPlaying,
        previewRequested: GlobalStates.hubModePreview
    })

    /// Only while charging by default. Someone using this as a desk display can drop that.
    readonly property bool powerSatisfied: HubState.powerSatisfied(root.armingState)

    /// Cleared the moment the seat reports activity again, so dismissing does not need a
    /// timer of its own: touching the screen ends the idle state, which ends Hub Mode, and
    /// this only stops it flashing back during the same idle period.
    property bool dismissed: false

    readonly property bool armed: HubState.armed(root.armingState)

    // Changing `timeout` in place leaves the monitor latched to a notification that no
    // longer exists — the keyboard backlight learned this the hard way — so the timeout is
    // read once per arming and `enabled` is cycled to re-arm.
    property bool _rearming: false
    onIdleSecondsChanged: {
        root._rearming = true;
        rearmTimer.restart();
    }

    readonly property Timer _rearmTimer: Timer {
        id: rearmTimer
        interval: 250
        repeat: false
        onTriggered: root._rearming = false
    }

    readonly property IdleMonitor _idleMonitor: IdleMonitor {
        id: idleMonitor
        enabled: root.armed && !root._rearming
        timeout: root.idleSeconds
        // Raw seat input, not the compositor's idle state: a video player holding an idle
        // inhibitor is exactly the case where the screen should stay as it is, and that is
        // handled by `mediaPlaying` below rather than by never noticing the user left.
        respectInhibitors: false
        onIsIdleChanged: {
            if (!idleMonitor.isIdle)
                root.dismissed = false;
        }
    }

    /// Something is playing and visible; taking the screen would interrupt watching it.
    readonly property bool mediaPlaying: HubState.mediaHolding(root.hubState)

    /**
     * A preview the user asked for.
     *
     * Deliberately bypasses `armed` in full — the charging cable, the idle timer, even
     * `enable` itself. Someone reaching for this is deciding whether to turn hub mode on,
     * and requiring it to already be on to see what it does is the circle that left this
     * feature untestable. See GlobalStates.hubModePreview.
     */
    readonly property bool previewing: HubState.previewing(root.hubState)

    readonly property bool shown: HubState.shouldShow(root.hubState)

    /// Ends the surface however it was started: a preview clears the request, an idle
    /// takeover is dismissed for the rest of this idle period.
    function dismiss() {
        if (GlobalStates.hubModePreview)
            GlobalStates.hubModePreview = false;
        else
            root.dismissed = true;
    }

    // A preview is a surface with no keyboard that covers the screen. The tap-to-exit
    // target is the whole thing, so this should never fire — but "should never" is a poor
    // guarantee for something the user cannot alt-tab away from, and the cost of the net
    // is one timer.
    readonly property Timer _previewSafety: Timer {
        interval: 45000
        repeat: false
        running: root.previewing
        onTriggered: GlobalStates.hubModePreview = false
    }

    // Locking the screen while a preview is up would otherwise leave the request set, and
    // hub mode would be waiting on the other side of the unlock.
    readonly property Connections _lockWatch: Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                GlobalStates.hubModePreview = false;
        }
    }

    /// `qs -c ii ipc call hubMode preview` — the same door Settings and the bubble use.
    IpcHandler {
        target: "hubMode"

        function preview(): string {
            GlobalStates.hubModePreview = true;
            return "Hub mode preview shown. Tap the screen to leave it.";
        }

        function hide(): string {
            GlobalStates.hubModePreview = false;
            root.dismissed = true;
            return "Hub mode dismissed.";
        }

        function toggle(): string {
            GlobalStates.toggleHubModePreview();
            return GlobalStates.hubModePreview ? "Hub mode preview shown." : "Hub mode preview hidden.";
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property ShellScreen modelData

            Loader {
                active: root.shown || hubWindow.item?.fadeOpacity > 0.01
                id: hubWindow

                sourceComponent: PanelWindow {
                    id: hub
                    screen: screenScope.modelData

                    property real fadeOpacity: root.shown ? 1 : 0

                    Behavior on fadeOpacity {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.OutCubic
                        }
                    }

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.namespace: "quickshell:tabletHubMode"
                    WlrLayershell.layer: WlrLayer.Overlay
                    // Never exclusive: the point is to get out of the way instantly, and a
                    // surface holding the keyboard cannot be dismissed by typing.
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colLayer0Base
                        opacity: hub.fadeOpacity

                        // Any contact ends it. There is nothing to press here — the whole
                        // surface is the dismiss target, which is what an ambient display
                        // should be.
                        MouseArea {
                            anchors.fill: parent
                            onPressed: root.dismiss()
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: DateTime.time
                                font.family: Appearance.font.family.title
                                // Big enough to read from across a room, which is the whole
                                // reason this surface exists.
                                font.pixelSize: Math.round((screenScope.modelData?.height ?? 1080) * 0.18)
                                color: Appearance.colors.colOnLayer0
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: DateTime.date
                                font.pixelSize: Appearance.font.pixelSize.huge
                                color: Appearance.colors.colSubtext
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 28
                                spacing: 10
                                visible: Weather.data?.temp !== undefined

                                Image {
                                    source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                                    sourceSize: Qt.size(32, 32)
                                }

                                StyledText {
                                    text: `${Weather.data?.temp ?? ""}  ${Weather.data?.wDesc ?? ""}`.trim()
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 10
                                spacing: 10
                                visible: (MprisController.activePlayer?.trackTitle ?? "").length > 0

                                MaterialSymbol {
                                    text: "music_note"
                                    iconSize: 20
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    text: MprisController.activePlayer?.trackTitle ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: Math.round((screenScope.modelData?.width ?? 1920) * 0.5)
                                }
                            }
                        }

                        /**
                         * The way out, spelled out — but only for a preview.
                         *
                         * An idle takeover is dismissed by the same touch that would have
                         * woken the device anyway, so it needs no instructions. A preview
                         * is a full-screen surface the user summoned on purpose from a
                         * settings page, and the one thing they need to know is that it is
                         * not stuck.
                         */
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 40
                            visible: root.previewing
                            opacity: hub.fadeOpacity
                            text: Translation.tr("Preview — tap anywhere to leave")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }

                        // Charge state in a corner, the way a docked device shows it. Small:
                        // it is a reassurance, not the reason anyone looks over here.
                        RowLayout {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 32
                            spacing: 8
                            visible: Battery.available

                            MaterialSymbol {
                                text: Battery.isCharging ? "battery_charging_full" : "battery_full"
                                iconSize: 18
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                text: `${Math.round(Battery.percentage * 100)}%`
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }
        }
    }
}
