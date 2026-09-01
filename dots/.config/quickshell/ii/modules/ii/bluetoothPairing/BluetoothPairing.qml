pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The pairing prompt, for every pairing, wherever it started.
 *
 * BlueZ asks its registered agent, not whichever window happens to be open, so a
 * pairing begun from the sidebar, from `bluetoothctl`, or by the other device
 * reaching out first has nowhere to answer without this. It is the only place
 * the question is ever put: a prompt that only sometimes appears is one the user
 * has to go looking for.
 *
 * Nothing is shown over a locked session: the lock surface draws above every
 * layer shell, so the card would be invisible while still taking keyboard focus.
 * The question is left in the queue instead, and BlueZ times it out itself.
 */
Scope {
    id: root

    readonly property bool shouldShow: (BluetoothAgent.hasRequest || BluetoothAgent.display !== null)
        && !GlobalStates.screenLocked

    // The card animates out, so the window has to outlive the answer by the
    // length of that animation or the whole thing vanishes mid-fade.
    property bool closing: false

    onShouldShowChanged: {
        if (root.shouldShow) {
            closeDelay.stop();
            root.closing = false;
            return;
        }
        root.closing = true;
        closeDelay.restart();
    }

    Timer {
        id: closeDelay
        interval: 300
        onTriggered: root.closing = false
    }

    LazyLoader {
        active: root.shouldShow || root.closing

        component: PanelWindow {
            id: promptWindow
            screen: Quickshell.screens.find(monitor => monitor.name === Hyprland.focusedMonitor?.name) ?? null
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            WlrLayershell.namespace: "quickshell:bluetoothPairing"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            BluetoothPairingContent {
                anchors.fill: parent
                focus: true
                wanted: root.shouldShow
            }
        }
    }
}
