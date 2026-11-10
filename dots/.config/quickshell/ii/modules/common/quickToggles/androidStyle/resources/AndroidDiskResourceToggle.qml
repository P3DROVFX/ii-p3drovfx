pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles.androidStyle

/**
 * The monitored disk alone, as one fill card filling the tile.
 *
 * `df` only runs while this tile is live on a grid: the request is dropped the moment the
 * tile is destroyed or drawn in the tray.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: `${Translation.tr("Disk Storage")}: ${card.percent}%`
    surfaceColor: "transparent"

    ResourceMetricRequests {
        active: root.shownOnScreen
        metrics: ({ disk: true })
    }

    ResourceFillCard {
        id: card
        anchors.fill: parent
        metric: "disk"
        detailed: true
        radius: root.surfaceRadius
    }
}
