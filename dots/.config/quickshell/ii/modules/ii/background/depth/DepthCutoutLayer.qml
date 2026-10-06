import QtQuick
import qs
import qs.services
import qs.modules.common

/**
 * The wallpaper's subject, drawn over the desktop widgets (services/DepthEffect.qml).
 *
 * Lives in the widgets window, over the widget canvas, and has to land on the
 * wallpaper window's exact pixels. Nothing is recomputed from config: every
 * number is read from the screen's own WallpaperImage (its live plane size,
 * content scale, parallax translate - mid-animation included - and framing)
 * and laid out in the same item structure (DepthPlaneChain.qml), with the
 * cutout at the file's pixels, cover-fit, inside it.
 *
 * Painted only where the canvas has pixels ("source atop", depthCutoutMask.frag).
 * The compositor blurs whatever sits behind a half-transparent pixel of the
 * widgets surface (Appearance.backgroundWidgetsBlur): drawn plainly, the
 * cutout's soft edge over bare wallpaper showed that blur as a fringe. Masked,
 * the surface stays transparent there and the screen is the wallpaper itself;
 * over a widget the subject covers it, soft edges and all.
 *
 * It is a picture of the wallpaper, so it leaves wherever the wallpaper stops
 * looking like itself: the lock's blur/desaturation, the overview's dim, the
 * AOD's black, a video, work safety. Edit Mode keeps it at reduced opacity,
 * and a widget drag lowers it further, so whatever is being placed behind the
 * subject stays visible while it is placed.
 */
Item {
    id: root

    required property string screenName
    // The widget canvas: the mask, rendered in window coordinates (its own
    // parallax offset undone through sourceRect).
    required property Item canvas
    required property var overviewController
    required property matrix4x4 containerEditMatrix
    required property real containerScale
    property real aodProgress: 0
    property real editProgress: 0
    // The canvas's own blur while windows are open (the widgets blur
    // themselves then; a copy of the wallpaper would not be blurred).
    property real windowBlurProgress: 0
    property bool dragging: false
    // Canvas UI the subject must not cover (the align bar, an icon's dialog,
    // the marquee): the canvas draws them, so the mask would include them.
    property bool suppressed: false

    readonly property var plane: DepthEffect.planes[root.screenName] ?? null
    readonly property Item contentItem: cutoutChain.contentItem
    readonly property var parallaxTranslate: cutoutChain.parallaxTranslate
    readonly property Item framedItem: cutoutChain.framedItem
    readonly property var wallpaperItem: root.plane ? root.plane.wallpaperItem : null

    // The picture actually on the plane, when it is one a cutout can stand for.
    readonly property string planePath: {
        const p = root.plane;
        if (!p || p.wallpaperIsVideo || p.shellVideoPath !== "" || p.wallpaperSafetyTriggered
                || Config.options.background.useWallpaperEngine)
            return "";
        return DepthEffect.cleanPath(p.committedWallpaperSource);
    }
    onPlanePathChanged: DepthEffect.want(root.screenName, root.planePath)
    Component.onCompleted: DepthEffect.want(root.screenName, root.planePath)
    Component.onDestruction: DepthEffect.want(root.screenName, "")

    // ── Which cutout is drawn ────────────────────────────────────────────────
    // The one for the picture on the plane. A new picture does not swap it in
    // place: the old cutout fades out with the wallpaper's transition and the
    // new one comes in once the transition has landed.
    readonly property var wantedCutout: {
        const c = DepthEffect.cutoutFor(root.planePath);
        return c && !c.empty && c.png ? c : null;
    }
    property var shownCutout: null
    readonly property bool transitioning: root.wallpaperItem ? root.wallpaperItem.transitioning : false
    readonly property bool lockShowsOtherPicture: GlobalStates.lockLookActive && root.plane
        && root.plane.useSeparateLockscreenWallpaper && root.plane.lockscreenWallpaperPath !== ""
        && root.plane.lockscreenWallpaperPath !== root.plane.wallpaperPath
    readonly property bool present: root.shownCutout !== null && root.shownCutout === root.wantedCutout
        && !root.transitioning && !root.lockShowsOtherPicture && cutout.status === Image.Ready
    property real presence: root.present ? 1 : 0
    Behavior on presence {
        NumberAnimation {
            duration: Math.round(320 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }
    function syncShown() {
        if (root.shownCutout === root.wantedCutout)
            return;
        // Swapped only while nothing is on screen, so a picture never shows
        // another picture's subject for a frame.
        if (root.shownCutout === null || root.presence <= 0.001)
            root.shownCutout = root.transitioning ? null : root.wantedCutout;
    }
    onWantedCutoutChanged: root.syncShown()
    onPresenceChanged: root.syncShown()
    onTransitioningChanged: root.syncShown()

    // ── When it steps aside ──────────────────────────────────────────────────
    // The lock treats the wallpaper (blur, desaturation, colour wash) on the
    // LockBlur clock: a 150 ms hold, then 350 ms. The cutout leaves on the same
    // clock, so the subject is never sharp over a treated picture.
    readonly property bool lockTreated: GlobalStates.lockLookActive
        && ((Config.options.lock.blur.enable ?? false)
            || (Config.options.lock.desaturate?.enable ?? false)
            || (Config.options.lock.colorWash?.enable ?? false))
    property real lockFade: root.lockTreated ? 1 : 0
    Behavior on lockFade {
        SequentialAnimation {
            PauseAnimation {
                duration: root.lockTreated ? Math.round(150 * Appearance.animMultiplier) : 0
            }
            NumberAnimation {
                duration: Math.round(350 * Appearance.animMultiplier)
                easing.type: Easing.OutCubic
            }
        }
    }
    property real dragFade: root.dragging || root.suppressed ? 1 : 0
    Behavior on dragFade {
        NumberAnimation {
            duration: Math.round(200 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }
    readonly property real overviewProgress: root.overviewController ? root.overviewController.progress : 0

    // ── While the plane moves ────────────────────────────────────────────────
    // The wallpaper and this cutout are two layer surfaces, and nothing on
    // Wayland presents two surfaces' frames together: mid-animation the
    // compositor pairs a wallpaper frame with a cutout frame a tick apart, and
    // the subject showed a few pixels off inside every widget it covers (the
    // date's glyphs ghosted across the face during a parallax slide). At rest
    // the two agree to the pixel.
    //
    // A parallax slide moves nothing but the plane, so for its length the
    // widgets window paints a copy of the wallpaper under the widgets
    // (DepthWallpaperCopy.qml, `copyActive`): the copy, the widgets and the
    // cutout are then one surface, in step by construction, and the subject
    // stays in front throughout. Everything else that moves the plane also
    // treats it (the lock's zoom under its blur, Edit Mode's card, the
    // overview), which a copy would not reproduce: there the cutout steps out
    // while the plane moves and comes back once it has settled.
    property bool planeMoving: false
    function noteMotion() {
        root.planeMoving = true;
        settleTimer.restart();
    }
    Timer {
        id: settleTimer
        interval: 120
        onTriggered: root.planeMoving = false
    }
    Connections {
        target: root.parallaxTranslate
        function onXChanged() { root.noteMotion(); }
        function onYChanged() { root.noteMotion(); }
    }
    Connections {
        target: root.contentItem
        function onContentScaleChanged() { root.noteMotion(); }
        function onWidthChanged() { root.noteMotion(); }
        function onHeightChanged() { root.noteMotion(); }
    }
    Connections {
        target: root.framedItem
        function onXChanged() { root.noteMotion(); }
        function onYChanged() { root.noteMotion(); }
        function onWidthChanged() { root.noteMotion(); }
        function onHeightChanged() { root.noteMotion(); }
        function onRotationChanged() { root.noteMotion(); }
    }
    Connections {
        target: cutoutChain
        function onCorrectionChanged() { root.noteMotion(); }
    }
    // The copy reproduces the plane and the bar overlay above it, nothing more.
    readonly property bool copyAllowed: root.editProgress <= 0.001
        && root.overviewProgress <= 0.001
        && !GlobalStates.lockLookActive
        && root.lockFade <= 0.001
        && root.aodProgress <= 0.001
        && root.windowBlurProgress <= 0.001
        && Math.abs(root.containerScale - 1) < 0.0001
    readonly property bool copyActive: root.planeMoving && root.copyAllowed && root.present
    property real motionFade: root.planeMoving && !root.copyAllowed ? 1 : 0
    Behavior on motionFade {
        NumberAnimation {
            duration: root.planeMoving ? Math.round(70 * Appearance.animMultiplier) : Math.round(220 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }

    opacity: root.presence
        * (1 - root.lockFade)
        * (1 - root.aodProgress)
        * (1 - root.overviewProgress)
        * (1 - root.motionFade)
        * (1 - 0.55 * root.editProgress)
        * (1 - (root.suppressed ? 1 : 0.65) * root.dragFade)
        * root.canvas.opacity
    visible: opacity > 0.001 && root.shownCutout !== null && root.plane !== null

    // ── Geometry ─────────────────────────────────────────────────────────────
    // Fills the widget container: window coordinates under its transforms.
    anchors.fill: parent

    // Rendered into `cutoutTexture`, which ignores the source item's own
    // transform: the chain's correction sits one level down.
    Item {
        id: cutoutPlane
        anchors.fill: parent

        DepthPlaneChain {
            id: cutoutChain
            anchors.fill: parent
            plane: root.plane
            overviewController: root.overviewController
            containerEditMatrix: root.containerEditMatrix
            containerScale: root.containerScale

            // The picture is drawn PreserveAspectCrop, centred: the cutout's
            // rectangle in file pixels maps through the same cover scale.
            Image {
                id: cutout
                readonly property var info: root.shownCutout
                readonly property real fileW: cutout.info ? cutout.info.sourceWidth : 1
                readonly property real fileH: cutout.info ? cutout.info.sourceHeight : 1
                readonly property real cover: Math.max(cutoutChain.frameWidth / cutout.fileW, cutoutChain.frameHeight / cutout.fileH)
                readonly property real offsetX: (cutoutChain.frameWidth - cutout.fileW * cutout.cover) / 2
                readonly property real offsetY: (cutoutChain.frameHeight - cutout.fileH * cutout.cover) / 2
                // Decoded at the wallpaper's own decode scale, so both sample
                // the same detail; native when the wallpaper is native.
                readonly property size decode: root.plane ? root.plane.stableDecodeSize : Qt.size(-1, -1)
                readonly property real decodeRatio: cutout.decode.width > 0 ? cutout.decode.width / cutout.fileW : 1

                x: cutout.info ? cutout.offsetX + cutout.info.x * cutout.cover : 0
                y: cutout.info ? cutout.offsetY + cutout.info.y * cutout.cover : 0
                width: cutout.info ? cutout.info.width * cutout.cover : 0
                height: cutout.info ? cutout.info.height * cutout.cover : 0
                source: cutout.info ? "file://" + cutout.info.png : ""
                sourceSize: cutout.info && cutout.decodeRatio < 1
                    ? Qt.size(Math.max(1, Math.round(cutout.info.width * cutout.decodeRatio)),
                              Math.max(1, Math.round(cutout.info.height * cutout.decodeRatio)))
                    : Qt.size(-1, -1)
                fillMode: Image.Stretch
                asynchronous: true
                // One copy, no pixmap cache: it is replaced, never shared.
                cache: false
                smooth: true
                mipmap: root.plane ? !root.plane.decodeCapped : true
                antialiasing: true
            }
        }
    }

    // At the window's own pixel grid, so the composite below copies it 1:1.
    ShaderEffectSource {
        id: cutoutTexture
        anchors.fill: parent
        sourceItem: cutoutPlane
        hideSource: true
        live: true
        visible: false
        smooth: true
    }
    // At full resolution too: a half-resolution mask spread every widget's
    // coverage a pixel out, over bare wallpaper.
    ShaderEffectSource {
        id: maskTexture
        anchors.fill: parent
        sourceItem: root.canvas
        sourceRect: Qt.rect(-root.canvas.x, -root.canvas.y, root.width, root.height)
        hideSource: false
        live: true
        visible: false
        smooth: true
    }
    ShaderEffect {
        anchors.fill: parent
        property var source: cutoutTexture
        property var maskSource: maskTexture
        property real maskThreshold: 0.02
        // Mirrors BarGradientOverlay's own gate, span and 300 ms fade.
        readonly property bool barBandShown: Config.options.bar.barBackgroundStyle === 0
            && Config.options.bar.transparentGlow
            && GlobalStates.barOpen
            && !GlobalStates.lockLookActive
        property real barBand: barBandShown ? 1 : 0
        Behavior on barBand {
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }
        readonly property real barSpan: (BarPlacement.vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight) + 80
        property real barBandSize: barSpan / Math.max(1, BarPlacement.vertical ? width : height)
        property real barBandAlongY: BarPlacement.vertical ? 0 : 1
        property real barBandFromEnd: BarPlacement.bottom ? 1 : 0
        property real outline: (Config.options.background.depthEffect.outline ?? false) ? 1 : 0
        Behavior on outline {
            NumberAnimation {
                duration: Math.round(250 * Appearance.animMultiplier)
                easing.type: Easing.OutCubic
            }
        }
        property vector2d maskTexel: Qt.vector2d(1 / Math.max(1, width), 1 / Math.max(1, height))
        property real outlineWidth: 2
        fragmentShader: Qt.resolvedUrl("../shaders/depthCutoutMask.frag.qsb")
    }
}
