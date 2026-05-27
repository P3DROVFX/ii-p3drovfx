pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.utils //FIXME. remove
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.ii.background.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.ii.background.widgets.weather
import qs.modules.ii.background.widgets.media

Scope {
    id: backgroundScope

    Variants {
        id: root
        model: Quickshell.screens

        PanelWindow {
            id: bgRoot

            required property var modelData

            // Hide when fullscreen
            property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
            property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
            visible: GlobalStates.screenLocked || (!(activeWorkspaceWithFullscreen != undefined)) || !Config?.options.background.hideWhenFullscreen

            // Workspaces
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            property list<var> relevantWindows: HyprlandData.windowList.filter(win => win.monitor == monitor?.id && win.workspace.id >= 0).sort((a, b) => a.workspace.id - b.workspace.id)
            property int firstWorkspaceId: relevantWindows[0]?.workspace.id || 1
            property int lastWorkspaceId: relevantWindows[relevantWindows.length - 1]?.workspace.id || 10

            // Wallpaper
            property bool wallpaperIsVideo: {
                const path = Config.options?.background?.wallpaperPath ?? "";
                return path !== "" && (path.endsWith(".mp4") || path.endsWith(".webm") || path.endsWith(".mkv") || path.endsWith(".avi") || path.endsWith(".mov"));
            }
            property string wallpaperPath: {
                const rawPath = wallpaperIsVideo ? (Config.options?.background?.thumbnailPath ?? "") : (Config.options?.background?.wallpaperPath ?? "");
                if (rawPath !== "")
                    return rawPath;
                return `${Directories.assetsPath}/images/default_wallpaper.png`;
            }
            property bool wallpaperSafetyTriggered: {
                const enabled = Config.options.workSafety.enable.wallpaper;
                const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
                const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
                return enabled && sensitiveWallpaper && sensitiveNetwork;
            }
            property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screen.width, wallpaperHeight / screen.height)
            property real preferredWallpaperScale: Config.options.background.parallax.workspaceZoom
            property real effectiveWallpaperScale: 1 // Some reasonable init value, to be updated
            property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
            property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
            property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.width) / 2
            property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.height) / 2
            readonly property real minSafeScale: {
                const w = wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale;
                const h = wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale;
                if (w <= 0 || h <= 0)
                    return 1.0;
                return Math.max(screen.width / w, screen.height / h);
            }

            readonly property bool verticalParallax: (Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical
            // Colors
            property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
            property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
            property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
            property color colText: {
                if (wallpaperSafetyTriggered)
                    return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
                return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
            }
            Behavior on colText {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"

            property var zoomLevels: {  // has to be reverted compared to background
                "in": {
                    default: 1.04,
                    zoomed: 1
                },
                "out": {
                    default: 1,
                    zoomed: 1.04
                }
            }

            property real defaultRatio: zoomInStyle ? zoomLevels.in.default : zoomLevels.out.default
            property real zoomedRatio: zoomInStyle ? zoomLevels.in.zoomed : zoomLevels.out.zoomed

            readonly property bool zoomInStyle: Config.options.overview.scrollingStyle.zoomStyle === "in"
            readonly property bool showOpeningAnimation: Config.options.overview.showOpeningAnimation

            property bool overviewOpen: GlobalStates.overviewOpen

            property real scaleAnimated: GlobalStates.overviewOpen && showOpeningAnimation ? zoomedRatio : defaultRatio
            Behavior on scaleAnimated {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // Layer props
            screen: modelData
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) ? WlrLayer.Top : WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell:background"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: {
                if (!bgRoot.wallpaperSafetyTriggered || bgRoot.wallpaperIsVideo)
                    return "transparent";
                return CF.ColorUtils.mix(Appearance.colors.colLayer0, Appearance.colors.colPrimary, 0.75);
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            onWallpaperPathChanged: {
                bgRoot.updateZoomScale();
                // Clock position gets updated after zoom scale is updated
            }

            // Wallpaper zoom scale
            function updateZoomScale() {
                getWallpaperSizeProc.path = bgRoot.wallpaperPath;
                getWallpaperSizeProc.running = true;
            }
            Process {
                id: getWallpaperSizeProc
                property string path: bgRoot.wallpaperPath
                command: ["magick", "identify", "-format", "%w %h", path]
                stdout: StdioCollector {
                    id: wallpaperSizeOutputCollector
                    onStreamFinished: {
                        const output = wallpaperSizeOutputCollector.text;
                        const [width, height] = output.split(" ").map(Number);
                        const [screenWidth, screenHeight] = [bgRoot.screen.width, bgRoot.screen.height];
                        bgRoot.wallpaperWidth = width;
                        bgRoot.wallpaperHeight = height;

                        if (width <= screenWidth || height <= screenHeight) {
                            // Undersized/perfectly sized wallpapers
                            bgRoot.effectiveWallpaperScale = Math.max(screenWidth / width, screenHeight / height);
                        } else {
                            // Oversized = can be zoomed for parallax, yay
                            bgRoot.effectiveWallpaperScale = Math.min(bgRoot.preferredWallpaperScale, width / screenWidth, height / screenHeight);
                        }
                    }
                }
            }

            property bool mediaModeOpen: mediaModeLoader.active && MprisController.activePlayer
            onMediaModeOpenChanged: {
                if (!mediaModeOpen) {
                    Wallpapers.apply(Config.options.background.wallpaperPath);
                    LyricsService.shellColorChanged = false;
                }
            }

            Component.onCompleted: {
                if (!mediaModeOpen) {
                    Wallpapers.apply(Config.options.background.wallpaperPath);
                }
            }

            Item {
                id: wallpaperItem
                anchors.fill: parent
                clip: true
                scale: showOpeningAnimation && overviewOpen && bgRoot.isScrollingLayout ? zoomedRatio : defaultRatio
                opacity: mediaModeOpen ? 0 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.InOutQuad
                    }
                }

                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }

                // --- STYLE 0/1: Blurred backing (full-screen blurred wallpaper behind zoomed-out central) ---
                TransitionImage {
                    id: bgWallpaperBlurred
                    anchors.fill: parent
                    imageSource: ((wallpaperItem.wallpaperZoomedOut || wallpaperItem.wallpaperClipRadius > 0) && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                    animated: Config.options.background.animateWallpaperChanges
                    fillMode: Image.PreserveAspectCrop
                    // Visible for both styles during zoom out & return animation to avoid any black fallback margins
                    visible: Config.options.background.zoomOutStyle !== 2 && (wallpaperItem.wallpaperZoomedOut || wallpaperItem.wallpaperClipRadius > 0) && !bgRoot.wallpaperIsVideo
                    opacity: 1.0
                }
                GaussianBlur {
                    id: bgWallpaperBlurEffect
                    anchors.fill: bgWallpaperBlurred
                    source: bgWallpaperBlurred
                    radius: 40
                    samples: 81
                    visible: bgWallpaperBlurred.visible
                    opacity: wallpaperItem.wallpaperZoomedOut ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 375
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Shared zoom-out state — gated on zoomOutEnabled
                readonly property bool wallpaperZoomedOut: Config.options.background.zoomOutEnabled && (GlobalStates.cheatsheetOpen || GlobalStates.overviewOpen)

                // Animated clip radius — drives both the border-radius clip and tile visibility
                property real wallpaperClipRadius: wallpaperZoomedOut ? Appearance.rounding.windowRounding : 0
                Behavior on wallpaperClipRadius {
                    NumberAnimation {
                        duration: 375
                        easing.type: Easing.OutCubic
                    }
                }

                // Wallpaper planes: scale zoom-out.
                Item {
                    id: wallpaperPlanes
                    anchors.fill: parent

                    readonly property bool barVertical: Config.options.bar.vertical
                    readonly property bool barBottom: Config.options.bar.bottom
                    readonly property int barSize: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
                    readonly property int gap: Appearance.gapsOut

                    readonly property int padLeft: barVertical && !barBottom ? barSize : gap
                    readonly property int padRight: barVertical && barBottom ? barSize : gap
                    readonly property int padTop: !barVertical && !barBottom ? barSize : gap
                    readonly property int padBottom: !barVertical && barBottom ? barSize : gap

                    readonly property real scaleOriginX: padLeft + (bgRoot.screen.width - padLeft - padRight) / 2
                    readonly property real scaleOriginY: padTop + (bgRoot.screen.height - padTop - padBottom) / 2

                    // Shared parallax + size properties used by all 9 tiles
                    property real wallpaperW: bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                    property real wallpaperH: bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale
                    property real parallaxX: -(bgRoot.movableXSpace) - (wallpaper.effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                    property real parallaxY: -(bgRoot.movableYSpace) - (wallpaper.effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
                    // Centered position (style 0: no parallax offset)
                    property real centeredX: -(bgRoot.movableXSpace)
                    property real centeredY: -(bgRoot.movableYSpace)

                    readonly property real scaleProgress: {
                        let startScale = 1.0;
                        let targetScale = Math.max(0.85, bgRoot.minSafeScale * 0.85);
                        if (startScale === targetScale)
                            return 0.0;
                        return Math.max(0.0, Math.min(1.0, (startScale - scaleValue) / (startScale - targetScale)));
                    }

                    property real scaleValue: {
                        if (!wallpaperItem.wallpaperZoomedOut)
                            return 1.0;
                        if (Config.options.background.zoomOutStyle === 2)
                            return 1.15;
                        return Math.max(0.85, bgRoot.minSafeScale * 0.85);
                    }
                    Behavior on scaleValue {
                        NumberAnimation {
                            duration: 375
                            easing.type: Easing.OutCubic
                        }
                    }

                    transform: Scale {
                        origin.x: wallpaperPlanes.scaleOriginX
                        origin.y: wallpaperPlanes.scaleOriginY
                        xScale: wallpaperPlanes.scaleValue
                        yScale: wallpaperPlanes.scaleValue
                    }

                    // Publish zoom state so OverviewWindowTransition can sync its animation
                    Binding {
                        target: GlobalStates
                        property: "overviewZoomScale"
                        value: wallpaperPlanes.scaleValue
                        when: Hyprland.focusedMonitor?.name == bgRoot.monitor?.name
                    }
                    Binding {
                        target: GlobalStates
                        property: "overviewZoomOriginX"
                        value: wallpaperPlanes.scaleOriginX
                        when: Hyprland.focusedMonitor?.name == bgRoot.monitor?.name
                    }
                    Binding {
                        target: GlobalStates
                        property: "overviewZoomOriginY"
                        value: wallpaperPlanes.scaleOriginY
                        when: Hyprland.focusedMonitor?.name == bgRoot.monitor?.name
                    }

                    // Tile visibility persists while clipRadius > 0 (through close animation)
                    readonly property bool tilesVisible: Config.options.background.zoomOutStyle === 1 && (wallpaperItem.wallpaperZoomedOut || wallpaperItem.wallpaperClipRadius > 0) && !bgRoot.wallpaperIsVideo

                    // --- MIRRORED PLANE TILES (Style 1) ---
                    // Each tile mirrors the central wallpaper and is offset by ±wallpaperW or ±wallpaperH
                    // Positions track parallaxX/Y directly so tiles are always pixel-perfect adjacent.
                    // Placed outside any clipping wrapper so they fill the screen perfectly to avoid black margins.

                    Item {
                        id: outerTilesContainer
                        anchors.fill: parent
                        visible: wallpaperPlanes.tilesVisible

                        TransitionImage {
                            id: leftTile
                            width: wallpaperPlanes.wallpaperW
                            height: wallpaperPlanes.wallpaperH
                            x: wallpaperPlanes.parallaxX - wallpaperPlanes.wallpaperW
                            y: wallpaperPlanes.parallaxY
                            imageSource: (wallpaperPlanes.tilesVisible && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop
                            transform: Scale {
                                xScale: -1
                                origin.x: leftTile.width / 2
                                origin.y: leftTile.height / 2
                            }
                        }
                        TransitionImage {
                            id: rightTile
                            width: wallpaperPlanes.wallpaperW
                            height: wallpaperPlanes.wallpaperH
                            x: wallpaperPlanes.parallaxX + wallpaperPlanes.wallpaperW
                            y: wallpaperPlanes.parallaxY
                            imageSource: (wallpaperPlanes.tilesVisible && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop
                            transform: Scale {
                                xScale: -1
                                origin.x: rightTile.width / 2
                                origin.y: rightTile.height / 2
                            }
                        }
                        TransitionImage {
                            id: topTile
                            width: wallpaperPlanes.wallpaperW
                            height: wallpaperPlanes.wallpaperH
                            x: wallpaperPlanes.parallaxX
                            y: wallpaperPlanes.parallaxY - wallpaperPlanes.wallpaperH
                            imageSource: (wallpaperPlanes.tilesVisible && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop
                            transform: Scale {
                                yScale: -1
                                origin.x: topTile.width / 2
                                origin.y: topTile.height / 2
                            }
                        }
                        TransitionImage {
                            id: bottomTile
                            width: wallpaperPlanes.wallpaperW
                            height: wallpaperPlanes.wallpaperH
                            x: wallpaperPlanes.parallaxX
                            y: wallpaperPlanes.parallaxY + wallpaperPlanes.wallpaperH
                            imageSource: (wallpaperPlanes.tilesVisible && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop
                            transform: Scale {
                                yScale: -1
                                origin.x: bottomTile.width / 2
                                origin.y: bottomTile.height / 2
                            }
                        }
                        TransitionImage {
                            id: topLeftTile
                            width: wallpaperPlanes.wallpaperW
                            height: wallpaperPlanes.wallpaperH
                            x: wallpaperPlanes.parallaxX - wallpaperPlanes.wallpaperW
                            y: wallpaperPlanes.parallaxY - wallpaperPlanes.wallpaperH
                            imageSource: (wallpaperPlanes.tilesVisible && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop
                            transform: Scale {
                                xScale: -1
                                yScale: -1
                                origin.x: topLeftTile.width / 2
                                origin.y: topLeftTile.height / 2
                            }
                        }
                        TransitionImage {
                            id: topRightTile
                            width: wallpaperPlanes.wallpaperW
                            height: wallpaperPlanes.wallpaperH
                            x: wallpaperPlanes.parallaxX + wallpaperPlanes.wallpaperW
                            y: wallpaperPlanes.parallaxY - wallpaperPlanes.wallpaperH
                            imageSource: (wallpaperPlanes.tilesVisible && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop
                            transform: Scale {
                                xScale: -1
                                yScale: -1
                                origin.x: topRightTile.width / 2
                                origin.y: topRightTile.height / 2
                            }
                        }
                        TransitionImage {
                            id: bottomLeftTile
                            width: wallpaperPlanes.wallpaperW
                            height: wallpaperPlanes.wallpaperH
                            x: wallpaperPlanes.parallaxX - wallpaperPlanes.wallpaperW
                            y: wallpaperPlanes.parallaxY + wallpaperPlanes.wallpaperH
                            imageSource: (wallpaperPlanes.tilesVisible && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop
                            transform: Scale {
                                xScale: -1
                                yScale: -1
                                origin.x: bottomLeftTile.width / 2
                                origin.y: bottomLeftTile.height / 2
                            }
                        }
                        TransitionImage {
                            id: bottomRightTile
                            width: wallpaperPlanes.wallpaperW
                            height: wallpaperPlanes.wallpaperH
                            x: wallpaperPlanes.parallaxX + wallpaperPlanes.wallpaperW
                            y: wallpaperPlanes.parallaxY + wallpaperPlanes.wallpaperH
                            imageSource: (wallpaperPlanes.tilesVisible && !bgRoot.wallpaperSafetyTriggered) ? bgRoot.wallpaperPath : ""
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop
                            transform: Scale {
                                xScale: -1
                                yScale: -1
                                origin.x: bottomRightTile.width / 2
                                origin.y: bottomRightTile.height / 2
                            }
                        }
                    }

                    // A single highly-optimized GaussianBlur to blur all 8 outer tiles at 1/4 texture size for maximum performance
                    GaussianBlur {
                        id: outerTilesBlur
                        anchors.fill: parent
                        source: ShaderEffectSource {
                            sourceItem: outerTilesContainer
                            hideSource: false
                            smooth: true
                            textureSize: Qt.size(parent.width / 4, parent.height / 4)
                        }
                        radius: 40
                        samples: 81
                        visible: outerTilesContainer.visible
                        opacity: wallpaperPlanes.scaleProgress
                    }

                    // Mask rectangle for rounded clip — must be a real scene Item with layer.enabled
                    Rectangle {
                        id: centralClipMask
                        x: 0
                        y: 0
                        width: centralWallpaperClipRect.width
                        height: centralWallpaperClipRect.height
                        radius: centralWallpaperClipRect.radius
                        visible: false
                        layer.enabled: true
                    }

                    Rectangle {
                        id: centralWallpaperClipRect
                        x: Config.options.background.zoomOutStyle !== 1 ? 0 : wallpaperPlanes.parallaxX
                        y: Config.options.background.zoomOutStyle !== 1 ? 0 : wallpaperPlanes.parallaxY
                        width: Config.options.background.zoomOutStyle !== 1 ? bgRoot.screen.width : wallpaperPlanes.wallpaperW
                        height: Config.options.background.zoomOutStyle !== 1 ? bgRoot.screen.height : wallpaperPlanes.wallpaperH
                        color: "transparent"
                        radius: Config.options.background.zoomOutStyle === 0 ? wallpaperItem.wallpaperClipRadius : 0

                        layer.enabled: radius > 0
                        layer.effect: OpacityMask {
                            maskSource: centralClipMask
                        }


                        Behavior on x {
                            NumberAnimation {
                                duration: 600
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on y {
                            NumberAnimation {
                                duration: 600
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on width {
                            NumberAnimation {
                                duration: 800
                                easing.type: Easing.OutCubic
                            }
                        }
                        Behavior on height {
                            NumberAnimation {
                                duration: 800
                                easing.type: Easing.OutCubic
                            }
                        }

                        TransitionImage {
                            id: wallpaper
                            // Style 0: Centered when zoomed out, follows parallax when zoomed in
                            // Style 1: Fills the clip wrapper perfectly
                            x: Config.options.background.zoomOutStyle !== 1 ? (wallpaperItem.wallpaperZoomedOut ? -bgRoot.movableXSpace : wallpaperPlanes.parallaxX) : 0
                            y: Config.options.background.zoomOutStyle !== 1 ? (wallpaperItem.wallpaperZoomedOut ? -bgRoot.movableYSpace : wallpaperPlanes.parallaxY) : 0
                            width: Config.options.background.zoomOutStyle !== 1 ? wallpaperPlanes.wallpaperW : parent.width
                            height: Config.options.background.zoomOutStyle !== 1 ? wallpaperPlanes.wallpaperH : parent.height

                            visible: opacity > 0 && !bgRoot.wallpaperIsVideo
                            opacity: (status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0

                            property int chunkSize: Config?.options.bar.workspaces.shown ?? 10
                            property int lower: Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize
                            property int upper: Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
                            property int range: Math.max(1, upper - lower)
                            property real valueX: {
                                let result = 0.5;
                                if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax)
                                    result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                                return result;
                            }
                            property real sidebarOffsetX: {
                                if (!Config.options.background.parallax.enableSidebar)
                                    return 0;
                                return (0.15 * GlobalStates.effectiveRightOpen - 0.15 * GlobalStates.effectiveLeftOpen);
                            }
                            property real valueY: {
                                let result = 0.5;
                                if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax)
                                    result = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                                return result;
                            }
                            property real effectiveValueX: Math.max(0, Math.min(1, valueX)) + sidebarOffsetX
                            property real effectiveValueY: Math.max(0, Math.min(1, valueY))

                            imageSource: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                            animated: Config.options.background.animateWallpaperChanges
                            fillMode: Image.PreserveAspectCrop

                            Behavior on x {
                                NumberAnimation {
                                    duration: 600
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on y {
                                NumberAnimation {
                                    duration: 600
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on width {
                                NumberAnimation {
                                    duration: 800
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on height {
                                NumberAnimation {
                                    duration: 800
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }

                        Loader {
                            id: blurLoader
                            active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                            anchors.fill: parent
                            scale: GlobalStates.screenLocked ? Config.options.lock.blur.extraZoom : 1
                            Behavior on scale {
                                NumberAnimation {
                                    id: scaleAnim
                                    duration: 400
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
                                }
                            }
                            opacity: GlobalStates.screenLocked ? 1.0 : 0.0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutCubic
                                }
                            }
                            sourceComponent: GaussianBlur {
                                source: ShaderEffectSource {
                                    sourceItem: wallpaper
                                    textureSize: Qt.size(centralWallpaperClipRect.width / 4, centralWallpaperClipRect.height / 4)
                                    smooth: true
                                    recursive: true
                                }
                                radius: Math.round(Config.options.lock.blur.radius / 4)
                                samples: Math.round(radius * 2 + 1)

                                Rectangle {
                                    opacity: 1.0
                                    anchors.fill: parent
                                    color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                                }
                            }
                        }

                        WidgetCanvas {
                            id: widgetCanvas
                            scale: 1 - (defaultRatio - 1)
                            Behavior on scale {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                bottom: parent.bottom
                                horizontalCenter: undefined
                                verticalCenter: undefined
                                readonly property real parallaxFactor: Config.options.background.parallax.widgetsFactor
                                leftMargin: {
                                    const xOnWallpaper = bgRoot.movableXSpace;
                                    const extraMove = (wallpaper.effectiveValueX * 2 * bgRoot.movableXSpace) * (parallaxFactor - 1);
                                    return xOnWallpaper - extraMove;
                                }
                                topMargin: {
                                    const yOnWallpaper = bgRoot.movableYSpace;
                                    const extraMove = (wallpaper.effectiveValueY * 2 * bgRoot.movableYSpace) * (parallaxFactor - 1);
                                    return yOnWallpaper - extraMove;
                                }
                                Behavior on leftMargin {
                                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                }
                                Behavior on topMargin {
                                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                                }
                            }
                            width: parent.width
                            height: parent.height
                            states: State {
                                name: "centered"
                                when: GlobalStates.screenLocked || bgRoot.wallpaperSafetyTriggered
                                PropertyChanges {
                                    target: widgetCanvas
                                    width: parent.width
                                    height: parent.height
                                }
                                AnchorChanges {
                                    target: widgetCanvas
                                    anchors {
                                        left: undefined
                                        right: undefined
                                        top: undefined
                                        bottom: undefined
                                        horizontalCenter: parent.horizontalCenter
                                        verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            transitions: Transition {
                                PropertyAnimation {
                                    properties: "width,height"
                                    duration: Appearance.animation.elementMove.duration
                                    easing.type: Appearance.animation.elementMove.type
                                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                }
                                AnchorAnimation {
                                    duration: Appearance.animation.elementMove.duration
                                    easing.type: Appearance.animation.elementMove.type
                                    easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                                }
                            }

                            FadeLoader {
                                shown: Config.options.background.widgets.weather.enable
                                sourceComponent: WeatherWidget {
                                    screenWidth: bgRoot.screen.width
                                    screenHeight: bgRoot.screen.height
                                    scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                    scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                    wallpaperScale: bgRoot.effectiveWallpaperScale
                                }
                            }

                            FadeLoader {
                                shown: Config.options.background.widgets.clock.enable
                                sourceComponent: ClockWidget {
                                    screenWidth: bgRoot.screen.width
                                    screenHeight: bgRoot.screen.height
                                    scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                    scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                    wallpaperScale: bgRoot.effectiveWallpaperScale
                                    wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                                }
                            }

                            Timer {
                                id: mediaTimer
                                interval: 200
                                onTriggered: mediaLoader.enableLoading = true
                            }

                            FadeLoader {
                                id: mediaLoader
                                property bool enableLoading: true
                                shown: Config.options.background.widgets.media.enable && enableLoading
                                sourceComponent: Config.options.background.widgets.media.style === "expressive" ? expressiveMediaWidget : circularMediaWidget

                                Component {
                                    id: circularMediaWidget
                                    MediaWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: expressiveMediaWidget
                                    ExpressiveMediaWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }
                                onLoaded: {
                                    if (item && item.requestReset) {
                                        item.requestReset.connect(() => { // hard reset
                                            mediaLoader.enableLoading = false;
                                            mediaTimer.running = true;
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }

            GlobalShortcut {
                name: "mediaModeToggle"
                description: "Toggles media mode on press"

                onPressed: {
                    if (!monitor.focused && Config.options.background.mediaMode.togglePerMonitor)
                        return;
                    mediaModeLoader.active = !mediaModeLoader.active;
                    LyricsService.mediaModeOpenCount += mediaModeLoader.active ? 1 : -1;
                }
            }

            Loader {
                id: mediaModeLoader
                anchors.fill: parent
                active: false
                asynchronous: true
                sourceComponent: MediaMode {}
                opacity: status === Loader.Ready ? 1 : 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    // --- Compositor-level blur overlay over active windows and wallpaper ---
    // Uses the quickshell:workspaceBlurOverlay namespace to trigger Hyprland's hardware-accelerated
    // blur and dimming over the entire screen when the overview or cheatsheet is active (Mirrored style only).
    Variants {
        id: blurOverlayVariant
        model: Quickshell.screens

        PanelWindow {
            id: blurOverlayWindow

            required property var modelData
            screen: modelData

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:workspaceBlurOverlay"
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property bool animEnabled: Config.options.background.zoomOutEnabled
            readonly property bool isMirroredStyle: Config.options.background.zoomOutStyle === 1
            readonly property bool isActive: animEnabled && isMirroredStyle && (GlobalStates.cheatsheetOpen || GlobalStates.overviewOpen)

            property real zoomProgress: isActive ? 1.0 : 0.0
            Behavior on zoomProgress {
                NumberAnimation {
                    duration: 375
                    easing.type: Easing.OutCubic
                }
            }

            visible: isActive || zoomProgress > 0.001

            Rectangle {
                id: overlayDimRect
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.25)
                opacity: blurOverlayWindow.zoomProgress
            }
        }
    }
}
