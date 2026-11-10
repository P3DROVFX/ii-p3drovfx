import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.functions
import qs.modules.settings.configs.colors

/**
 * The lock wallpaper with the lock's treatments on it, at any size: blur (with the
 * dimming layer LockBlur lays over it), desaturation, the primary colour wash and
 * the vignette — the same stack, in the same order, as the real lock. Values are
 * the effective ones (0 = off); `screenScale` is this item's width over the
 * screen's, so a blur radius set in screen pixels looks the same when shrunk.
 */
Item {
    id: root

    /// Screen pixels, 0–50.
    property real blurRadius: 0
    /// 0–1 each.
    property real desaturation: 0
    property real colorWash: 0
    property real vignette: 0
    property real screenScale: 0.4
    property bool animated: true

    readonly property bool separateWallpaper: Config.options.background.useSeparateLockscreenWallpaper

    // Eased copies, so a slider or a preset glides the picture into its new look.
    property real _blur: root.blurRadius
    property real _desaturation: root.desaturation
    property real _wash: root.colorWash
    property real _vignette: root.vignette
    Behavior on _blur {
        enabled: root.animated && !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on _desaturation {
        enabled: root.animated && !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on _wash {
        enabled: root.animated && !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on _vignette {
        enabled: root.animated && !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    ColorsWallpaperImage {
        id: picture
        anchors.fill: parent
        targetMode: root.separateWallpaper ? "lockscreen" : "desktop"
    }

    ShaderEffectSource {
        id: pictureSource
        anchors.fill: parent
        sourceItem: picture
        hideSource: true
        visible: false
    }

    // LockBlur blurs a half-size capture, so its radius spans twice as many screen pixels.
    MultiEffect {
        anchors.fill: parent
        source: pictureSource
        autoPaddingEnabled: false
        blurEnabled: root._blur > 0.1
        blurMax: 48
        blur: Math.min(1, root._blur * 2 * root.screenScale / 48)
        saturation: -root._desaturation
    }

    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
        opacity: Math.min(1, root._blur / 5)
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colPrimary
        opacity: root._wash
    }

    Canvas {
        id: vignetteCanvas
        anchors.fill: parent
        opacity: root._vignette
        visible: opacity > 0.001
        onPaint: {
            const ctx = getContext("2d");
            const w = width;
            const h = height;
            if (w <= 0 || h <= 0)
                return;
            ctx.clearRect(0, 0, w, h);
            const cx = w / 2;
            const cy = h / 2;
            const outer = Math.hypot(cx, cy);
            const grad = ctx.createRadialGradient(cx, cy, outer * 0.35, cx, cy, outer);
            grad.addColorStop(0.0, "rgba(0, 0, 0, 0)");
            grad.addColorStop(0.5, "rgba(0, 0, 0, 0.3)");
            grad.addColorStop(0.8, "rgba(0, 0, 0, 0.7)");
            grad.addColorStop(1.0, "rgba(0, 0, 0, 0.95)");
            ctx.fillStyle = grad;
            ctx.fillRect(0, 0, w, h);
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onAvailableChanged: if (available) requestPaint()
    }
}
