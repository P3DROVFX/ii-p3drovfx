import QtQuick
import qs.modules.common

// One instance belongs to one monitor.  All overview background consumers read
// the same animated progress and the same semantic preset outputs from it.
Item {
    id: root
    visible: false

    required property bool active
    property string style: ""
    property int legacyStyle: Config.options.background.zoomOutStyle
    property bool videoEffectsDisabled: false
    property string wallpaperPath: ""
    property bool wallpaperSafetyTriggered: false

    required property real screenWidth
    required property real screenHeight
    required property real wallpaperWidth
    required property real wallpaperHeight
    required property real baseWallpaperScale
    required property real parallaxX
    required property real parallaxY

    readonly property bool barVertical: BarPlacement.vertical
    readonly property bool barBottom: BarPlacement.bottom
    readonly property real barSize: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
    readonly property real gap: Appearance.gapsOut

    readonly property real padLeft: barVertical && !barBottom ? barSize : gap
    readonly property real padRight: barVertical && barBottom ? barSize : gap
    readonly property real padTop: !barVertical && !barBottom ? barSize : gap
    readonly property real padBottom: !barVertical && barBottom ? barSize : gap

    readonly property real centeredScaleOriginX: padLeft + (screenWidth - padLeft - padRight) / 2
    readonly property real centeredScaleOriginY: padTop + (screenHeight - padTop - padBottom) / 2

    readonly property real wallpaperToScreenRatio: {
        if (wallpaperWidth <= 0 || wallpaperHeight <= 0 || screenWidth <= 0 || screenHeight <= 0)
            return 1.0;
        return Math.min(wallpaperWidth / screenWidth, wallpaperHeight / screenHeight);
    }

    readonly property real wallpaperPlaneWidth: {
        if (wallpaperToScreenRatio <= 0 || baseWallpaperScale <= 0)
            return 0;
        return wallpaperWidth / wallpaperToScreenRatio * baseWallpaperScale;
    }

    readonly property real wallpaperPlaneHeight: {
        if (wallpaperToScreenRatio <= 0 || baseWallpaperScale <= 0)
            return 0;
        return wallpaperHeight / wallpaperToScreenRatio * baseWallpaperScale;
    }

    // Non-Gnome presets can preserve the wallpaper's current parallax center
    // as their scale origin. Gnome-like intentionally keeps its original
    // monitor-centered origin below.
    readonly property real parallaxScaleOriginX: wallpaperPlaneWidth / 2 + parallaxX
    readonly property real parallaxScaleOriginY: wallpaperPlaneHeight / 2 + parallaxY
    property real animationScaleOriginX: centeredScaleOriginX
    property real animationScaleOriginY: centeredScaleOriginY

    function captureScaleOrigin() {
        animationScaleOriginX = useWallpaperParallax ? parallaxScaleOriginX : centeredScaleOriginX;
        animationScaleOriginY = useWallpaperParallax ? parallaxScaleOriginY : centeredScaleOriginY;
    }

    onActiveChanged: {
        if (active) {
            captureScaleOrigin();
            if (isMaterialShape)
                pickRandomShape();
        }
    }

    Component.onCompleted: {
        if (active) {
            captureScaleOrigin();
            if (isMaterialShape)
                pickRandomShape();
        }
    }

    readonly property real scaleOriginX: centeredScaleOriginX
    readonly property real scaleOriginY: centeredScaleOriginY

    // Minimum transform that keeps the actual wallpaper covering the visible
    // monitor area.  This is the single source used by non-backing styles,
    // avoiding silent arbitrary scale fallbacks.
    readonly property real overviewCoverScale: {
        if (wallpaperPlaneWidth <= 0 || wallpaperPlaneHeight <= 0 || screenWidth <= 0 || screenHeight <= 0)
            return 1.0;
        const translationPadding = effectiveStyle === "directional" ? 0.015 : 0.0;
        const visibleWidth = screenWidth * (1.0 + translationPadding);
        const visibleHeight = screenHeight * (1.0 + translationPadding);
        return Math.max(visibleWidth / wallpaperPlaneWidth, visibleHeight / wallpaperPlaneHeight);
    }

    // The original Gnome-like animation scales to 85% of the minimum safe
    // coverage instead of using a fixed preset scale.
    readonly property real gnomeTargetScale: Math.max(0.85, overviewCoverScale * 0.85)

    readonly property string resolvedStyle: {
        const knownStyles = ["gnome", "soft-focus", "camera-push", "depth", "card-lift", "desaturate", "directional", "material-shape"];
        if (knownStyles.indexOf(root.style) >= 0)
            return root.style;

        switch (root.legacyStyle) {
        case 0:
            return "gnome";
        case 1:
            return "soft-focus";
        case 2:
        default:
            return "camera-push";
        }
    }

    // Animated wallpapers cannot safely use image-based effects. Keep their
    // fallback limited to the two styles that operate on the existing plane.
    readonly property string effectiveStyle: {
        if (!root.videoEffectsDisabled)
            return root.resolvedStyle;
        return root.resolvedStyle === "camera-push" ? "camera-push" : "soft-focus";
    }

    readonly property bool isGnomeLike: effectiveStyle === "gnome"
    readonly property bool isMaterialShape: effectiveStyle === "material-shape"

    readonly property var availableMaterialShapes: [
        "Flower",
        "Cookie9Sided",
        "Cookie12Sided",
        "Cookie7Sided",
        "Cookie6Sided",
        "SoftBurst",
        "Burst",
        "Sunny",
        "VerySunny",
        "Puffy",
        "Clover4Leaf",
        "Clover8Leaf",
        "Boom",
        "SoftBoom",
        "Bun",
        "Gem",
        "ClamShell",
        "Heart"
    ]
    property string currentMaterialShape: "Flower"
    property real shapeInitialAngle: -18.0

    function pickRandomShape() {
        const list = availableMaterialShapes;
        const idx = Math.floor(Math.random() * list.length);
        currentMaterialShape = list[idx];
        shapeInitialAngle = (Math.random() > 0.5 ? 1 : -1) * (14 + Math.random() * 8);
    }

    readonly property real shapeTargetScale: Math.max(0.1, Config.options.background.materialShapeScale ?? 1.0)
    readonly property real maskTargetDiameter: Math.min(screenWidth, screenHeight) * 0.72
    readonly property real initialMaskScale: Math.max(3.6, Math.hypot(screenWidth, screenHeight) / (Math.max(1, maskTargetDiameter) * 0.40))
    readonly property real maskScale: initialMaskScale + (shapeTargetScale - initialMaskScale) * progress
    readonly property real maskRotation: shapeInitialAngle * (1.0 - progress)
    readonly property real wallpaperContentScale: isMaterialShape ? (1.0 - 0.06 * progress) : 1.0

    // Gnome restores the original blurred backing around the rounded central
    // wallpaper plane. Card Lift has its own separate backing blur policy.
    readonly property bool useBackingImage: (effectiveStyle === "gnome" || effectiveStyle === "card-lift") && !videoEffectsDisabled
    readonly property bool useBackingBlur: (effectiveStyle === "gnome" || effectiveStyle === "card-lift") && !videoEffectsDisabled
    // Soft Focus is the only preset that intentionally blurs the full scene.
    // Depth gets its separation from scale, color and dimming instead.
    readonly property bool useCompositorBlur: effectiveStyle === "soft-focus" && !videoEffectsDisabled

    readonly property real targetScale: {
        switch (effectiveStyle) {
        case "gnome":
            return gnomeTargetScale;
        case "soft-focus":
            return 1.035;
        case "camera-push":
            return 1.09;
        case "depth":
            return 0.96;
        case "card-lift":
            return 0.92;
        case "desaturate":
            return 0.985;
        case "directional":
            return 0.97;
        case "material-shape":
            return 1.0;
        default:
            return 1.0;
        }
    }

    readonly property real safeTargetScale: (useBackingImage || useCompositorBlur || isMaterialShape) ? targetScale : Math.max(targetScale, overviewCoverScale)

    property real progress: active ? 1.0 : 0.0
    Behavior on progress {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    readonly property real scale: 1.0 + (safeTargetScale - 1.0) * progress

    readonly property real scaleProgress: {
        if (!isGnomeLike)
            return progress;
        const denominator = 1.0 - gnomeTargetScale;
        if (Math.abs(denominator) < 0.0001)
            return 0.0;
        return Math.max(0.0, Math.min(1.0, (1.0 - scale) / denominator));
    }

    readonly property real translateX: {
        if (effectiveStyle !== "directional")
            return 0;
        return progress * (barVertical ? (barBottom ? -screenWidth : screenWidth) * 0.015 : 0);
    }

    readonly property real translateY: {
        if (effectiveStyle !== "directional")
            return 0;
        return progress * (!barVertical ? (barBottom ? -screenHeight : screenHeight) * 0.015 : 0);
    }

    readonly property real blurAmount: progress * (useBackingBlur ? 0.7 : useCompositorBlur ? 0.8 : 0.0)

    readonly property real dimAmount: {
        let amount = 0.0;
        switch (effectiveStyle) {
        case "gnome":
            amount = 0.24;
            break;
        case "soft-focus":
            amount = 0.18;
            break;
        case "card-lift":
            amount = 0.16;
            break;
        case "depth":
            amount = 0.05;
            break;
        case "directional":
            amount = 0.06;
            break;
        default:
            amount = 0.0;
        }
        return progress * amount;
    }

    readonly property real saturation: {
        switch (effectiveStyle) {
        case "soft-focus":
            return 0.82 + (1.0 - 0.82) * (1.0 - progress);
        case "depth":
            return 0.94 + (1.0 - 0.94) * (1.0 - progress);
        case "camera-push":
            return 0.88 + (1.0 - 0.88) * (1.0 - progress);
        case "desaturate":
            return 0.50 + (1.0 - 0.50) * (1.0 - progress);
        default:
            return 1.0;
        }
    }

    readonly property real brightness: {
        switch (effectiveStyle) {
        case "camera-push":
            return 0.82 + (1.0 - 0.82) * (1.0 - progress);
        case "depth":
            return 0.96 + (1.0 - 0.96) * (1.0 - progress);
        case "desaturate":
            return 0.82 + (1.0 - 0.82) * (1.0 - progress);
        default:
            return 1.0;
        }
    }

    readonly property real cornerRadius: progress * (effectiveStyle === "gnome" ? Appearance.rounding.windowRounding : effectiveStyle === "card-lift" ? Appearance.rounding.large : 0)
    readonly property real borderOpacity: isGnomeLike ? scaleProgress : 0.0
    readonly property real shadowAmount: (isGnomeLike ? scaleProgress : progress) * ((effectiveStyle === "gnome" || effectiveStyle === "card-lift" || (effectiveStyle === "material-shape" && (Config.options.background.materialShapeShadow === true))) ? 1.0 : 0.0)

    readonly property bool followWidgetsScale: ["gnome", "camera-push", "depth", "card-lift"].indexOf(effectiveStyle) >= 0
    readonly property bool followWidgetsTranslation: effectiveStyle === "directional"
    readonly property real opacityMultiplier: 1.0
    readonly property bool useWallpaperParallax: effectiveStyle !== "soft-focus"
    readonly property bool useColorAdjustments: progress > 0.001 && (saturation < 0.999 || brightness < 0.999)

    readonly property string windowTransitionMode: {
        if (!Config.options.background.windowZoomOnOverview)
            return "none";
        switch (effectiveStyle) {
        case "gnome":
            return "scale-with-background";
        case "soft-focus":
            return "settle";
        default:
            return "none";
        }
    }
}
