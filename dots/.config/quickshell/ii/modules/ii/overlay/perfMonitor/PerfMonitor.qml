import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.ii.overlay

StyledOverlayWidget {
    id: root
    title: Translation.tr("Performance")
    showCenterButton: true
    // The HUD draws its own semi-transparent card and sizes itself from the
    // toggles, so it neither fades when click-through nor resizes by hand.
    opacity: 1
    resizable: false

    function savePosition(xPos = root.x, yPos = root.y, width = 0, height = 0) {
        root.persistentStateEntry.x = Math.round(xPos);
        root.persistentStateEntry.y = Math.round(yPos);
        root.persistentStateEntry.width = 0;
        root.persistentStateEntry.height = 0;
    }

    contentItem: PerfMonitorContent {
        monitoring: root.visible
    }
}
