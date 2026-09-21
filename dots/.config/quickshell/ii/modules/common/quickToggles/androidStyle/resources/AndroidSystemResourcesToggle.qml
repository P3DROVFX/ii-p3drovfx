pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.quickToggles.androidStyle

/**
 * System resources: up to four fill cards in one tile.
 *
 * The tile is free-form, so the arrangement is chosen from the surface it actually has
 * rather than from the stored cell size: every arrangement that still leaves each card
 * usable (74 x 40 px) is considered, the one showing the most monitors wins, and a tie is
 * broken by whichever leaves the cards closest to square. That gives, without a single
 * size written down twice:
 *
 * | Tile | Arrangement                                            |
 * |------|--------------------------------------------------------|
 * | 1x1  | CPU alone                                              |
 * | 2x1  | CPU and RAM side by side (the design's own footprint)   |
 * | 4x1  | all four in a row                                      |
 * | 1x2+ | stacked in a column, one card per row that fits        |
 * | 2x2  | a 2 x 2 grid of short cards - icon and reading only     |
 * | 4x2  | all four in a row, each tall enough for the full design |
 * | 4x4+ | a 2 x 2 grid of full cards, growing into the space      |
 *
 * The fourth monitor is the GPU where one was detected and swap where none was: a machine
 * with no readable GPU would otherwise spend a card on a reading that never moves.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("System resources")

    readonly property bool gpuDetected: ResourceUsage.gpuVendor !== "unknown"
    readonly property var allMetrics: ["cpu", "ram", "disk", root.gpuDetected ? "gpu" : "swap"]
    readonly property var shownMetrics: root.allMetrics.slice(0, root.arrangement.count)

    readonly property var arrangement: root.pickArrangement(root.surface.width, root.surface.height)

    /**
     * The best grid for this surface: most cards first, roundest cards second.
     * `pad` and `gap` scale with the smaller side so a quarter-sized card is not eaten
     * by its own margins.
     */
    function pickArrangement(surfaceWidth: real, surfaceHeight: real): var {
        const pad = Math.max(4, Math.min(10, Math.round(Math.min(surfaceWidth, surfaceHeight) * 0.07)));
        const gap = Math.max(4, Math.min(8, Math.round(Math.min(surfaceWidth, surfaceHeight) * 0.05)));
        const candidates = [[1, 1], [2, 1], [3, 1], [4, 1], [1, 2], [1, 3], [1, 4], [2, 2]];
        const minCardWidth = 74;
        const minCardHeight = 40;

        let best = null;
        for (let i = 0; i < candidates.length; i++) {
            const columns = candidates[i][0];
            const rows = candidates[i][1];
            const cardWidth = (surfaceWidth - 2 * pad - gap * (columns - 1)) / columns;
            const cardHeight = (surfaceHeight - 2 * pad - gap * (rows - 1)) / rows;
            if (cardWidth < minCardWidth || cardHeight < minCardHeight)
                continue;
            const count = columns * rows;
            const balance = Math.abs(Math.log(cardWidth / cardHeight));
            if (best === null || count > best.count || (count === best.count && balance < best.balance))
                best = { columns: columns, rows: rows, count: count, cardWidth: cardWidth,
                    cardHeight: cardHeight, balance: balance, pad: pad, gap: gap };
        }

        // Smaller than any card wants to be: one card, squeezed.
        if (best === null)
            best = { columns: 1, rows: 1, count: 1, cardWidth: Math.max(0, surfaceWidth - 2 * pad),
                cardHeight: Math.max(0, surfaceHeight - 2 * pad), balance: 0, pad: pad, gap: gap };
        return best;
    }

    // Temperature feeds the CPU card's detail line; disk and GPU are only sampled while a
    // card of theirs is actually on screen.
    ResourceMetricRequests {
        active: root.shownOnScreen
        metrics: ({
            temperature: true,
            disk: root.shownMetrics.indexOf("disk") !== -1,
            swap: root.shownMetrics.indexOf("swap") !== -1
        })
        // Requested from the fourth slot on: the vendor is only detected while the service
        // is sampling, so `gpuDetected` can never become true without asking first.
        gpu: root.arrangement.count >= 4
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: root.arrangement.pad
        columns: root.arrangement.columns
        rows: root.arrangement.rows
        columnSpacing: root.arrangement.gap
        rowSpacing: root.arrangement.gap

        Repeater {
            model: root.shownMetrics

            delegate: ResourceFillCard {
                required property string modelData

                Layout.fillWidth: true
                Layout.fillHeight: true

                metric: modelData
                radius: Config.options.appearance.sharpMode ? 0
                    : Math.min(root.arrangement.cardWidth / 2, root.arrangement.cardHeight / 2,
                        Appearance.rounding.normal)
            }
        }
    }
}
