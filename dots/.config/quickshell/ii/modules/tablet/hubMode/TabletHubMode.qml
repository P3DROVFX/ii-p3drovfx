pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

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
    /// Only while charging by default. Someone using this as a desk display can drop that.
    readonly property bool powerSatisfied: !(root.opts?.requireCharging ?? true)
        || !Battery.available
        || Battery.isPluggedIn
    readonly property int idleSeconds: root.opts?.idleSeconds ?? 120

    /// Cleared the moment the seat reports activity again, so dismissing does not need a
    /// timer of its own: touching the screen ends the idle state, which ends Hub Mode, and
    /// this only stops it flashing back during the same idle period.
    property bool dismissed: false

    readonly property bool armed: root.enabled && root.powerSatisfied && !GlobalStates.screenLocked

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
    readonly property bool mediaPlaying: (root.opts?.pauseWhilePlaying ?? true)
        && MprisController.isPlaying

    readonly property bool shown: root.armed && idleMonitor.isIdle
        && !root.dismissed && !root.mediaPlaying

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
                            onPressed: root.dismissed = true
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
