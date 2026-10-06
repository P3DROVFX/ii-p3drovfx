import QtQuick
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
        readonly property int overlaySpan: barSize + 100
        // Wallpaper captured past the band's end, so the kernel there samples
        // real pixels instead of clamping onto the last row (a smeared seam
        // right where the blur should be fading out). Two strong radii.
        readonly property int padding: 2 * strongRadius * 2
        readonly property int captureSpan: overlaySpan + padding
        readonly property int captureX: isVertical ? (isBottom ? parent.width - captureSpan : 0) : 0
        readonly property int captureY: !isVertical ? (isBottom ? parent.height - captureSpan : 0) : 0
        readonly property int captureW: isVertical ? captureSpan : parent.width
        readonly property int captureH: !isVertical ? captureSpan : parent.height
        // Blur radii at the capture's half resolution: ~20 px and ~48 px on screen.
        readonly property int mediumRadius: 10
        readonly property int strongRadius: 24

        Item {
            x: barBlurOverlay.captureX
            y: barBlurOverlay.captureY
            width: barBlurOverlay.captureW
            height: barBlurOverlay.captureH

            // Half resolution: the band is about to be blurred by tens of
            // pixels, so the lost detail never shows and the kernels cost a quarter.
            ShaderEffectSource {
                id: barBlurCapture
                sourceItem: barOverlayRoot.sourceItem
                sourceRect: Qt.rect(barBlurOverlay.captureX, barBlurOverlay.captureY,
                    barBlurOverlay.captureW, barBlurOverlay.captureH)
                width: Math.max(1, Math.round(barBlurOverlay.captureW / 2))
                height: Math.max(1, Math.round(barBlurOverlay.captureH / 2))
                textureSize: Qt.size(width, height)
                // Only capture while the overlay is actually on screen.
                live: barBlurOverlay.visible
                hideSource: false
                smooth: true
                visible: false
            }

            // GaussianBlur, not MultiEffect: MultiEffect's blur tops out low
            // and its downsampled levels band at large radii. transparentBorder
            // off clamps at the screen edges instead of fading to transparent.
            GaussianBlur {
                id: mediumBlur
                width: barBlurCapture.width
                height: barBlurCapture.height
                source: barBlurCapture
                radius: barBlurOverlay.mediumRadius
                samples: barBlurOverlay.mediumRadius * 2 + 1
                transparentBorder: false
                visible: barBlurOverlay.visible
            }

            GaussianBlur {
                id: strongBlur
                width: barBlurCapture.width
                height: barBlurCapture.height
                source: barBlurCapture
                radius: barBlurOverlay.strongRadius
                samples: barBlurOverlay.strongRadius * 2 + 1
                transparentBorder: false
                visible: barBlurOverlay.visible
            }

            ShaderEffectSource {
                id: mediumBlurTexture
                sourceItem: mediumBlur
                hideSource: true
                live: barBlurOverlay.visible
                smooth: true
                visible: false
            }

            ShaderEffectSource {
                id: strongBlurTexture
                sourceItem: strongBlur
                hideSource: true
                live: barBlurOverlay.visible
                smooth: true
                visible: false
            }

            // Full strength under the whole bar, then a progressive fade past
            // it (see barBlur.frag). The padding is drawn transparent.
            ShaderEffect {
                anchors.fill: parent
                property var mediumBlur: mediumBlurTexture
                property var strongBlur: strongBlurTexture
                readonly property real axisLength: Math.max(1, barBlurOverlay.captureSpan)
                // From 60% of the bar on: the widgets sit mid-bar, the rim needs less.
                property real bandSolid: barBlurOverlay.barSize * 0.6 / axisLength
                property real bandSize: barBlurOverlay.overlaySpan / axisLength
                property real alongY: barBlurOverlay.isVertical ? 0 : 1
                property real fromEnd: barBlurOverlay.isBottom ? 1 : 0
                fragmentShader: Qt.resolvedUrl("../shaders/barBlur.frag.qsb")
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

        readonly property int overlaySpan: barSize + 100

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
                    color: !barGradientOverlay.isBottom ? Qt.rgba(0,0,0,0.45) : "transparent"
                }
                GradientStop {
                    position: !barGradientOverlay.isBottom ? 0.55 : 0.45
                    color: Qt.rgba(0,0,0,0.15)
                }
                GradientStop {
                    position: 1.0
                    color: !barGradientOverlay.isBottom ? "transparent" : Qt.rgba(0,0,0,0.45)
                }
            }
        }
    }
}
