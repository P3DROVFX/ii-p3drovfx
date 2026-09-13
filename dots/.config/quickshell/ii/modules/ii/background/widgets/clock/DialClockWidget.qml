import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_dial"

    implicitWidth: 240
    implicitHeight: 240

    property bool wallpaperSafetyTriggered: false

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    needsColText: false

    // Supersampled: DialClock is a Canvas, so it rasterises at its own item
    // size. Without this it would be a stretched bitmap once the widget grows.
    Supersampled {
        anchors.fill: parent
        factor: root.renderScale

        DialClock {
            anchors.fill: parent
        }
    }
}
