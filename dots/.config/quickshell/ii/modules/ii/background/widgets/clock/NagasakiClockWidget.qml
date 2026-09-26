import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_nagasaki"

    implicitWidth: 240
    implicitHeight: 240

    property bool wallpaperSafetyTriggered: false

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    needsColText: false

    NagasakiClock {}
}
