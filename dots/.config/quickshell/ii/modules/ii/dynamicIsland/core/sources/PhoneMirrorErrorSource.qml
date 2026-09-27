pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.ii.dynamicIsland.core

/**
 * A phone mirror or app window that failed to open, or died on its own.
 *
 * PhoneScrcpyService already turned scrcpy's message into something to act on. When the
 * island owns these failures the service does not post a notification, so an
 * announcement the island refuses (the quiet window after a boot or unlock) falls back
 * to one here — a failure must never go unsaid.
 */
TransientSource {
    id: source

    activityId: "phoneMirrorError"
    ttlMs: 6000
    cooldownMs: 1000

    property Connections _service: Connections {
        target: PhoneScrcpyService
        function onMirrorFailed(sessionId, title, reason) {
            if (source.trigger({ sessionId: sessionId, title: title, reason: reason }))
                return;
            Notifications.publishInternalNotification({
                "appName": Translation.tr("Phone"),
                "appIcon": "smartphone",
                "summary": title,
                "body": reason,
                "urgency": "normal"
            });
        }
    }
}
