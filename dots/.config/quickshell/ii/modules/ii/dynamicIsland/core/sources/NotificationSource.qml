pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * A notification is asking to be seen.
 *
 * `Notifications.popupList` already carries its own lifetime (each notification expires
 * or is dismissed), so this is a state and not an announcement: the island shows one for
 * as long as the service says there is one.
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
        }
    }
}
