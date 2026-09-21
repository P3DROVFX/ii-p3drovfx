pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/**
 * Turns "the pointer is over this" into "the user means to open this".
 *
 * Hover alone is a bad trigger for a surface that grows: crossing the island on the way
 * to a window would open it, and a pointer resting on a boundary would flicker it. So an
 * intent needs dwell, and a pointer travelling fast is passing through rather than
 * arriving. Leaving has its own grace period, because the surface moves when it expands
 * and the pointer briefly finds itself outside the shape it just entered.
 *
 * `blocked` exists because a held mouse button means a drag is in progress, and changing
 * geometry or focus mid-drag ends the drag in Hyprland.
 */
QtObject {
    id: intent

    property bool hovered: false
    /** Pointer speed in px/ms, from a HoverHandler's point velocity. */
    property real pointerSpeed: 0
    property bool blocked: false

    property int dwellMs: 160
    property int graceMs: 380
    /** Above this, the pointer is crossing the island, not aiming at it. */
    property real maxEntrySpeed: 1.6

    readonly property bool engaged: intent._engaged
    property bool _engaged: false

    readonly property bool arriving: intent.hovered && !intent.blocked && !intent._engaged

    onHoveredChanged: {
        if (intent.hovered) {
            graceTimer.stop();
            if (!intent.blocked)
                dwellTimer.restart();
        } else {
            dwellTimer.stop();
            if (intent._engaged)
                graceTimer.restart();
        }
    }

    onBlockedChanged: {
        if (intent.blocked) {
            // Never open or close while blocked; reset engaged state immediately.
            dwellTimer.stop();
            graceTimer.stop();
            intent._engaged = false;
            return;
        }
        dwellTimer.stop();
        graceTimer.stop();
        if (intent.hovered)
            dwellTimer.restart();
    }

    function disengage() {
        dwellTimer.stop();
        graceTimer.stop();
        intent._engaged = false;
    }

    property Timer _dwell: Timer {
        id: dwellTimer
        interval: intent.dwellMs
        repeat: false
        onTriggered: {
            if (!intent.hovered || intent.blocked)
                return;
            // Still moving quickly: give it another dwell rather than opening under a
            // pointer that is on its way somewhere else.
            if (intent.pointerSpeed > intent.maxEntrySpeed) {
                dwellTimer.restart();
                return;
            }
            intent._engaged = true;
        }
    }

    property Timer _grace: Timer {
        id: graceTimer
        interval: intent.graceMs
        repeat: false
        onTriggered: {
            if (!intent.hovered && !intent.blocked)
                intent._engaged = false;
        }
    }
}
