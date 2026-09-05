import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common

Item {
    id: barOverlayRoot
    anchors.fill: parent

    // The source must use this overlay's screen coordinate space. Keeping the
    // overlay outside WallpaperImage makes its fade fixed while this capture
    // still reflects the wallpaper's animated pixels.
    required property var sourceItem
    required property int screenWidth
    required property int screenHeight

    readonly property bool shouldShow: Config.options.bar.barBackgroundStyle === 0
        && Config.options.bar.transparentGlow
        && GlobalStates.barOpen
        && !GlobalStates.lockLookActive

    Item {
        id: barBlurOverlay
        anchors.fill: parent

        visible: opacity > 0.001
        opacity: barOverlayRoot.shouldShow ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        readonly property bool isVertical: BarPlacement.vertical
        readonly property bool isBottom: BarPlacement.bottom
        readonly property int barSize: isVertical
            ? Appearance.sizes.verticalBarWidth
            : Appearance.sizes.barHeight
        readonly property int overlaySpan: barSize + 80
        readonly property int overlayX: isVertical ? (isBottom ? parent.width - overlaySpan : 0) : 0
        readonly property int overlayY: !isVertical ? (isBottom ? parent.height - overlaySpan : 0) : 0
        readonly property int overlayW: isVertical ? overlaySpan : parent.width
        readonly property int overlayH: !isVertical ? overlaySpan : parent.height

        Item {
            x: barBlurOverlay.overlayX
            y: barBlurOverlay.overlayY
            width: barBlurOverlay.overlayW
            height: barBlurOverlay.overlayH
            // Released while hidden so the mask FBO isn't held for the whole session
            layer.enabled: barBlurOverlay.visible
            layer.effect: OpacityMask {
                maskSource: barBlurGradientMask
            }

            ShaderEffectSource {
                id: barBlurShaderSource
                sourceItem: barOverlayRoot.sourceItem
                sourceRect: Qt.rect(barBlurOverlay.overlayX, barBlurOverlay.overlayY,
                    barBlurOverlay.overlayW, barBlurOverlay.overlayH)
                width: barBlurOverlay.overlayW
                height: barBlurOverlay.overlayH
                // Only capture while the overlay is actually on screen. A permanently
                // live full-width source feeds the blur below every frame, which is
                // pure wasted fill rate at high resolutions when the overlay is hidden.
                live: barBlurOverlay.visible
                hideSource: false
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: barBlurShaderSource
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: 0.35
            }
        }

        Item {
            id: barBlurGradientMask
            x: barBlurOverlay.overlayX
            y: barBlurOverlay.overlayY
            width: barBlurOverlay.overlayW
            height: barBlurOverlay.overlayH
            opacity: 0

            Canvas {
                anchors.fill: parent
                readonly property bool isVertical: barBlurOverlay.isVertical
                readonly property bool isBottom: barBlurOverlay.isBottom

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();

                    var gradient;
                    if (isVertical) {
                        gradient = isBottom
                            ? ctx.createLinearGradient(0, 0, width, 0)
                            : ctx.createLinearGradient(width, 0, 0, 0);
                    } else {
                        gradient = isBottom
                            ? ctx.createLinearGradient(0, 0, 0, height)
                            : ctx.createLinearGradient(0, height, 0, 0);
                    }

                    gradient.addColorStop(0.0, "rgba(255, 255, 255, 0)");
                    gradient.addColorStop(0.55, "rgba(255, 255, 255, 0.4)");
                    gradient.addColorStop(1.0, "rgba(255, 255, 255, 1)");

                    ctx.fillStyle = gradient;
                    ctx.fillRect(0, 0, width, height);
                }

                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onIsVerticalChanged: requestPaint()
                onIsBottomChanged: requestPaint()
            }
        }
    }

    // Bar gradient overlay
    Item {
        id: barGradientOverlay
        anchors.fill: parent

        visible: opacity > 0.001
        opacity: barOverlayRoot.shouldShow ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        readonly property bool isVertical: BarPlacement.vertical
        readonly property bool isBottom: BarPlacement.bottom
        readonly property int barSize: isVertical
            ? Appearance.sizes.verticalBarWidth
            : Appearance.sizes.barHeight

        readonly property int overlaySpan: barSize + 80

        readonly property int overlayX: isVertical ? (isBottom ? parent.width - overlaySpan : 0) : 0
        readonly property int overlayY: !isVertical ? (isBottom ? parent.height - overlaySpan : 0) : 0
        readonly property int overlayW: isVertical ? overlaySpan : parent.width
        readonly property int overlayH: !isVertical ? overlaySpan : parent.height

        Rectangle {
            x: barGradientOverlay.overlayX
            y: barGradientOverlay.overlayY
            width: barGradientOverlay.overlayW
            height: barGradientOverlay.overlayH

            gradient: Gradient {
                orientation: barGradientOverlay.isVertical ? Gradient.Horizontal : Gradient.Vertical

                GradientStop {
                    position: 0.0
                    color: barGradientOverlay.isVertical
                        ? (barGradientOverlay.isBottom ? "transparent" : Qt.rgba(0,0,0,0.45))
                        : (!barGradientOverlay.isBottom ? Qt.rgba(0,0,0,0.45) : "transparent")
                }
                GradientStop {
                    position: 0.55
                    color: barGradientOverlay.isVertical
                        ? (barGradientOverlay.isBottom ? "transparent" : Qt.rgba(0,0,0,0.15))
                        : (!barGradientOverlay.isBottom ? Qt.rgba(0,0,0,0.15) : "transparent")
                }
                GradientStop {
                    position: 1.0
                    color: barGradientOverlay.isVertical
                        ? (barGradientOverlay.isBottom ? "rgba(0,0,0,0.45)" : "transparent")
                        : (!barGradientOverlay.isBottom ? "transparent" : "rgba(0,0,0,0.45)")
                }
            }
        }
    }
}
