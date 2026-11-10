pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.ii.dynamicIsland.core

/**
 * A call on the paired phone.
 *
 * Three shapes of one activity. Ringing is an interrupt with the highest priority on the
 * island: it takes the centre and nothing - a notification included - takes it back until
 * the call is answered or gone. Talking is a live glance beside the clock with the call's
 * length. A missed call is said once, in the centre, and leaves.
 */
ContinuousSource {
    id: source

    activityId: "phoneCall"

    readonly property string callState: PhoneCallService.callState
    /** "ringing", "talking" or "missed", for the face. */
    readonly property string phase: source.missedShowing ? "missed" : source.callState

    property bool missedShowing: false
    property string missedName: ""

    condition: PhoneCallService.active || source.missedShowing
    payload: source.phase

    readonly property bool announcing: source.missedShowing && !PhoneCallService.active
    /** A missed call is a one-line pill, not the ringing card's box; see NotchIsland. */
    readonly property var sizeOverride: source.phase === "missed" ? ({ width: 320, height: -1 }) : null
    readonly property string tierOverride: source.callState === "ringing" ? "interrupt"
        : (source.announcing ? "transient" : "live")

    onPhaseChanged: if (source.active) source.revision += 1

    property Connections _missed: Connections {
        target: PhoneCallService
        function onMissed(displayName, number) {
            if (!source.allowed)
                return;
            source.missedName = displayName !== "" ? displayName : number;
            source.missedShowing = true;
            source._missedTimer.restart();
        }
    }

    property Timer _missedTimer: Timer {
        interval: 5000
        onTriggered: {
            if (source.hovered)
                source._missedTimer.restart();
            else
                source.missedShowing = false;
        }
    }
}
