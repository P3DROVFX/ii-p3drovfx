import QtQuick
import qs.services
import qs.modules.common

Item {
    id: overviewZoomController
    visible: false

    // Inputs
    required property bool wallpaperZoomedOut
    required property real minSafeScale
    required property real zoomOutCoverScale
    required property int screenWidth
    required property int screenHeight

    // Margins/origins
    readonly property bool barVertical: Config.options.bar.vertical
    readonly property bool barBottom: Config.options.bar.bottom
    readonly property int barSize: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
    readonly property int gap: Appearance.gapsOut

    readonly property int padLeft: barVertical && !barBottom ? barSize : gap
    readonly property int padRight: barVertical && barBottom ? barSize : gap
    readonly property int padTop: !barVertical && !barBottom ? barSize : gap
    readonly property int padBottom: !barVertical && barBottom ? barSize : gap

    readonly property real scaleOriginX: padLeft + (screenWidth - padLeft - padRight) / 2
    readonly property real scaleOriginY: padTop + (screenHeight - padTop - padBottom) / 2

    // Scale calculation
    property real scaleValue: {
        if (!wallpaperZoomedOut)
            return 1.0;
        if (Config.options.background.zoomOutStyle === 2)
            return 1.15;
        // Style 1: use zoom-to-fill to cover screen without mirrored tiles
        if (Config.options.background.zoomOutStyle === 1)
            return Math.max(0.85, zoomOutCoverScale);
        return Math.max(0.85, minSafeScale * 0.85);
    }
    Behavior on scaleValue {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    readonly property real scaleProgress: {
        let startScale = 1.0;
        let targetScale = Math.max(0.85, minSafeScale * 0.85);
        if (startScale === targetScale)
            return 0.0;
        return Math.max(0.0, Math.min(1.0, (startScale - scaleValue) / (startScale - targetScale)));
    }
}
