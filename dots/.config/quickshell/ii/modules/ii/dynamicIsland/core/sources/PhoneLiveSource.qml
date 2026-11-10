pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.ii.dynamicIsland.core

/**
 * A live notification on the phone: an order on its way, a ride arriving.
 *
 * Only exists with the optional ii tools Android app, which relays the ongoing
 * notifications KDE Connect would drop (see KdeConnectService.liveUpdates). Without
 * the app the list is always empty and this never begins.
 *
 * The newest one sits beside the clock for as long as it lasts. The interruption -
 * "out for delivery" - is its shell notification (KdeConnectService._syncLivePopups),
 * which the island shows like any other, so this source never takes the centre.
 */
ContinuousSource {
    id: source

    activityId: "phoneLive"

    readonly property var current: (KdeConnectService.liveUpdates ?? [])[0] ?? null

    condition: source.current !== null
    payload: source.current
}
