pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles.androidStyle

/**
 * RAM alone, as one fill card filling the tile.
 *
 * The amounts in use replace the temperature line the CPU card has; swap is only sampled
 * once the tile is tall enough for the detail rows that show it.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: `${Translation.tr("RAM Memory")}: ${card.percent}%`
    surfaceColor: "transparent"

    ResourceMetricRequests {
        active: root.shownOnScreen
        metrics: ({ swap: card.showDetails })
    }

    ResourceFillCard {
        id: card
        anchors.fill: parent
        metric: "ram"
        detailed: true
        radius: root.surfaceRadius
    }
}
