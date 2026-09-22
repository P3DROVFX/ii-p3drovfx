pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle
import qs.modules.ii.background.widgets.clock

/**
 * Digital clock tile: the background widget's DigitalClock, instantiated as-is.
 *
 * The `clock_digital` settings the desktop widget uses are the whole configuration:
 * typography (size, weight, width, roundness), the vertical line spacing and the
 * extras (date, quote, colon, seconds). Nothing is re-configured here, so the settings
 * page for the Digital Clock widget stays the only place to change the look.
 *
 * What the tile owns is the fit and the orientation:
 * - Free-form sizing: the configured design is laid out at its natural size and scaled
 *   as a whole into whatever footprint the grid gives it, so every size from 1x1 up
 *   works and the configured proportions survive.
 * - A tile taller than wide stacks the two lines (the vertical form); a wider tile runs
 *   the single-line form.
 *
 * Does not toggle anything on click; purely an information display tile.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Clock")

    /** Portrait tiles stack the lines, landscape tiles run the single-line form. */
    readonly property bool isVertical: root.surface.height > root.surface.width

    DigitalClock {
        id: clockContent
        anchors.centerIn: parent
        isVertical: root.isVertical

        readonly property real fitPadding: Math.max(8, Math.round(Math.min(root.surface.width, root.surface.height) * 0.10))
        scale: Math.min(
            Math.max(10, root.surface.width - fitPadding * 2) / Math.max(1, implicitWidth),
            Math.max(10, root.surface.height - fitPadding * 2) / Math.max(1, implicitHeight))
    }
}
