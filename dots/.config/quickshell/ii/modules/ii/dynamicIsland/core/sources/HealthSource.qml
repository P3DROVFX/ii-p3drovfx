pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.ii.dynamicIsland.core

/**
 * A new critical System Health problem: a service that failed, a program that crashed.
 *
 * HealthService already decided it is worth saying — live, new, unmuted, inside the
 * alert budget, and not while you are fullscreen. When the island refuses it (the quiet
 * window after a boot or an unlock) it falls back to a notification: a failure must not
 * go unsaid.
 */
TransientSource {
    id: source

    activityId: "health"
    ttlMs: 9000
    cooldownMs: 800

    property Connections _service: Connections {
        target: HealthService
        function onIslandAlert(payload) {
            if (!source.trigger(payload))
                HealthService.notifyAlert(payload);
        }
    }
}
