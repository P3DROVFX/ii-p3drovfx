import QtQuick
import qs
import qs.services
import qs.modules.common

Item {
    id: parallaxController
    visible: false

    // Inputs
    required property real movableXSpace
    required property real movableYSpace
    required property int firstWorkspaceId
    required property int lastWorkspaceId
    required property int chunkSize
    required property bool verticalParallax
    required property bool parallaxFrozen
    required property var activeWorkspaceId
    property bool wallpaperCentered: false

    // Intermediate calculations
    readonly property int lower: Math.floor(firstWorkspaceId / chunkSize) * chunkSize
    readonly property int upper: Math.ceil(lastWorkspaceId / chunkSize) * chunkSize
    readonly property int range: Math.max(1, upper - lower)

    readonly property real valueX: {
        let result = 0.5;
        if (Config.options.background.parallax.enableWorkspace && !verticalParallax) {
            let activeId = activeWorkspaceId ?? 1;
            let ratio = ((activeId - lower) / range);
            result = Config.options.background.parallax.invertHorizontal ? (1.0 - ratio) : ratio;
        }
        return result;
    }

    readonly property real sidebarOffsetX: {
        if (!Config.options.background.parallax.enableSidebar)
            return 0;
        return (0.15 * GlobalStates.effectiveRightOpen - 0.15 * GlobalStates.effectiveLeftOpen);
    }

    readonly property real valueY: {
        let result = 0.5;
        if (Config.options.background.parallax.enableWorkspace && verticalParallax) {
            let activeId = activeWorkspaceId ?? 1;
            let ratio = ((activeId - lower) / range);
            result = Config.options.background.parallax.invertVertical ? (1.0 - ratio) : ratio;
        }
        return result;
    }

    readonly property real effectiveValueX: parallaxFrozen ? 0.5 : Math.max(0, Math.min(1, valueX)) + sidebarOffsetX
    readonly property real effectiveValueY: parallaxFrozen ? 0.5 : Math.max(0, Math.min(1, valueY))

    // Outputs
    readonly property real parallaxX: ((GlobalStates.screenLocked && wallpaperCentered) || parallaxFrozen)
        ? -movableXSpace
        : -movableXSpace - (effectiveValueX - 0.5) * 2 * movableXSpace

    readonly property real parallaxY: ((GlobalStates.screenLocked && wallpaperCentered) || parallaxFrozen)
        ? -movableYSpace
        : -movableYSpace - (effectiveValueY - 0.5) * 2 * movableYSpace

    readonly property real centeredX: -movableXSpace
    readonly property real centeredY: -movableYSpace
}
