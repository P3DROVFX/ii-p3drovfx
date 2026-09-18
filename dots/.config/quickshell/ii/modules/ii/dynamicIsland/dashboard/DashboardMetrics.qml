pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.quickToggles
import "../../../common/quickToggles/androidStyle/QuickToggleCatalog.js" as QuickToggleCatalog
import "../../../common/quickToggles/androidStyle/QuickToggleLayout.js" as QuickToggleLayout

/**
 * The dashboard's size at rest, computed from its layout - no grid needs to exist.
 *
 * The island starts morphing the moment it decides to show the dashboard, but the
 * dashboard's content is only built after the outgoing face has faded (about 130 ms).
 * Until then the island had nothing to size itself from and aimed at a guess larger
 * than the real grid, then retargeted when the grid appeared: it grew too far and
 * bounced back. These are the same numbers the panel lays itself out with (the packer,
 * the compact slider rows, the paddings), so the first target is already the final one.
 */
Singleton {
    id: root

    // Kept in step with AndroidQuickPanel's defaults and IslandDashboard's frame.
    readonly property real cellWidth: 96
    readonly property real cellHeight: 56
    readonly property real spacing: 6
    readonly property real panelPadding: 6
    readonly property real framePadding: 8

    readonly property var layout: Config.ready ? Config.options.dynamicIsland.dashboard.quickToggles : null
    readonly property int columns: root.layout ? Math.max(1, root.layout.columns) : 6
    readonly property int rows: root.layout ? Math.max(1, root.layout.rows) : 6

    readonly property real compactRowHeight: QuickToggleMetrics.sliderWidgetHeight(root.cellHeight)
    readonly property var compactTypes: QuickToggleCatalog.allTypes().filter(type => QuickToggleCatalog.kind(type) === "slider")

    readonly property real gridWidth: root.columns * root.cellWidth + (root.columns - 1) * root.spacing

    /** Height the panel's single page lays out to, exactly as AndroidQuickPanel.pageHeight. */
    readonly property real pageHeight: {
        if (!root.layout)
            return root.cellHeight;
        const pages = QuickToggleCatalog.normalizePages(root.layout.pages, root.columns, {});
        const page = pages.length > 0 ? pages[0] : [];
        const packed = QuickToggleLayout.pack(page, root.columns, root.cellWidth, root.cellHeight, root.spacing);
        const heights = QuickToggleLayout.rowPixelHeights(packed, root.cellHeight, root.spacing,
            root.compactRowHeight, root.compactTypes);
        if (!heights)
            return Math.max(root.cellHeight, packed.rowsUsed * (root.cellHeight + root.spacing) - root.spacing);
        let total = 0;
        for (let i = 0; i < heights.length; i++)
            total += heights[i] + root.spacing;
        return Math.max(root.cellHeight, total - root.spacing);
    }

    readonly property real restWidth: root.gridWidth + 2 * root.panelPadding + 2 * root.framePadding
    readonly property real restHeight: root.pageHeight + 2 * root.panelPadding + 2 * root.framePadding
}
