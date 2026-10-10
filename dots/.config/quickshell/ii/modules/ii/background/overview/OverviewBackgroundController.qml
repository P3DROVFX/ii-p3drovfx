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
    // The lock's own effect reuses this controller while the screen is locked.
    // The scrolling overview's Gnome lock-in does not apply - there is no
    // overview UI on screen to land on - and window captures must never start
    // under a session lock.
    property bool lockDriven: false
    readonly property bool isOverviewAlwaysActive: Config.options.background.useBackgroundOverviewAlways ?? false

    required property real screenWidth
    required property real screenHeight
    required property real wallpaperWidth
    required property real wallpaperHeight
    required property real baseWallpaperScale
    required property real parallaxX
    required property real parallaxY

    readonly property bool barVertical: BarPlacement.vertical
    readonly property bool barBottom: BarPlacement.bottom
    // Match the space reserver used by BarWindow.  `barHeight` includes both
    // floating-bar gaps, while the compositor reserves only one outer gap;
    // using the former moved the overview's scale origin away from the actual
    // usable viewport whenever the horizontal bar was at the top or bottom.
    readonly property real barSize: barVertical
        ? Appearance.sizes.baseVerticalBarWidth + (BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
        : Appearance.sizes.baseBarHeight + (BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
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
    readonly property real centeredParallaxX: -(wallpaperPlaneWidth - screenWidth) / 2
    readonly property real centeredParallaxY: -(wallpaperPlaneHeight - screenHeight) / 2
    property real wallpaperDisplacementX: videoEffectsDisabled ? 0 : (parallaxX - centeredParallaxX)
    property real wallpaperDisplacementY: videoEffectsDisabled ? 0 : (parallaxY - centeredParallaxY)
    property real animationScaleOriginX: centeredScaleOriginX
    property real animationScaleOriginY: centeredScaleOriginY

    function captureScaleOrigin() {
        animationScaleOriginX = useWallpaperParallax ? parallaxScaleOriginX : centeredScaleOriginX;
        animationScaleOriginY = useWallpaperParallax ? parallaxScaleOriginY : centeredScaleOriginY;
    }

    onActiveChanged: {
        if (active)
            captureScaleOrigin();
    }

    // Prepare the next silhouette only after the closing animation finishes.
    // Reopening mid-close must reverse the same shape, not replace it on screen.
    onProgressChanged: {
        if (!active && progress === 0 && isMaterialShape)
            pickRandomShape();
    }

    Component.onCompleted: {
        if (active)
            captureScaleOrigin();
        if (isMaterialShape)
            pickRandomShape();
    }

    /**
     * The scrolling overview's workspace frame this monitor zooms into.
     *
     * With Hyprland's scrolling layout the overview is locked to the Gnome-like
     * zoom, aimed at the active workspace's row instead of the screen centre:
     * the wallpaper plane (and the window captures, which share its transform)
     * shrinks exactly onto that row's frame, where the scrolling overview then
     * draws the same wallpaper and windows. Published by the overview through
     * GlobalStates; empty until it has laid its rows out once.
     */
    readonly property bool scrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    property rect scrollingTarget: Qt.rect(0, 0, 0, 0)
    /** On-screen corner radius of the scrolling overview's frames. */
    property real scrollingFrameRadius: Appearance.rounding.normal + 4
    readonly property bool scrollingAimed: scrollingLayout && scrollingTarget.width > 1 && screenWidth > 0
        && scrollingTarget.width < screenWidth
    readonly property real scrollingScale: scrollingAimed ? scrollingTarget.width / screenWidth : 1.0
    /**
     * Fully open, the overview's own rows carry the wallpaper and windows, so
     * the plane and the captures step aside (the rows can scroll away from
     * where the plane landed). Closing brings them back at the row's place.
     */
    readonly property bool scrollingHandedOff: scrollingAimed && active && progress >= 0.999

    readonly property real scaleOriginX: scrollingAimed ? scrollingTarget.x / (1.0 - scrollingScale)
        : realGnomeAimed ? realGnomeTarget.x / (1.0 - realGnomeScale) : centeredScaleOriginX
    readonly property real scaleOriginY: scrollingAimed ? scrollingTarget.y / (1.0 - scrollingScale)
        : realGnomeAimed ? realGnomeTarget.y / (1.0 - realGnomeScale) : centeredScaleOriginY

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
        const persistentAllowedStyles = ["gnome", "real-gnome", "camera-push", "card-lift", "desaturate", "directional", "material-shape"];
        const knownStyles = isOverviewAlwaysActive
            ? persistentAllowedStyles
            : ["gnome", "real-gnome", "soft-focus", "camera-push", "depth", "card-lift", "desaturate", "directional", "material-shape"];
        if (knownStyles.indexOf(root.style) >= 0)
            return root.style;

        if (isOverviewAlwaysActive)
            return "gnome";

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
        if (root.scrollingLayout && !root.isOverviewAlwaysActive && !root.lockDriven)
            return "gnome";
        // Real Gnome is the Gnome-like pipeline plus the `isRealGnome`
        // refinements below, so every consumer of "gnome" serves both.
        if (!root.videoEffectsDisabled)
            return root.resolvedStyle === "real-gnome" ? "gnome" : root.resolvedStyle;
        return (root.resolvedStyle === "camera-push" || root.isOverviewAlwaysActive) ? "camera-push" : "soft-focus";
    }

    readonly property bool isGnomeLike: effectiveStyle === "gnome"

    /**
     * Real Gnome: the Gnome-like zoom reworked after GNOME Shell's overview.
     *
     * The plane lands in the free area under the workspace thumbnails instead
     * of the screen centre, the windows spread into a non-overlapping picker
     * (OverviewWindowTransition), the motion eases without overshoot and the
     * backing gains GNOME's vignette. The scrolling layout, the lock and the
     * always-on overview keep plain Gnome Like.
     */
    readonly property bool isRealGnome: resolvedStyle === "real-gnome" && isGnomeLike
        && !scrollingLayout && !lockDriven && !isOverviewAlwaysActive
    /** Free area under the thumbnails (screen coordinates), published by the overview. */
    property rect realGnomeArea: Qt.rect(0, 0, 0, 0)
    // Until the overview has laid out once, estimate the search above the plane
    // (field plus the now-playing card it can show).
    readonly property rect realGnomeFallbackArea: {
        // Plus the workspace indicator's strip at the bottom.
        const chrome = 200;
        const indicator = 40;
        return barBottom && !barVertical
            ? Qt.rect(padLeft, padTop, screenWidth - padLeft - padRight, screenHeight - padTop - padBottom - chrome - indicator)
            : Qt.rect(padLeft, padTop + chrome, screenWidth - padLeft - padRight, screenHeight - padTop - padBottom - chrome - indicator);
    }
    readonly property rect realGnomeTarget: {
        if (!isRealGnome || screenWidth <= 0 || screenHeight <= 0)
            return Qt.rect(0, 0, 0, 0);
        const area = realGnomeArea.width > 1 && realGnomeArea.height > 1 ? realGnomeArea : realGnomeFallbackArea;
        const margin = Appearance.sizes.elevationMargin * 2;
        const s = Math.max(0.3, Math.min(gnomeTargetScale,
            (area.width - margin * 2) / screenWidth, (area.height - margin * 2) / screenHeight));
        const w = screenWidth * s;
        const h = screenHeight * s;
        return Qt.rect(area.x + (area.width - w) / 2, area.y + (area.height - h) / 2, w, h);
    }
    readonly property bool realGnomeAimed: realGnomeTarget.width > 1 && realGnomeTarget.width < screenWidth
    readonly property real realGnomeScale: realGnomeAimed ? realGnomeTarget.width / screenWidth : gnomeTargetScale
    /** On-screen corner radius of the workspace plane. */
    readonly property real realGnomeRadius: Appearance.rounding.large

    // GNOME eases without overshoot. Opening uses the compositor's own window
    // curve and speed (Settings -> Windows), closing is shorter and lands
    // softly on the real windows.
    readonly property real realGnomeWindowSpeed: Math.max(1, Math.min(10, Number(Config.options.appearance.appLaunchAnimation.speed) || 4))
    readonly property int realGnomeOpenDuration: Math.round(realGnomeWindowSpeed * 100 * Appearance.animMultiplier)
    readonly property int realGnomeCloseDuration: Math.round(realGnomeWindowSpeed * 75 * Appearance.animMultiplier)
    readonly property var realGnomeOpenCurve: [0.22, 1, 0.36, 1, 1, 1]
    readonly property var realGnomeCloseCurve: [0.25, 0.46, 0.45, 0.94, 1, 1]
    /** GNOME's radial shade over the blurred backing. */
    readonly property real vignetteAmount: isRealGnome ? progress : 0.0
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
    readonly property bool useCompositorBlur: effectiveStyle === "soft-focus" && !videoEffectsDisabled && !isOverviewAlwaysActive

    readonly property real targetScale: {
        switch (effectiveStyle) {
        case "gnome":
            return scrollingAimed ? scrollingScale : isRealGnome ? realGnomeScale : gnomeTargetScale;
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

    /// Set while a touchpad gesture is holding the overview part-way open: the zoom then
    /// sits where the fingers are instead of running on its own clock.
    property bool held: false
    property real heldProgress: 0

    /// Held at 0 on open until the window captures have taken over (see OverviewWindowTransition).
    property bool openHold: false
    property real progress: root.held ? root.heldProgress : (active && !root.openHold ? 1.0 : 0.0)
    Behavior on progress {
        enabled: !root.isOverviewAlwaysActive && !root.held
        // Bound to `active`: the Behavior reads them after the target flips,
        // so each direction runs on its own curve.
        NumberAnimation {
            duration: root.isRealGnome
                ? (root.active ? root.realGnomeOpenDuration : root.realGnomeCloseDuration)
                : Appearance.animation.elementMove.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.isRealGnome
                ? (root.active ? root.realGnomeOpenCurve : root.realGnomeCloseCurve)
                : Appearance.animation.elementMove.bezierCurve
        }
    }

    readonly property real scale: 1.0 + (safeTargetScale - 1.0) * progress

    readonly property real scaleProgress: {
        if (!isGnomeLike)
            return progress;
        const denominator = 1.0 - (scrollingAimed ? scrollingScale : isRealGnome ? realGnomeScale : gnomeTargetScale);
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

    // The plane's radius is drawn before its scale, so the scrolling frame's
    // on-screen radius is divided back out of the current scale.
    readonly property real cornerRadius: scrollingAimed
        ? progress * scrollingFrameRadius / Math.max(0.05, scale)
        : isRealGnome
        ? progress * realGnomeRadius / Math.max(0.05, scale)
        : progress * (effectiveStyle === "gnome" ? Appearance.rounding.windowRounding : effectiveStyle === "card-lift" ? Appearance.rounding.large : 0)
    readonly property real borderOpacity: isGnomeLike && !scrollingLayout && !isRealGnome ? scaleProgress : 0.0
    readonly property real shadowAmount: (isGnomeLike ? scaleProgress : progress) * ((effectiveStyle === "gnome" || effectiveStyle === "card-lift" || (effectiveStyle === "material-shape" && (Config.options.background.materialShapeShadow === true))) ? 1.0 : 0.0)

    readonly property bool followWidgetsScale: ["gnome", "camera-push", "depth", "card-lift"].indexOf(effectiveStyle) >= 0
    readonly property bool followWidgetsTranslation: effectiveStyle === "directional"
    readonly property real opacityMultiplier: 1.0
    readonly property bool useWallpaperParallax: effectiveStyle !== "soft-focus"
    readonly property bool useColorAdjustments: progress > 0.001 && (saturation < 0.999 || brightness < 0.999)

    readonly property string windowTransitionMode: {
        if (root.lockDriven)
            return "none";
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
