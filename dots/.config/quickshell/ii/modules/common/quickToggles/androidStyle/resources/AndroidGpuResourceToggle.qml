pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles.androidStyle

/**
 * The GPU alone, as one fill card filling the tile.
 *
 * GPU sampling is the expensive one - a nvidia-smi or fdinfo pass per tick - so it is
 * held only while the tile is live on a grid. Until the vendor is detected the card
 * reads zero and says so in its detail line.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: `${Translation.tr("GPU Usage")}: ${card.percent}%`
    surfaceColor: "transparent"

    ResourceMetricRequests {
        active: !root.isUnused
        gpu: true
    }

    ResourceFillCard {
        id: card
        anchors.fill: parent
        metric: "gpu"
        detailed: true
        radius: root.surfaceRadius
    }
}
