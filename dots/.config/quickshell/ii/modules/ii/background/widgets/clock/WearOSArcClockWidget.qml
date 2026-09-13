import QtQuick
import qs
import qs.modules.common
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "wearos_arc_clock"

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly" || (Config.options.lock.centerWidget === "wearos_arc_clock")
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    readonly property real contentScale: (Config.options.background.widgets.wearos_arc_clock.widgetSize ?? 100) / 100.0
    implicitWidth: 240 * contentScale
    implicitHeight: 240 * contentScale

    // Supersampled: WearOSArcClock is a Canvas, so it rasterises at its own
    // item size. Without this it would be a stretched bitmap once the widget
    // grows — either by the size slider or by the corner grip.
    Supersampled {
        anchors.fill: parent
        factor: root.renderScale

        WearOSArcClock {
            id: clockContent
            anchors.fill: parent
        }
    }
}
