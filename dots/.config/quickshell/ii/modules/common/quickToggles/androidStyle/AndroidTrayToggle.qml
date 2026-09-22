pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * The system tray as an island dashboard tile: the tablet shade's tray pill, at
 * grid sizes.
 *
 * The content is the shared `SystemTrayPill` itself — the same component the
 * shade's action row draws — so the count line, the disabled empty state and the
 * metrics all stay in one place. The pill is a function of `rowHeight`, and the
 * tile hands it the surface height, which is what makes every 1-row size
 * (2x1…6x1) the same design with more or less room for the text.
 *
 * A click asks the panel for the tray: `openTrayDialog`, which the sidebar hosts
 * answer as a dialog and the island answers as a page (the same `TabletTrayDialog`,
 * in page mode). While the grid is in edit mode the pill stops taking presses —
 * the edit overlay owns them for drag and resize — without dimming: the dim is the
 * empty tray's, not the editing one's.
 *
 * The surface is transparent because the pill is the surface: it draws its own
 * full-round background, exactly as the shade draws it.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: Translation.tr("Active apps")
    surfaceColor: "transparent"

    SystemTrayPill {
        anchors.fill: parent
        rowHeight: root.surface.height
        interactionEnabled: !root.editMode
        onTrayRequested: {
            if (root.panel)
                root.panel.openTrayDialog();
        }
    }
}
