pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.ii.dynamicIsland.core

/**
 * A notification is asking to be seen.
 *
 * `Notifications.popupList` already carries its own lifetime (each notification expires
 * or is dismissed), so this is a state and not an announcement: the island shows one for
 * as long as the service says there is one.
 *
 * Except while it is being read: the pointer on the island stops the popups' timers, the
 * way the standalone popup does, so a notification never expires under the pointer (the
 * island would drop its card and open the dashboard in its place). Leaving counts as
 * read - the paused popups go once the island's collapse grace has passed, the same
 * wait that folds the dashboard.
 */
ContinuousSource {
    id: source

    activityId: "notification"
    condition: Notifications.popupList.length > 0
    payload: Notifications.popupList

    // A second notification arriving while the first is still up is an accent on an
    // activity that is already present, not a new arrival.
    property int _seen: 0
    property Connections _notifications: Connections {
        target: Notifications
        function onPopupListChanged() {
            const now = Notifications.popupList.length;
            if (now > source._seen && source.active)
                source.revision += 1;
            source._seen = now;
            // One arriving under the pointer is being read as well.
            if (source.hovered)
                source.pauseTimeouts();
        }
    }

    // ── Held while read ──────────────────────────────────────────────────────
    /** The popups the pointer stopped, which leaving then dismisses. */
    property var _pausedIds: []

    function pauseTimeouts() {
        const ids = source._pausedIds.slice();
        Notifications.popupList.forEach(notif => {
            Notifications.cancelTimeout(notif.notificationId);
            if (ids.indexOf(notif.notificationId) === -1)
                ids.push(notif.notificationId);
        });
        source._pausedIds = ids;
    }

    onHoveredChanged: {
        if (source.hovered) {
            leaveTimer.stop();
            source.pauseTimeouts();
        } else if (source._pausedIds.length > 0) {
            leaveTimer.restart();
        }
    }

    property Timer _leaveTimer: Timer {
        id: leaveTimer
        interval: IslandPolicy.collapseGraceMs
        onTriggered: {
            const ids = source._pausedIds;
            source._pausedIds = [];
            // As the service's own timer ends them; one closed meanwhile is already gone.
            Notifications.popupList.filter(notif => ids.indexOf(notif.notificationId) !== -1)
                .forEach(notif => {
                    if (notif.isTransient)
                        Notifications.discardNotification(notif.notificationId);
                    else
                        Notifications.timeoutNotification(notif.notificationId);
                });
        }
    }
}
