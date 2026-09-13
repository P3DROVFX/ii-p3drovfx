pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.functions

// Full-bleed artwork for the Immersive frontend. The sharp cover dissolves
// horizontally into a blurred copy of itself, so the side panels sit on the
// cover's own colours instead of on a separate surface.
//
// layout "side":  the whole square cover at full height, beside the panels
//                 (centred when they are hidden).
// layout "cover": the cover cropped to fill the screen.
Item {
    id: root
    property string source: ""
    property string layout: "side"
    /// 0 = side panels hidden, 1 = shown.
    property real panelProgress: 1
    property bool videoActive: false
    property color tint: Appearance.colors.colPrimary
    property color shade: Appearance.m3colors.m3scrim
    /// Palette colour lightly tinting the field beside the whole cover ("side").
    property color fieldColor: tint
    /// Darkening over the blurred field beside the whole cover ("side"); brighter
    /// covers get more on top of this.
    property real fieldShade: 0.4

    readonly property color tintedShade: ColorUtils.mix(shade, tint, 0.78)
    readonly property real tintLuminance: ColorUtils.relativeLuminance(tint)
    property real coverProgress: layout === "cover" ? 1 : 0
    property real artOpacity: videoActive ? 0 : 1

    readonly property int blurTextureSize: 512

    function cropRect(aspect, size) {
        const s = size ?? root.blurTextureSize;
        if (!(aspect > 0))
            return Qt.rect(0, 0, s, s);
        if (aspect >= 1) {
            const h = s / aspect;
            return Qt.rect(0, (s - h) / 2, s, h);
        }
        const w = s * aspect;
        return Qt.rect((s - w) / 2, 0, w, s);
    }
    readonly property int fieldTextureSize: 256

    // Track changes -------------------------------------------------------------
    // The art decodes asynchronously, so swapping `source` directly flashes an
    // empty frame. Instead the current art is frozen into `previousFrame`, the new
    // source is loaded underneath, and the frozen frame fades out once every
    // layer of the new art is ready.
    property string displayedSource: ""
    property bool swapPending: false
    /// The first artwork is decoded; the frontend waits for this before its entrance.
    readonly property bool ready: displayedSource !== "" && newArtReady
    readonly property bool newArtReady: sharp.status !== Image.Loading && blurSource.status !== Image.Loading
                                        && fieldSource.status !== Image.Loading
    onSourceChanged: {
        if (!root.displayedSource || !root.source || root.videoActive || !root.visible) {
            root.displayedSource = root.source;
            return;
        }
        previousFrame.scheduleUpdate();
        root.swapPending = true;
    }
    Connections {
        target: root.Window.window
        enabled: root.swapPending
        function onFrameSwapped() {
            // The frozen texture now holds the old art: show it, then swap.
            root.swapPending = false;
            previousFadeOut.stop();
            previousFrame.opacity = 1;
            root.displayedSource = root.source;
            revealTimeout.restart();
        }
    }
    onNewArtReadyChanged: if (root.newArtReady && previousFrame.opacity > previousFrame.restingOpacity)
                              revealDelay.restart()
    // One frame for the cached blurs to re-render before the reveal.
    Timer {
        id: revealDelay
        interval: 32
        onTriggered: previousFadeOut.restart()
    }
    Timer {
        id: revealTimeout
        interval: 1500
        onTriggered: previousFadeOut.restart()
    }

    Behavior on coverProgress {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    Behavior on artOpacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    clip: true

    Item {
        id: artContent
        anchors.fill: parent

        // Blur pipeline -----------------------------------------------------------
        // The cover is blurred once, with a true gaussian, into a fixed square
        // texture that is cached. Every blurred layer below is a crop of that one
        // texture, so layout animations only move and crop it instead of re-blurring.
        // (MultiEffect's large blur levels upsample into a visible square grid.)

        Image {
            id: blurSource
            width: root.blurTextureSize
            height: root.blurTextureSize
            source: root.displayedSource
            sourceSize: Qt.size(root.blurTextureSize, root.blurTextureSize)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        // "side" wants a heavy blur beside the whole cover. "cover" keeps a much
        // lighter one (~60 px on screen) so the cropped art stays recognisable.
        GaussianBlur {
            id: coverBlur
            width: root.blurTextureSize
            height: root.blurTextureSize
            source: blurSource
            radius: 48
            samples: 97
            transparentBorder: false
            cached: true
        }
        GaussianBlur {
            id: coverBlurSoft
            width: root.blurTextureSize
            height: root.blurTextureSize
            source: blurSource
            radius: 16
            samples: 33
            transparentBorder: false
            cached: true
        }

        ShaderEffectSource {
            id: ambientTexture
            sourceItem: coverBlur
            hideSource: true
            sourceRect: root.cropRect(root.width / root.height)
            smooth: true
            visible: false
        }
        ShaderEffectSource {
            id: ambientTextureSoft
            sourceItem: coverBlurSoft
            hideSource: true
            sourceRect: root.cropRect(root.width / root.height)
            smooth: true
            visible: false
        }
        ShaderEffectSource {
            id: alignedTexture
            sourceItem: coverBlur
            hideSource: true
            sourceRect: root.cropRect(sharp.width / sharp.height)
            smooth: true
            visible: false
        }
        ShaderEffectSource {
            id: alignedTextureSoft
            sourceItem: coverBlurSoft
            hideSource: true
            sourceRect: root.cropRect(sharp.width / sharp.height)
            smooth: true
            visible: false
        }

        // Ambient echo: the blurred cover across the whole screen.
        Item {
            anchors.fill: parent
            opacity: root.artOpacity
            ShaderEffect {
                anchors.fill: parent
                property var source: ambientTexture
            }
            ShaderEffect {
                anchors.fill: parent
                opacity: root.coverProgress
                visible: opacity > 0.001
                property var source: ambientTextureSoft
            }
        }

        // The ambient echo is the cover scaled to the whole screen, so at the sharp
        // cover's edge it shows different content. This blurred copy shares the sharp
        // cover's exact geometry: the sharp image dissolves into its own blur, and
        // only this soft copy meets the ambient field.
        Rectangle {
            id: alignedBlurMask
            x: sharp.x
            width: sharp.width
            height: sharp.height
            visible: false
            layer.enabled: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.15
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.061 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.3
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.216 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.45
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.425 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.6
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.648 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.75
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.844 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.88
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.96 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid
                    color: ColorUtils.applyAlpha(root.shade, 1)
                }
                GradientStop {
                    position: revealMask.blurSolid
                    color: ColorUtils.applyAlpha(root.shade, 1)
                }
                GradientStop {
                    position: revealMask.blurSolid + (revealMask.rightClear - revealMask.blurSolid) * 0.15
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.939)
                }
                GradientStop {
                    position: revealMask.blurSolid + (revealMask.rightClear - revealMask.blurSolid) * 0.3
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.784)
                }
                GradientStop {
                    position: revealMask.blurSolid + (revealMask.rightClear - revealMask.blurSolid) * 0.45
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.575)
                }
                GradientStop {
                    position: revealMask.blurSolid + (revealMask.rightClear - revealMask.blurSolid) * 0.6
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.352)
                }
                GradientStop {
                    position: revealMask.blurSolid + (revealMask.rightClear - revealMask.blurSolid) * 0.75
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.156)
                }
                GradientStop {
                    position: revealMask.blurSolid + (revealMask.rightClear - revealMask.blurSolid) * 0.88
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.04)
                }
                GradientStop {
                    position: revealMask.rightClear
                    color: ColorUtils.applyAlpha(root.shade, 0)
                }
                GradientStop {
                    position: 1
                    color: ColorUtils.applyAlpha(root.shade, 0)
                }
            }
        }
        Item {
            x: sharp.x
            width: sharp.width
            height: sharp.height
            opacity: root.artOpacity
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: alignedBlurMask
            }
            ShaderEffect {
                anchors.fill: parent
                property var source: alignedTexture
            }
            ShaderEffect {
                anchors.fill: parent
                opacity: root.coverProgress
                visible: opacity > 0.001
                property var source: alignedTextureSoft
            }
        }

        // Deepens the blur toward the cover's dominant colour; controls and lyrics
        // are always light, so the ambient field has to stay dark.
        Rectangle {
            anchors.fill: parent
            opacity: root.artOpacity
            color: ColorUtils.applyAlpha(root.tintedShade, 0.34)
        }

        // In "side" the space beside the cover is the cover itself, almost whole, under
        // a very strong blur: a small decode blurred with a wide gaussian leaves only
        // soft colour masses, so nothing is recognisable, stretched or repeated. A
        // darker overlay keeps the lyrics readable and a wide ramp blends it in.
        Image {
            id: fieldSource
            width: root.fieldTextureSize
            height: root.fieldTextureSize
            source: root.displayedSource
            sourceSize: Qt.size(root.fieldTextureSize, root.fieldTextureSize)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        GaussianBlur {
            id: fieldBlur
            width: root.fieldTextureSize
            height: root.fieldTextureSize
            source: fieldSource
            radius: 56
            samples: 113
            transparentBorder: false
            cached: true
        }
        ShaderEffectSource {
            id: fieldTexture
            sourceItem: fieldBlur
            hideSource: true
            sourceRect: root.cropRect(edgeField.width / Math.max(1, edgeField.height), root.fieldTextureSize)
            smooth: true
            visible: false
        }
        Rectangle {
            id: edgeRamp
            width: edgeField.width
            height: edgeField.height
            visible: false
            layer.enabled: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: ColorUtils.applyAlpha(root.shade, 0)
                }
                GradientStop {
                    position: edgeField.solidAt * 0.15
                    color: ColorUtils.applyAlpha(root.shade, 0.061)
                }
                GradientStop {
                    position: edgeField.solidAt * 0.3
                    color: ColorUtils.applyAlpha(root.shade, 0.216)
                }
                GradientStop {
                    position: edgeField.solidAt * 0.45
                    color: ColorUtils.applyAlpha(root.shade, 0.425)
                }
                GradientStop {
                    position: edgeField.solidAt * 0.6
                    color: ColorUtils.applyAlpha(root.shade, 0.648)
                }
                GradientStop {
                    position: edgeField.solidAt * 0.75
                    color: ColorUtils.applyAlpha(root.shade, 0.844)
                }
                GradientStop {
                    position: edgeField.solidAt * 0.88
                    color: ColorUtils.applyAlpha(root.shade, 0.96)
                }
                GradientStop {
                    position: edgeField.solidAt
                    color: root.shade
                }
                GradientStop {
                    position: 1
                    color: root.shade
                }
            }
        }
        Item {
            id: edgeField
            readonly property real amount: (1 - root.coverProgress) * root.panelProgress
            // Starts halfway into the cover and is fully in well past its edge.
            readonly property real solidEdge: sharp.x + sharp.width + root.width * 0.16
            readonly property real solidAt: width > 0 ? Math.min(1, Math.max(0, (solidEdge - x) / width)) : 1
            x: sharp.x + revealMask.rightSolid * sharp.width
            width: Math.max(0, root.width - x)
            height: root.height
            opacity: root.artOpacity * amount
            visible: opacity > 0.001
            layer.enabled: visible
            layer.effect: OpacityMask {
                maskSource: edgeRamp
            }
            ShaderEffect {
                anchors.fill: parent
                property var source: fieldTexture
            }
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.applyAlpha(ColorUtils.mix(root.shade, root.fieldColor, 0.82),
                                             root.fieldShade + root.tintLuminance * 0.24)
            }
        }

        // Sharp cover ---------------------------------------------------------------
        Image {
            id: sharp
            readonly property real sideSize: root.height
            readonly property real sideX: Math.max(0, (root.width - sideSize) / 2) * (1 - root.panelProgress)
            x: sideX * (1 - root.coverProgress)
            width: sideSize + (root.width - sideSize) * root.coverProgress
            height: root.height
            source: root.displayedSource
            sourceSize: Qt.size(1600, 1600)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Rectangle {
            id: revealMask
            // Fade positions in the sharp image's own 0..1 width.
            readonly property real sideAmount: 1 - root.coverProgress
            readonly property real leftSolid: sideAmount * (1 - root.panelProgress) * 0.12
            readonly property real rightSolid: 1 - sideAmount * (0.14 + 0.36 * root.panelProgress) - root.coverProgress
                                               * root.panelProgress * 0.58
            readonly property real rightClear: Math.max(rightSolid, 1 - root.coverProgress * root.panelProgress * 0.3)
            // Staggered dissolves: the sharp cover is gone at 65% of the span, while its
            // aligned blur only starts leaving at 30% and reaches zero at the very end,
            // so neither layer ever ends on a hard edge.
            readonly property real sharpClear: rightSolid + (rightClear - rightSolid) * 0.65
            readonly property real blurSolid: rightSolid + (rightClear - rightSolid) * 0.3
            x: sharp.x
            width: sharp.width
            height: sharp.height
            visible: false
            // Smoothstep stops: a linear ramp reaches zero with a visible corner.
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.15
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.061 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.3
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.216 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.45
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.425 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.6
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.648 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.75
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.844 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid * 0.88
                    color: ColorUtils.applyAlpha(root.shade, revealMask.leftSolid > 0.001 ? 0.96 : 1)
                }
                GradientStop {
                    position: revealMask.leftSolid
                    color: ColorUtils.applyAlpha(root.shade, 1)
                }
                GradientStop {
                    position: revealMask.rightSolid
                    color: ColorUtils.applyAlpha(root.shade, 1)
                }
                GradientStop {
                    position: revealMask.rightSolid + (revealMask.sharpClear - revealMask.rightSolid) * 0.15
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.939)
                }
                GradientStop {
                    position: revealMask.rightSolid + (revealMask.sharpClear - revealMask.rightSolid) * 0.3
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.784)
                }
                GradientStop {
                    position: revealMask.rightSolid + (revealMask.sharpClear - revealMask.rightSolid) * 0.45
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.575)
                }
                GradientStop {
                    position: revealMask.rightSolid + (revealMask.sharpClear - revealMask.rightSolid) * 0.6
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.352)
                }
                GradientStop {
                    position: revealMask.rightSolid + (revealMask.sharpClear - revealMask.rightSolid) * 0.75
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.156)
                }
                GradientStop {
                    position: revealMask.rightSolid + (revealMask.sharpClear - revealMask.rightSolid) * 0.88
                    color: ColorUtils.applyAlpha(root.shade, 1 * 0.04)
                }
                GradientStop {
                    position: revealMask.sharpClear
                    color: ColorUtils.applyAlpha(root.shade, 0)
                }
                GradientStop {
                    position: 1
                    color: ColorUtils.applyAlpha(root.shade, 0)
                }
            }
        }
        OpacityMask {
            x: sharp.x
            width: sharp.width
            height: sharp.height
            opacity: root.artOpacity
            source: sharp
            maskSource: revealMask
        }
    }

    ShaderEffectSource {
        id: previousFrame
        // Kept at a near-zero opacity instead of hidden: a culled source never
        // renders, and scheduleUpdate() would capture nothing.
        readonly property real restingOpacity: 0.001
        anchors.fill: parent
        sourceItem: artContent
        live: false
        hideSource: false
        opacity: restingOpacity
        NumberAnimation {
            id: previousFadeOut
            target: previousFrame
            property: "opacity"
            to: previousFrame.restingOpacity
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }

    // Legibility ----------------------------------------------------------------
    // A light veil at the top for the toolbar and a deep one at the bottom for the
    // title and transport, which sit over the busiest part of many covers.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0
                color: ColorUtils.applyAlpha(root.shade, 0.3)
            }
            GradientStop {
                position: 0.18
                color: ColorUtils.applyAlpha(root.shade, 0)
            }
            GradientStop {
                position: 0.4
                color: ColorUtils.applyAlpha(root.shade, 0)
            }
            GradientStop {
                position: 0.58
                color: ColorUtils.applyAlpha(root.shade, 0.3)
            }
            GradientStop {
                position: 0.72
                color: ColorUtils.applyAlpha(root.shade, 0.52)
            }
            GradientStop {
                position: 0.86
                color: ColorUtils.applyAlpha(root.shade, 0.64)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(root.shade, 0.76)
            }
        }
    }
    // Behind the panels. The "side" field is already darkened for legibility, so
    // there this wash stays light.
    Rectangle {
        id: panelWash
        readonly property real strength: root.videoActive ? 1 : 0.35 + 0.65 * root.coverProgress
        anchors.fill: parent
        opacity: root.panelProgress * strength
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.4
                color: ColorUtils.applyAlpha(root.tintedShade, 0)
            }
            GradientStop {
                position: 0.72
                color: ColorUtils.applyAlpha(root.tintedShade, root.videoActive ? 0.5 : 0.22)
            }
            GradientStop {
                position: 1
                color: ColorUtils.applyAlpha(root.tintedShade, root.videoActive ? 0.62 : 0.3)
            }
        }
    }

}
