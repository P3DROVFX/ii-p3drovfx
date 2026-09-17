pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.ii.dynamicIsland.core

/**
 * An announcement: visible for `ttlMs`, then gone.
 *
 * `trigger()` is the only way in, and it refuses during the quiet window, so a boot, a
 * hot reload or an unlock cannot masquerade as user activity. `cooldownMs` collapses
 * bursts - the three `wl-paste --watch` processes each fire on one copy, and a device
 * that flaps reconnects several times a second.
 */
IslandSource {
    id: source

    property int ttlMs: 2500
    property int cooldownMs: 0
    /** A TTL that pauses under the pointer, so reading it never races the timer. */
    property bool holdWhileHovered: true

    property double _lastTrigger: 0

    function trigger(data) {
        if (!source.allowed || IslandPolicy.quietWindowActive)
            return false;
        const now = Date.now();
        if (source.cooldownMs > 0 && (now - source._lastTrigger) < source.cooldownMs)
            return false;
        source._lastTrigger = now;
        source.begin(data);
        ttl.restart();
        return true;
    }

    function dismiss() {
        ttl.stop();
        source.end();
        // A transient payload is always passed in by hand, so clearing it here cannot
        // break a binding and keeps stale announcements out of the next one.
        source.payload = null;
    }

    property Timer _ttl: Timer {
        id: ttl
        interval: source.ttlMs
        repeat: false
        onTriggered: {
            if (source.hovered && source.holdWhileHovered)
                ttl.restart();
            else
                source.dismiss();
        }
    }
}
