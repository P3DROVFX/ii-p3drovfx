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
    // toggles, so it neither fades when click-through nor resizes by hand,
    // and it may sit flush against the top of the screen.
    opacity: 1
    resizable: false
    flushToEdges: true

    function savePosition(xPos = root.x, yPos = root.y, width = 0, height = 0) {
        root.persistentStateEntry.x = Math.round(xPos);
        root.persistentStateEntry.y = Math.round(yPos);
        root.persistentStateEntry.width = 0;
        root.persistentStateEntry.height = 0;
    }

    PerfSampler {
        id: hudSampler
        active: root.visible
    }
    // IPC `perfMonitor cycleGpu` reaches the live HUD's sampler through here.
    Component.onCompleted: OverlayContext.perfSampler = hudSampler
    Component.onDestruction: {
        if (OverlayContext.perfSampler === hudSampler)
            OverlayContext.perfSampler = null;
    }

    contentItem: PerfMonitorContent {
        sampler: hudSampler
    }
}
