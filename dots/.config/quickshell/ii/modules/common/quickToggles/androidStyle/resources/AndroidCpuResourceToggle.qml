pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles.androidStyle

/**
 * The CPU alone, as one fill card filling the tile.
 *
 * Free-form like the combined tile: the card is the tile, and it decides for itself how
 * much of the design fits - icon and reading at 1x1, the name from 2x1, the temperature
 * from 2x2, and the detail rows once the tile is tall enough to hold them.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: `${Translation.tr("CPU Usage")}: ${card.percent}%`
    // The card paints the tile: its container colour is the tile's surface.
    surfaceColor: "transparent"

    ResourceMetricRequests {
        active: !root.isUnused
        metrics: ({
            temperature: true,
            // The processor's name is only read when there is a row to print it in.
            hardwareIdentity: card.showDetails
        })
    }

    ResourceFillCard {
        id: card
        anchors.fill: parent
        metric: "cpu"
        detailed: true
        radius: root.surfaceRadius
    }
}
