pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.settings.configs.lockscreen
import "../../common/functions/aod.js" as Aod
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The Always On Display, raised from the desktop.
 *
 * The screen fades to pure black and the widgets the lock keeps glide from their
 * desktop spots to the lock's layout, drained of colour. Leaving it (a click or a
 * key) lands back on the desktop.
 *
 * Nothing here inhibits idle: the lock's own timeout still runs underneath. When it
 * locks, the lock's AOD (LockSurface, BackgroundRoot and the widgets window, all
 * keyed on the same `oledSaverMonitors`) takes over this screen and this window
 * fades out once the real widgets have reached the lock's layout. The lock raises
 * the AOD on its own timer (Lock.qml); this window never shows over a lock.
 */
Scope {
    id: root

    function toggle() {
        if (!(Config.options.oledSaver.enable ?? true)) return;
        const name = Hyprland.focusedMonitor?.name;
        if (!name) return;
        const monitors = GlobalStates.oledSaverMonitors;
        GlobalStates.oledSaverMonitors = monitors.includes(name) ? monitors.filter(n => n !== name) : [...monitors, name];
    }

    function close(name) {
        GlobalStates.oledSaverMonitors = GlobalStates.oledSaverMonitors.filter(n => n !== name);
    }

    // An AOD still up at unlock (a fingerprint unlocks without waking it) must not
    // follow the user onto the desktop.
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (!GlobalStates.screenLocked)
                GlobalStates.oledSaverMonitors = [];
        }
    }

    // Clear AOD monitors immediately when disabled in settings.
    Connections {
        target: Config.options.oledSaver
        function onEnableChanged() {
            if (!Config.options.oledSaver.enable)
                GlobalStates.oledSaverMonitors = [];
        }
    }

    IpcHandler {
        target: "oledSaver"

        function toggle() {
            root.toggle();
        }
    }

    GlobalShortcut {
        name: "oledSaverToggle"
        description: "Toggles the Always On Display on the focused monitor"
        onPressed: root.toggle()
    }

    component AodWindow: PanelWindow {
        id: window
        signal dismiss

        // The screen's AodState, which outlives this window's fade out.
        required property AodState aod
        readonly property string screenName: window.aod.screenName
        readonly property bool holdsInput: window.aod.holdsInput
        readonly property bool shown: window.aod.shown
        readonly property real progress: window.aod.progress
        onBackingWindowVisibleChanged: {
            if (window.backingWindowVisible)
                window.aod.mapped = true;
        }

        color: "transparent"
        WlrLayershell.namespace: "quickshell:oledSaver"
        // Top (not Overlay) so OSD, notifications, polkit prompts, etc. still
        // render above the AOD instead of being hidden by it.
        WlrLayershell.layer: WlrLayer.Top
        // OnDemand (not Exclusive) so only this monitor's input is captured;
        // Exclusive grabs all input globally, blocking mouse on other monitors.
        WlrLayershell.keyboardFocus: window.holdsInput ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Explicit mask constrains input to this window's bounds on this output only.
        // Released while fading out, so the desktop takes clicks again at once.
        mask: Region {
            item: window.holdsInput ? windowMaskItem : null
        }

        // Start the same way a mouse move leaves things: cursor shown, hide timer
        // already counting down.
        property bool cursorVisible: true

        // A focus grab held while this window's surface is still mapping keeps
        // the pointer focused on whatever is underneath, so Qt never learns the
        // cursor is inside and can never swap it for the blank one - the old
        // cursor image would sit on the blackout until the user moved the mouse.
        // Arming the grab a moment after the surface is up lets the pointer
        // enter land first, then still routes keys here without a click.
        HyprlandFocusGrab {
            id: aodGrab
            windows: [window]
            active: false
        }

        Timer {
            running: true
            interval: 100
            onTriggered: aodGrab.active = window.holdsInput
        }
        Connections {
            target: window
            function onHoldsInputChanged() {
                if (!window.holdsInput)
                    aodGrab.active = false;
            }
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: window.progress
        }

        // The widgets the lock keeps, where the lock keeps them, in grey.
        LockWidgetLayer {
            anchors.fill: parent
            monitorName: window.screenName
            atLock: window.shown
            burnInShiftX: GlobalStates.aodBurnInShiftX
            burnInShiftY: GlobalStates.aodBurnInShiftY
            opacity: window.progress
            visible: opacity > 0
            layer.enabled: true
            layer.effect: MultiEffect {
                saturation: -window.progress
            }
        }

        Item {
            id: windowMaskItem
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                // Held modifiers are not typing - and Super is the first half of the
                // shortcut that toggles this window, which would re-raise it.
                if (!Aod.keyWakes(event.key))
                    return;
                event.accepted = true;
                window.dismiss();
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: window.cursorVisible ? Qt.ArrowCursor : Qt.BlankCursor

                onPositionChanged: {
                    window.cursorVisible = true;
                    cursorHideTimer.restart();
                }
                onClicked: window.dismiss()
            }

            Timer {
                id: cursorHideTimer
                running: true
                interval: Config.options.oledSaver.cursorHideDelay * 1000
                onTriggered: window.cursorVisible = false
            }
        }
    }

    // One screen's AOD: whether it is wanted, and the fade that the window follows.
    component AodState: Scope {
        id: aodState
        required property string screenName
        readonly property bool listed: (Config.options.oledSaver.enable ?? true) && GlobalStates.oledSaverMonitors.includes(aodState.screenName)
        // The first frames go to mapping the surface; the fade waits for it instead of
        // starting half-way through.
        property bool mapped: false
        // Set once the lock's own AOD holds this screen; cleared on unlock.
        property bool handedOff: GlobalStates.screenLocked
        // Owns input from the moment it maps until it is dismissed or handed off; the
        // fade out that follows is look only.
        readonly property bool holdsInput: aodState.listed && !aodState.handedOff
        readonly property bool shown: aodState.holdsInput && aodState.mapped
        property real progress: aodState.shown ? 1 : 0
        Behavior on progress {
            animation: Appearance.animation.elementMoveSlow.numberAnimation.createObject(aodState)
        }
        // Kept alive through the fade out, and through the hand-off to the lock.
        readonly property bool windowWanted: aodState.holdsInput || aodState.progress > 0.001
        onWindowWantedChanged: {
            if (!aodState.windowWanted)
                aodState.mapped = false;
        }

        Timer {
            id: handoffTimer
            interval: Appearance.animation.elementMoveSlow.duration
            onTriggered: aodState.handedOff = true
        }
        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    handoffTimer.restart();
                } else {
                    handoffTimer.stop();
                    aodState.handedOff = false;
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: screenScope
            required property var modelData

            AodState {
                id: aodState
                screenName: screenScope.modelData.name
            }

            Loader {
                active: aodState.windowWanted

                sourceComponent: AodWindow {
                    screen: screenScope.modelData
                    aod: aodState
                    onDismiss: root.close(screenScope.modelData.name)
                }
            }
        }
    }
}
