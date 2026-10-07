import QtQuick
import qs
import qs.services
import qs.modules.common

QuickToggleModel {
    name: Translation.tr("Draw on screen")
    statusText: LiveDraw.trayOpen
        ? (LiveDraw.drawing ? Translation.tr("Drawing") : Translation.tr("Pen up"))
        : (LiveDraw.sheetCount > 0 ? Translation.tr("Ink on screen") : "")
    toggled: LiveDraw.trayOpen
    icon: "draw"

    mainAction: () => {
        // Out of the way first: the overlay draws over everything, the panel included,
        // and the first stroke should land on the screen rather than on the dashboard.
        if (!LiveDraw.trayOpen)
            GlobalStates.sidebarRightOpen = false;
        LiveDraw.toggle();
    }

    tooltipText: Translation.tr("Draw over the screen — for recordings, calls and screen sharing")
}
