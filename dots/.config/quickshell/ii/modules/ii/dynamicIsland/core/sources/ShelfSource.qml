pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/**
 * Drop shelf source: active whenever files are stored in the shelf.
 */
ContinuousSource {
    id: source

    activityId: "shelf"

    readonly property int itemCount: Persistent.ready ? (Persistent.states.dockUtilities.shelf ?? []).length : 0

    condition: source.itemCount > 0
}
