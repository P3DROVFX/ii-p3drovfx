pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.ii.dynamicIsland.core

/**
 * The phone's "KDE Connect Remote Keyboard" just came up in a text field, so the PC
 * keyboard can type there. Said once per time it comes up; a click opens the pad.
 */
TransientSource {
    id: source

    activityId: "phoneKeyboard"
    ttlMs: 5000
    cooldownMs: 3000

    // The service starts out "not active" whatever the truth, and the first report after
    // it attaches a device is the baseline, not the user doing anything.
    property bool _was: true

    property Connections _service: Connections {
        target: KdeConnectService
        function onRemoteKeyboardActiveChanged() {
            const now = KdeConnectService.remoteKeyboardActive;
            if (now && !source._was)
                source.trigger({ device: KdeConnectService.activeDeviceDisplayName });
            source._was = now;
        }
    }

    property Timer _baseline: Timer {
        interval: 8000
        running: true
        onTriggered: source._was = KdeConnectService.remoteKeyboardActive
    }
}
