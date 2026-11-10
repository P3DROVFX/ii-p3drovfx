pragma ComponentBehavior: Bound

import QtQuick
import qs.services

/**
 * Drop shelf source: active whenever files are stored in the shelf.
 */
ContinuousSource {
    id: source

    activityId: "shelf"

    readonly property int itemCount: FileShelf.count

    condition: source.itemCount > 0
}
