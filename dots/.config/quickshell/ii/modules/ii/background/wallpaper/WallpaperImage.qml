import QtQuick
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.ii.background.blur
import qs.modules.ii.background.overview
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

Item {
    id: wallpaperImageRoot
    anchors.fill: parent

    // Required inputs
    required property var screen
    required property var overviewController
    required property string wallpaperPath
    property string lockscreenWallpaperPath: ""
    property bool useSeparateLockscreenWallpaper: false
    required property bool wallpaperIsVideo
    required property bool wallpaperSafetyTriggered
    required property real preferredWallpaperScale
    required property real effectiveWallpaperScale
    required property real baseWallpaperScale
    required property int wallpaperWidth
    required property int wallpaperHeight
    required property bool wallpaperSizeKnown
    required property real wallpaperToScreenRatio
    required property real movableXSpace
    required property real movableYSpace
    required property real minSafeScale
    readonly property bool videoEffectsDisabled: wallpaperIsVideo || Config.options.background.useWallpaperEngine

    required property real parallaxX
    required property real parallaxY
    property real effectiveValueX: 0.5
    property real effectiveValueY: 0.5
    required property real scaleValue
    required property real scaleOriginX
    required property real scaleOriginY
    required property real scaleProgress
    property bool legacyGnomeZoomedOut: false
    // Edit Mode's shrink of the whole plane; the identity outside the mode.
    property matrix4x4 editMatrix: Qt.matrix4x4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    // Edit Mode's per-monitor progress, handed in by the surface that owns this
    // plane. Zero on every screen the mode is not on, so a second monitor's
    // wallpaper never follows a shrink it does not have.
    property real editProgress: 0

    // Smoothly center parallax during overview opening to ensure zoom-out presets
    // never expose black screen edges at extreme workspace positions, and during
    // Edit Mode's shrink so the wallpaper and the widgets arrive as one desktop.
    //
    // The mode term is a ramp on `editProgress`, not a gate on the `editMode`
    // boolean, for two reasons. The boolean is global while only one screen
    // shrinks, so keying on it would centre every monitor's wallpaper and slide
    // each of them on its own 450ms Behavior clock; the widgets already ramp on
    // the per-monitor scalar (BackgroundWidgetsWindow.widgetsParallaxOffset) and
    // the two layers must not disagree inside one card. And the boolean flips
    // instantly on the way out, which is the other half of the race.
    //
    // The blend order is not cosmetic: the overview term already multiplies by
    // `progress`, so applying the mode's factor afterwards is what keeps the two
    // independent - during the overview the mode is closed (factor 1, expression
    // unchanged byte for byte), during the mode no overview is open.
    readonly property real editParallaxFactor: 1.0 - editProgress
    readonly property real effectiveParallaxX: {
        if (videoEffectsDisabled || !overviewController.useWallpaperParallax)
            return wallpaperPlanes.centeredX;
        const raw = (overviewController && overviewController.progress > 0.001)
            ? parallaxX + (wallpaperPlanes.centeredX - parallaxX) * overviewController.progress
            : parallaxX;
        return wallpaperPlanes.centeredX + (raw - wallpaperPlanes.centeredX) * editParallaxFactor;
    }
    readonly property real effectiveParallaxY: {
        if (videoEffectsDisabled || !overviewController.useWallpaperParallax)
            return wallpaperPlanes.centeredY;
        const raw = (overviewController && overviewController.progress > 0.001)
            ? parallaxY + (wallpaperPlanes.centeredY - parallaxY) * overviewController.progress
            : parallaxY;
        return wallpaperPlanes.centeredY + (raw - wallpaperPlanes.centeredY) * editParallaxFactor;
    }

    required property bool anyWidgetIsDragging
    required property bool mediaModeOpen
    property bool lockAnimationActive: false
    required property bool hasWindowsInActiveWorkspace
    required property var widgetStateManager

    // The quality switch is also the opt-in for the reduced wallpaper render
    // targets.  With it off, keep the original full-resolution composition so
    // the wallpaper never goes through the cached low-resolution path.
    readonly property bool reduceVramUsage: Config.options.background.scaleLargeWallpapers === true

    // Output aliases
    property alias wallpaperItem: wallpaper
    property alias clipRectItem: centralWallpaperClipRect
    // The plane as it looks at rest, for Edit Mode's backdrop: sampled in its own coordinates,
    // so the sample stays full-screen while the plane itself is transformed into the card.
    readonly property alias wallpaperPlanesItem: wallpaperPlanes

    // ── Decode cap ────────────────────────────────────────────────────────────
    // A wallpaper larger than the plane it is drawn on costs RAM twice (decoded QImage plus GPU
    // texture) for detail no pixel can show. Cap the decode at the plane's device-pixel size with
    // headroom for every transform that can magnify it: the overview zoom presets (1.15 worst
    // case), the Gnome-like opening ratio (1.04) and the lock animation, which drives the plane
    // back to scale 1.0 and so only magnifies if the base scale is below 1.
    //
    // The cap is expressed as pre-scaled *file* dimensions rather than the plane box: sourceSize
    // fits the image inside the box preserving aspect, so with fillMode PreserveAspectCrop a box
    // of a different aspect ratio would decode too small and be upscaled to cover.
    // The window's DPR is the scale its buffer is actually rendered at. ShellScreen.devicePixelRatio
    // reports the integer-rounded wl_output scale (2 on a 1.5x monitor), which over-decodes by 33%
    // on every fractionally scaled setup. Only fall back to the screen before the window exists.
    readonly property real devicePixelRatio: {
        const w = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 0;
        if (w > 0)
            return Math.max(1, w);
        return Math.max(1, screen && screen.devicePixelRatio ? screen.devicePixelRatio : 1);
    }

    // Every transform that can scale the plane *up*, at its end value - the animated values
    // themselves must stay out of this, or the image would be re-decoded mid-animation.
    //   - the legacy zoom-out presets (fixed 1.15 for style 2, otherwise bounded by the coverage
    //     scale the overview needs),
    //   - the modern overview preset's end scale (camera-push is the largest at 1.09),
    //   - the Gnome-like opening ratio on this item,
    //   - the lock animation, which drives the plane to scale 1.0 and so only magnifies when the
    //     base scale is under 1.
    readonly property real magnificationHeadroom: {
        let headroom = Math.max(1, minSafeScale);
        if (Config.options.background.zoomOutStyle === 2)
            headroom = Math.max(headroom, 1.15);
        if (overviewController && overviewController.safeTargetScale)
            headroom = Math.max(headroom, overviewController.safeTargetScale);
        if (isGnomeLikeOverview)
            headroom *= Math.max(defaultRatio, zoomedRatio);
        if (baseWallpaperScale > 0)
            headroom *= Math.max(1, 1 / baseWallpaperScale);
        return headroom;
    }

    function decodeSizeFor(planeWidth, planeHeight) {
        // Native decode until the probe reports real file dimensions.
        if (wallpaperWidth <= 0 || wallpaperHeight <= 0 || planeWidth <= 0 || planeHeight <= 0)
            return Qt.size(-1, -1);
        const targetW = planeWidth * devicePixelRatio * magnificationHeadroom;
        const targetH = planeHeight * devicePixelRatio * magnificationHeadroom;
        const coverScale = Math.max(targetW / wallpaperWidth, targetH / wallpaperHeight);
        if (coverScale >= 1)
            return Qt.size(-1, -1);
        return Qt.size(Math.ceil(wallpaperWidth * coverScale), Math.ceil(wallpaperHeight * coverScale));
    }

    // Calculations
    readonly property bool overviewOpen: GlobalStates.overviewOpen
    readonly property bool overviewBackgroundActive: overviewController && overviewController.active
    readonly property bool overviewAnimationVisible: overviewController && (overviewController.active || overviewController.progress > 0.001)
    readonly property bool materialShapeActive: overviewController.isMaterialShape && overviewAnimationVisible
    readonly property bool materialShapeShadowActive: materialShapeActive && (Config.options.background.materialShapeShadow === true)
    readonly property bool materialShapeDirectMask: overviewController.isMaterialShape && Config.options.background.materialShapeShadow !== true
    readonly property real overviewCoverScale: overviewController.overviewCoverScale
    readonly property bool isGnomeLikeOverview: overviewController.isGnomeLike

    // The blur effects below capture this subtree into a texture once, when their Loader
    // activates, and keep that texture until the Loader is torn down again. Capturing before the
    // plane has its final size and the image has decoded is what leaves the wallpaper split into a
    // blurred and a sharp band until a workspace switch or an unlock rebuilds the effect.
    readonly property bool wallpaperSourceReady: wallpaperSizeKnown && wallpaper.status === Image.Ready

    // Keep the legacy opening scale available for Gnome-like while the modern
    // presets remain driven exclusively by OverviewBackgroundController.
    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    readonly property bool zoomInStyle: !videoEffectsDisabled && Config.options.overview.scrollingStyle.zoomStyle === "in"
    readonly property bool showOpeningAnimation: Config.options.overview.showOpeningAnimation
    readonly property var zoomLevels: ({
        "in": { default: 1.04, zoomed: 1 },
        "out": { default: 1, zoomed: 1.01 }
    })
    readonly property real defaultRatio: zoomInStyle ? zoomLevels.in.default : zoomLevels.out.default
    readonly property real zoomedRatio: zoomInStyle ? zoomLevels.in.zoomed : zoomLevels.out.zoomed

    // The overview controller owns the only background scale animation. Keeping
    // this item at unit scale prevents the scrolling overview's legacy scale
    // from multiplying it a second time.
    scale: isGnomeLikeOverview
        ? (!videoEffectsDisabled && showOpeningAnimation && overviewOpen && isScrollingLayout ? zoomedRatio : defaultRatio)
        : 1.0
    opacity: mediaModeOpen ? 0 : 1

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(wallpaperImageRoot)
    }

    // --- Overview backing (only styles that need exposed area fill) ---
    TransitionImage {
        id: overviewBackingImage
        anchors.fill: parent
        // Keep the small backing decoded for the selected preset. Clearing it
        // on close made Card Lift decode/crossfade again during the next search.
        imageSource: wallpaperImageRoot.overviewController.useBackingImage && !wallpaperSafetyTriggered ? wallpaperPath : ""
        animated: Config.options.background.animateWallpaperChanges
        fillMode: Image.PreserveAspectCrop
        visible: (wallpaperImageRoot.overviewController.isGnomeLike
            ? !wallpaperSafetyTriggered
            : wallpaperImageRoot.overviewController.useBackingImage && wallpaperImageRoot.overviewAnimationVisible && !wallpaperSafetyTriggered)
            && !wallpaperIsVideo && !Config.options.background.useWallpaperEngine
        opacity: 1.0
        mipmap: false
        antialiasing: false
        // The reduced backing source is part of the opt-in VRAM-saving path;
        // with the toggle off it follows the native-size branch below.
        sourceSize: wallpaperImageRoot.overviewController.useBackingBlur && wallpaperImageRoot.reduceVramUsage
            ? Qt.size(screen.width > 0 ? Math.round(screen.width / 8) : 240, screen.height > 0 ? Math.round(screen.height / 8) : 135)
            : (Config.options.background.scaleLargeWallpapers
                ? Qt.size(screen.width > 0 ? Math.round(screen.width * preferredWallpaperScale) : 1920, screen.height > 0 ? Math.round(screen.height * preferredWallpaperScale) : 1080)
                : Qt.size(-1, -1))
        lockAnimationActive: wallpaperImageRoot.lockAnimationActive
        // In the reduced path this image is decoded at 1/8 for blur and keeps
        // its crop in a small texture instead of a fullscreen proxy. The layer
        // is disabled when native wallpaper quality is selected.
        layer.enabled: wallpaperImageRoot.reduceVramUsage && overviewBackingBlurLoader.active
        layer.textureSize: wallpaperImageRoot.reduceVramUsage
            ? Qt.size(Math.max(1, Math.ceil(width / 4)), Math.max(1, Math.ceil(height / 4)))
            : Qt.size(0, 0)
        layer.smooth: true
    }

    Loader {
        id: overviewBackingBlurLoader
        anchors.fill: overviewBackingImage
        // Cache the final blur as well as its input. Gnome's blur is static;
        // Card Lift changes it per frame, but now renders only 1/16 the pixels.
        layer.enabled: wallpaperImageRoot.reduceVramUsage && active
        layer.textureSize: wallpaperImageRoot.reduceVramUsage
            ? Qt.size(Math.max(1, Math.ceil(width / 4)), Math.max(1, Math.ceil(height / 4)))
            : Qt.size(0, 0)
        layer.smooth: true
        // The backing must survive until the closing zoom covers it again.
        // Gating Gnome on active alone destroyed its blur on the first close frame.
        active: wallpaperImageRoot.overviewController.useBackingBlur && wallpaperImageRoot.overviewAnimationVisible
            && !wallpaperImageRoot.videoEffectsDisabled
        sourceComponent: MultiEffect {
            anchors.fill: parent
            source: overviewBackingImage
            // This plane fills the monitor; blur padding outside it is wasted.
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 75
            blur: wallpaperImageRoot.overviewController.isGnomeLike ? 0.7 : wallpaperImageRoot.overviewController.blurAmount

            Rectangle {
                anchors.fill: parent
                color: wallpaperImageRoot.overviewController.isGnomeLike ? "#000000" : Appearance.colors.colLayer0
                opacity: wallpaperImageRoot.overviewController.isGnomeLike ? 0.24 : wallpaperImageRoot.overviewController.dimAmount
            }
        }
    }

    Rectangle {
        id: overviewBackingDim
        anchors.fill: overviewBackingImage
        color: Appearance.colors.colLayer0
        visible: wallpaperImageRoot.overviewController.useBackingImage
            && !wallpaperImageRoot.overviewController.useBackingBlur
            && wallpaperImageRoot.overviewAnimationVisible
        opacity: wallpaperImageRoot.overviewController.dimAmount
    }

    Rectangle {
        id: materialShapeSolidBackdrop
        anchors.fill: parent
        color: Appearance.colors.colPrimaryContainer
        visible: wallpaperImageRoot.overviewController.isMaterialShape && wallpaperImageRoot.overviewAnimationVisible
        opacity: wallpaperImageRoot.overviewController.progress
    }

    // cornerRadius is already derived from the controller's animated progress.
    // A second Behavior here continuously retargets behind that clock, so the
    // mask stays nearly square until progress stops at the end of the overview.
    readonly property real wallpaperClipRadius: overviewController ? overviewController.cornerRadius : 0

    // Edit Mode container: shrinks the whole plane so it lands inside the card.
    Item {
        id: wallpaperPlanesContainer
        anchors.fill: parent

        transform: [
            Matrix4x4 {
                matrix: wallpaperImageRoot.editMatrix
            }
        ]

        // Wallpaper planes: scale zoom-out.
        Item {
            id: wallpaperPlanes
            anchors.fill: parent

            readonly property real wallpaperW: wallpaperWidth / wallpaperToScreenRatio * baseWallpaperScale
            readonly property real wallpaperH: wallpaperHeight / wallpaperToScreenRatio * baseWallpaperScale
            readonly property real centeredX: -movableXSpace
            readonly property real centeredY: -movableYSpace

            transform: [
                Scale {
                    origin.x: scaleOriginX
                    origin.y: scaleOriginY
                    xScale: scaleValue
                    yScale: scaleValue
                }
            ]

        Loader {
            id: materialShapeMaskContainer
            x: 0
            y: 0
            width: screen.width
            height: screen.height
            visible: wallpaperImageRoot.materialShapeShadowActive
            active: wallpaperImageRoot.materialShapeShadowActive

            sourceComponent: Item {
                MaterialShape {
                    id: materialShapeMask
                    anchors.centerIn: parent
                    width: wallpaperImageRoot.overviewController.maskTargetDiameter
                    height: wallpaperImageRoot.overviewController.maskTargetDiameter
                    shapeString: wallpaperImageRoot.overviewController.currentMaterialShape
                    // Alpha data for the optional shadow mask.
                    color: "white"
                    // A newly selected mask must be static while its transform moves.
                    animation: NumberAnimation { duration: 0 }

                    transform: [
                        Scale {
                            origin.x: materialShapeMask.width / 2
                            origin.y: materialShapeMask.height / 2
                            xScale: wallpaperImageRoot.overviewController.maskScale
                            yScale: wallpaperImageRoot.overviewController.maskScale
                        },
                        Rotation {
                            origin.x: materialShapeMask.width / 2
                            origin.y: materialShapeMask.height / 2
                            angle: wallpaperImageRoot.overviewController.maskRotation
                        }
                    ]
                }
            }
        }

        ShaderEffectSource {
            id: materialShapeMaskSource
            // Only the optional shadow needs a transformed screen-sized mask.
            // The common path transforms the static silhouette in its shader.
            sourceItem: wallpaperImageRoot.materialShapeShadowActive ? materialShapeMaskContainer : null
            hideSource: true
            live: wallpaperImageRoot.materialShapeShadowActive
            visible: false
        }

        StyledRectangularShadow {
            id: centralWallpaperShadow
            target: centralWallpaperClipRect
            // Radius, blur and offset all animate. A cached shadow would redraw
            // and resize an extra fullscreen texture on each of those frames.
            cached: false
            blur: 32 * scaleProgress
            offset: Qt.vector2d(0, 4 * scaleProgress)
            visible: wallpaperImageRoot.isGnomeLikeOverview
                ? wallpaperImageRoot.scaleProgress > 0.01
                : wallpaperImageRoot.overviewController.shadowAmount > 0.01
            opacity: scaleProgress
        }

        Rectangle {
            id: centralWallpaperClipRect
            x: 0
            y: 0
            width: screen.width
            height: screen.height
            color: "transparent"
            radius: wallpaperImageRoot.isGnomeLikeOverview
                ? wallpaperImageRoot.wallpaperClipRadius
                : wallpaperImageRoot.overviewController.cornerRadius
            clip: wallpaperImageRoot.isGnomeLikeOverview
                ? true
                : radius > 0
            border.color: wallpaperImageRoot.overviewController.isGnomeLike
                ? CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.35)
                : "transparent"
            border.width: wallpaperImageRoot.overviewController.isGnomeLike
                ? 1.5 * wallpaperImageRoot.scaleProgress
                : 0

            // Material Shape masks the stable content texture below directly;
            // capturing its animated transform here would dirty a full monitor.
            layer.enabled: (radius > 0) || wallpaperImageRoot.materialShapeShadowActive
            layer.effect: wallpaperImageRoot.overviewController.isMaterialShape
                ? materialShadowEffect
                : roundedMaskEffect

            Component {
                id: roundedMaskEffect
                OverviewRoundedMask {
                    cornerRadius: centralWallpaperClipRect.radius
                }
            }

            Component {
                id: materialShadowEffect
                MultiEffect {
                    maskEnabled: true
                    maskSource: materialShapeMaskSource
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0

                    shadowEnabled: wallpaperImageRoot.materialShapeShadowActive
                    shadowColor: "#000000"
                    shadowBlur: 0.35
                    shadowOpacity: 0.28
                    shadowVerticalOffset: 3
                    shadowHorizontalOffset: 0
                }
            }

            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(wallpaperImageRoot)
            }
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(wallpaperImageRoot)
            }
            Behavior on width {
                enabled: !wallpaperImageRoot.lockAnimationActive
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on height {
                enabled: !wallpaperImageRoot.lockAnimationActive
                NumberAnimation {
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }

            Item {
                id: wallpaperContent
                // Material Shape retains this layer between openings. Scale and
                // parallax are outer transforms: the wallpaper texture stays clean
                // while the shader moves its screen-space cutout over that texture.
                layer.enabled: wallpaperImageRoot.lockAnimationActive || GlobalStates.lockLookActive || wallpaperImageRoot.materialShapeDirectMask
                layer.effect: wallpaperImageRoot.materialShapeDirectMask ? materialWallpaperMaskEffect : null
                width: wallpaperPlanes.wallpaperW
                height: wallpaperPlanes.wallpaperH
                readonly property real contentScale: (baseWallpaperScale > 0 ? (effectiveWallpaperScale / baseWallpaperScale) : 1.0)
                    * (wallpaperImageRoot.overviewController ? wallpaperImageRoot.overviewController.wallpaperContentScale : 1.0)

                Component {
                    id: materialWallpaperMaskEffect
                    OverviewMaterialMask {
                        controller: wallpaperImageRoot.overviewController
                        maskScreenExtent: Qt.vector2d(centralWallpaperClipRect.width, centralWallpaperClipRect.height)
                        sourceScale: wallpaperContent.contentScale
                        sourceOffset: Qt.vector2d(
                            parallaxTranslate.x + wallpaperContent.width * (1 - sourceScale) / 2,
                            parallaxTranslate.y + wallpaperContent.height * (1 - sourceScale) / 2)
                    }
                }

                transform: [
                    Scale {
                        origin.x: wallpaperContent.width / 2
                        origin.y: wallpaperContent.height / 2
                        xScale: wallpaperContent.contentScale
                        yScale: wallpaperContent.contentScale
                    },
                    Translate {
                        id: parallaxTranslate
                        // effectiveParallaxX/Y already fall back to the centred offset when
                        // parallax is disabled; the centring must never be dropped or the
                        // overscanned wallpaper sits top-left and the lock zoom-out exposes it.
                        x: wallpaperImageRoot.effectiveParallaxX
                        y: wallpaperImageRoot.effectiveParallaxY
                        // One clock for the centring in both directions, exactly
                        // as the widget canvas gates its own position Behaviors
                        // on the mode's scalar. The centring above is already
                        // derived from `editProgress`, so this chase would only
                        // lag it - and it used to be enabled through the whole
                        // mode, which is the 450ms-vs-500ms race between the
                        // wallpaper and the widgets inside one shrinking card.
                        Behavior on x {
                            enabled: !wallpaperImageRoot.overviewAnimationVisible
                                && wallpaperImageRoot.editProgress <= 0.001
                            NumberAnimation {
                                duration: Math.round(450 * Appearance.animMultiplier)
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on y {
                            enabled: !wallpaperImageRoot.overviewAnimationVisible
                                && wallpaperImageRoot.editProgress <= 0.001
                            NumberAnimation {
                                duration: Math.round(450 * Appearance.animMultiplier)
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                ]

                Item {
                    id: wallpaperVisualContainer
                    anchors.fill: parent
                    layer.enabled: wallpaperImageRoot.overviewController.useColorAdjustments
                    layer.effect: MultiEffect {
                        saturation: wallpaperImageRoot.overviewController.saturation - 1.0
                        brightness: wallpaperImageRoot.overviewController.brightness - 1.0
                    }

                    TransitionImage {
                        id: wallpaper
                        anchors.fill: parent

                        visible: opacity > 0
                        opacity: (wallpaper.status === Image.Ready && !Config.options.background.useWallpaperEngine && (!wallpaperIsVideo || (windowBlur && windowBlur.shouldBlur))) ? 1 : 0
                        // GPU: cap the decode at the plane's device size with zoom
                        // headroom (decodeSizeFor). A 5320x3136 file decoded native
                        // costs ~64 MiB of RGBA texture per Image for pixels the plane
                        // can never show; the cap only fires when the file is larger
                        // than the plane and never upscales. The helper is only
                        // selected while the VRAM reduction toggle is enabled;
                        // disabling it restores the native decode size.
                        sourceSize: wallpaperImageRoot.reduceVramUsage
                            ? wallpaperImageRoot.decodeSizeFor(wallpaperContent.width, wallpaperContent.height)
                            : Qt.size(-1, -1)

                        imageSource: wallpaperSafetyTriggered ? "" : wallpaperPath
                        animated: Config.options.background.animateWallpaperChanges
                        transitionShader: Config.options.background.wallpaperAnimation
                        shadersPath: Qt.resolvedUrl("../shaders")
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        antialiasing: true
                        smooth: true
                        lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                    }

    // ── Video lockscreen wallpaper ───────────────────────────────────────
                    // A video picked for the lockscreen used to be handed to
                    // mpvpaper, which owns the *desktop* background layer — so it
                    // replaced the live wallpaper instead of the lock screen.
                    // switchwall.sh now leaves that layer alone for variant
                    // targets (see is_desktop_target) and the shell plays the
                    // file itself, here, only while locked.
                    Loader {
                        id: lockscreenVideo
                        anchors.fill: parent
                        z: 1

                        readonly property bool isVideoLockscreen: lockscreenWallpaper.isActive
                            && Wallpapers.isVideoFile(String(wallpaperImageRoot.lockscreenWallpaperPath).toLowerCase())
                        // Built on lock and torn down on unlock: a decoder has no
                        // business staying alive behind an unlocked desktop.
                        active: isVideoLockscreen && GlobalStates.lockLookActive
                        visible: active && opacity > 0
                        opacity: active ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Math.round(750 * Appearance.animMultiplier)
                                easing.type: Easing.InOutCubic
                            }
                        }

                        sourceComponent: Item {
                            MediaPlayer {
                                id: lockVideoPlayer
                                source: CF.FileUtils.trimFileProtocol(wallpaperImageRoot.lockscreenWallpaperPath)
                                autoPlay: true
                                loops: MediaPlayer.Infinite
                                // Muted deliberately: this is wallpaper, and the
                                // lock screen is the last place that should make
                                // noise on its own.
                                audioOutput: null
                                videoOutput: lockVideoOutput
                                Component.onCompleted: play()
                            }
                            VideoOutput {
                                id: lockVideoOutput
                                anchors.fill: parent
                                fillMode: VideoOutput.PreserveAspectCrop
                            }
                        }
                    }

                    TransitionImage {
                        id: lockscreenWallpaper
                        anchors.fill: parent

                        readonly property bool isActive: wallpaperImageRoot.useSeparateLockscreenWallpaper && wallpaperImageRoot.lockscreenWallpaperPath !== "" && wallpaperImageRoot.lockscreenWallpaperPath !== wallpaperImageRoot.wallpaperPath
                        visible: isActive && opacity > 0
                        opacity: (isActive && GlobalStates.lockLookActive) ? 1.0 : 0.0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Math.round(750 * Appearance.animMultiplier)
                                easing.type: Easing.InOutCubic
                            }
                        }

                        // GPU: same dynamic sourceSize cap as main wallpaper
                        sourceSize: Config.options.background.scaleLargeWallpapers ? Qt.size(screen.width > 0 ? Math.round(screen.width * preferredWallpaperScale) : 1920, screen.height > 0 ? Math.round(screen.height * preferredWallpaperScale) : 1080) : Qt.size(-1, -1)
                        // An Image cannot decode a video container; handing it one
                        // just produced an error and a blank layer. The poster frame
                        // ffmpeg extracts stands in until the decoder has a picture.
                        imageSource: (isActive && !wallpaperSafetyTriggered && !lockscreenVideo.isVideoLockscreen)
                            ? wallpaperImageRoot.lockscreenWallpaperPath
                            : ""
                        animated: Config.options.background.animateWallpaperChanges
                        transitionShader: Config.options.background.wallpaperAnimation
                        shadersPath: Qt.resolvedUrl("../shaders")
                        fillMode: Image.PreserveAspectCrop
                        mipmap: false
                        antialiasing: false
                        lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                    }
                }

                // Sits directly above the wallpaper and below every dim layer, so the overview's
                // dim and the widget-drag dim still compose on top of the blurred wallpaper
                // instead of being hidden underneath it.
                WindowBlur {
                    id: windowBlur
                    anchors.fill: parent
                    sourceItem: wallpaperVisualContainer
                    sourceReady: wallpaperImageRoot.wallpaperSourceReady
                    hasWindowsInActiveWorkspace: wallpaperImageRoot.hasWindowsInActiveWorkspace
                }

                Rectangle {
                    id: overviewDimLayer
                    anchors.fill: parent
                    color: Appearance.colors.colLayer0
                    // Soft Focus owns the scene-wide dim through
                    // BlurOverlayWindow; applying it here as well made that
                    // preset darker and visually converge with the others.
                    opacity: wallpaperImageRoot.overviewController.isGnomeLike || wallpaperImageRoot.overviewController.useCompositorBlur
                        ? 0.0
                        : wallpaperImageRoot.overviewController.dimAmount
                    visible: opacity > 0.001
                }

                Rectangle {
                    id: wallpaperDimLayer
                    anchors.fill: parent
                    color: Appearance.colors.colLayer0
                    opacity: anyWidgetIsDragging ? 0.2 : 0.0
                    visible: opacity > 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                LockBlur {
                    id: lockBlur
                    anchors.fill: parent
                    sourceItem: wallpaperVisualContainer
                    sourceReady: wallpaperImageRoot.wallpaperSourceReady
                    baseScale: wallpaperImageRoot.baseWallpaperScale
                    lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                    wallpaperIsVideo: wallpaperImageRoot.wallpaperIsVideo || Config.options.background.useWallpaperEngine
                }

                LockDesaturate {
                    anchors.fill: parent
                    sourceItem: Config.options.lock.blur.enable ? lockBlur : wallpaperVisualContainer
                    sourceReady: wallpaperImageRoot.wallpaperSourceReady
                    baseScale: wallpaperImageRoot.baseWallpaperScale
                    lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                }

                LockColorWash {
                    anchors.fill: parent
                    sourceItem: wallpaperVisualContainer
                    baseScale: wallpaperImageRoot.baseWallpaperScale
                    lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                }

                LockVignette {
                    anchors.fill: parent
                    sourceItem: wallpaperVisualContainer
                    baseScale: wallpaperImageRoot.baseWallpaperScale
                    lockAnimationActive: wallpaperImageRoot.lockAnimationActive
                }
            }
        }

        }
    }
}
