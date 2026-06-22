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
            property bool isFullscreen: activeWorkspaceWithFullscreen != undefined
            property var activeWorkspace: workspacesForMonitor.filter(workspace => workspace.active)[0]
            property bool hasWindowsInActiveWorkspace: activeWorkspace != undefined && HyprlandData.windowList.some(w => w.workspace.id === activeWorkspace.id)
            // Deferred to avoid Wayland dispatch reentrancy crash in PanelWindow visibility
            property bool deferredFullscreen: false
            Timer {
                id: fullscreenDeferTimer
                interval: 50
                repeat: false
                onTriggered: bgRoot.deferredFullscreen = bgRoot.isFullscreen
            }
            onIsFullscreenChanged: fullscreenDeferTimer.restart()
            visible: true

            // Workspaces
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            readonly property bool isMonitorFocused: Hyprland.focusedMonitor?.name == monitor?.name
            readonly property bool loopEnabled: Config.options.background.parallax.loop
            readonly property var intensitySpans: [20, 15, 12, 10, 8, 7, 5, 4, 3, 2]
            readonly property int chunkSize: {
                let intensity = Config.options.background.parallax.intensity;
                if (intensity === undefined || isNaN(intensity)) intensity = 4;
                let idx = Math.max(1, Math.min(10, intensity)) - 1;
                return intensitySpans[idx] ?? 10;
            }
            readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
            readonly property list<var> workspaceMap: Config.options.bar.workspaces.workspaceMap
            readonly property int monitorIndex: Quickshell.screens.indexOf(modelData)
            readonly property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0
            readonly property int workspaceGroup: {
                if (!loopEnabled)
                    return 0;
                let activeId = monitor?.activeWorkspace?.id;
                if (!activeId)
                    return 0;
                if (activeId <= workspaceOffset)
                    return 0;
                if (useWorkspaceMap && workspaceMap.length > monitorIndex + 1) {
                    let nextMonitorStart = workspaceMap[monitorIndex + 1];
                    if (activeId > nextMonitorStart)
                        return 0;
                }
                let group = Math.floor((activeId - workspaceOffset - 1) / chunkSize);
                return Math.max(0, group);
            }
            property int firstWorkspaceId: workspaceOffset + workspaceGroup * chunkSize + 1
            property int lastWorkspaceId: workspaceOffset + (workspaceGroup + 1) * chunkSize

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
                    zoomed: 1.01
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
                if (!mediaModeOpen && Config.options.appearance.palette.type.startsWith("scheme")) {
                    Wallpapers.apply(Config.options.background.wallpaperPath);
                    LyricsService.shellColorChanged = false;
                }
            }

            Component.onCompleted: {
                if (!mediaModeOpen && Config.options.appearance.palette.type.startsWith("scheme")) {
                    Wallpapers.apply(Config.options.background.wallpaperPath);
                }
            }

            Item {
                id: contentRoot
                anchors.fill: parent
                visible: GlobalStates.screenLocked || !bgRoot.deferredFullscreen || !Config?.options.background.hideWhenFullscreen

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
                        // Performance: disable expensive mipmapping on background blur layer
                        mipmap: false
                        antialiasing: false
                        sourceSize: Qt.size(bgRoot.screen.width > 0 ? Math.round(bgRoot.screen.width / 4) : 480, bgRoot.screen.height > 0 ? Math.round(bgRoot.screen.height / 4) : 270)
                    }
                    Loader {
                        id: bgWallpaperBlurLoader
                        anchors.fill: bgWallpaperBlurred
                        active: wallpaperItem.wallpaperZoomedOut || opacity > 0.01
                        opacity: wallpaperItem.wallpaperZoomedOut ? 1.0 : 0.0
                        Behavior on opacity {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        sourceComponent: MultiEffect {
                            anchors.fill: parent
                            source: bgWallpaperBlurred
                            blurEnabled: true
                            // Performance: MultiEffect uses separable blur, ~2-3x faster than GaussianBlur
                            blurMax: 75
                            blur: 0.7

                            Rectangle {
                                anchors.fill: parent
                                color: "#000000"
                                opacity: 0.24
                            }
                        }
                    }

                    // Shared zoom-out state — gated on zoomOutEnabled
                    readonly property bool scratchpadOpen: {
                        if (!HyprlandData.monitors)
                            return false;
                        return HyprlandData.monitors.some(mon => mon.specialWorkspace && mon.specialWorkspace.name !== "");
                    }
                    readonly property bool wallpaperZoomedOut: Config.options.background.zoomOutEnabled && (GlobalStates.cheatsheetOpen || GlobalStates.overviewOpen || scratchpadOpen) && bgRoot.isMonitorFocused

                    // Animated clip radius — drives both the border-radius clip and tile visibility
                    property real wallpaperClipRadius: wallpaperZoomedOut ? Appearance.rounding.windowRounding : 0
                    Behavior on wallpaperClipRadius {
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
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
                        property real parallaxX: GlobalStates.screenLocked ? -(bgRoot.movableXSpace) : -(bgRoot.movableXSpace) - (wallpaper.effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                        property real parallaxY: GlobalStates.screenLocked ? -(bgRoot.movableYSpace) : -(bgRoot.movableYSpace) - (wallpaper.effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
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
                            // Style 1: use zoom-to-fill to cover screen without mirrored tiles
                            if (Config.options.background.zoomOutStyle === 1)
                                return Math.max(0.85, zoomOutCoverScale);
                            return Math.max(0.85, bgRoot.minSafeScale * 0.85);
                        }
                        Behavior on scaleValue {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
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

                        // --- STYLE 1: Zoom-to-fill (no mirrored tiles) ---
                        // When zoomed out, the central wallpaper scales to cover the entire screen
                        // without parallax movement, eliminating the need for expensive mirrored tiles.
                        // The wallpaper already uses PreserveAspectCrop and sufficient scale.
                        property real zoomOutCoverScale: {
                            // Ensure the wallpaper always covers the screen during zoom-out,
                            // even when parallax is disabled or the wallpaper is smaller than the screen.
                            const w = bgRoot.wallpaperWidth / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale;
                            const h = bgRoot.wallpaperHeight / bgRoot.wallpaperToScreenRatio * bgRoot.effectiveWallpaperScale;
                            if (w <= 0 || h <= 0)
                                return 1.0;
                            // Scale to cover the screen, adding a small margin for safety
                            return Math.max(bgRoot.screen.width / w, bgRoot.screen.height / h) * 1.05;
                        }

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

                        ShaderEffectSource {
                            id: windowBlurSource
                            sourceItem: windowBlurEffect.visible ? centralWallpaperClipRect : null
                            sourceRect: {
                                if (Config.options.background.zoomOutStyle === 1) {
                                    return Qt.rect(-centralWallpaperClipRect.x, -centralWallpaperClipRect.y, bgRoot.screen.width, bgRoot.screen.height);
                                }
                                return Qt.rect(0, 0, centralWallpaperClipRect.width, centralWallpaperClipRect.height);
                            }
                            width: bgRoot.screen.width
                            height: bgRoot.screen.height
                            live: windowBlurEffect.visible
                            hideSource: false
                        }

                        Item {
                            id: windowBlurMask
                            width: bgRoot.screen.width
                            height: bgRoot.screen.height
                            visible: false

                            Rectangle {
                                x: windowBlurEffect.wbLeft
                                y: windowBlurEffect.wbTop
                                width: parent.width - windowBlurEffect.wbLeft - windowBlurEffect.wbRight
                                height: parent.height - windowBlurEffect.wbTop - windowBlurEffect.wbBottom
                                color: "black"
                                radius: {
                                    if (wallpaperItem.wallpaperClipRadius > 0)
                                        return wallpaperItem.wallpaperClipRadius;
                                    if (Config.options.appearance.fakeScreenRounding > 0)
                                        return Appearance.rounding.screenRounding;
                                    return 0;
                                }
                            }
                            layer.enabled: true
                        }

                        StyledRectangularShadow {
                            id: centralWallpaperShadow
                            target: centralWallpaperClipRect
                            blur: 32 * wallpaperPlanes.scaleProgress
                            offset: Qt.vector2d(0, 4 * wallpaperPlanes.scaleProgress)
                            visible: Config.options.background.zoomOutStyle === 0 && wallpaperPlanes.scaleProgress > 0.01
                            opacity: wallpaperPlanes.scaleProgress
                        }

                        Rectangle {
                            id: centralWallpaperClipRect
                            x: Config.options.background.zoomOutStyle !== 1 ? 0 : wallpaperPlanes.parallaxX
                            y: Config.options.background.zoomOutStyle !== 1 ? 0 : wallpaperPlanes.parallaxY
                            width: Config.options.background.zoomOutStyle !== 1 ? bgRoot.screen.width : wallpaperPlanes.wallpaperW
                            height: Config.options.background.zoomOutStyle !== 1 ? bgRoot.screen.height : wallpaperPlanes.wallpaperH
                            color: "transparent"
                            radius: Config.options.background.zoomOutStyle === 0 ? wallpaperItem.wallpaperClipRadius : 0
                            clip: Config.options.background.zoomOutStyle !== 1
                            border.color: CF.ColorUtils.transparentize(Appearance.colors.colPrimary, 0.35)
                            border.width: 1.5 * wallpaperPlanes.scaleProgress

                            layer.enabled: radius > 0
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: centralClipMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }

                            Behavior on x {
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on y {
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on width {
                                NumberAnimation {
                                    duration: 500
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on height {
                                NumberAnimation {
                                    duration: 500
                                    easing.type: Easing.OutCubic
                                }
                            }

                            TransitionImage {
                                id: wallpaper
                                // Style 0: Centered when zoomed out, follows parallax when zoomed in
                                // Style 1: Fills the clip wrapper perfectly, no parallax during zoom-out
                                x: {
                                    if (Config.options.background.zoomOutStyle === 1) {
                                        // In style 1, wallpaper fills the clip rect; no parallax offset needed
                                        return 0;
                                    }
                                    // Style 0: centered when zoomed out, parallax when zoomed in
                                    return wallpaperItem.wallpaperZoomedOut ? -bgRoot.movableXSpace : wallpaperPlanes.parallaxX;
                                }
                                y: {
                                    if (Config.options.background.zoomOutStyle === 1) {
                                        return 0;
                                    }
                                    return wallpaperItem.wallpaperZoomedOut ? -bgRoot.movableYSpace : wallpaperPlanes.parallaxY;
                                }
                                width: Config.options.background.zoomOutStyle !== 1 ? wallpaperPlanes.wallpaperW : parent.width
                                height: Config.options.background.zoomOutStyle !== 1 ? wallpaperPlanes.wallpaperH : parent.height

                                visible: opacity > 0 && !bgRoot.wallpaperIsVideo
                                opacity: (wallpaper.status === Image.Ready && !bgRoot.wallpaperIsVideo) ? 1 : 0
                                sourceSize: Qt.size(bgRoot.screen.width > 0 ? Math.round(bgRoot.screen.width * bgRoot.preferredWallpaperScale) : 1920, bgRoot.screen.height > 0 ? Math.round(bgRoot.screen.height * bgRoot.preferredWallpaperScale) : 1080)

                                property int chunkSize: bgRoot.chunkSize
                                property int lower: Math.floor(bgRoot.firstWorkspaceId / chunkSize) * chunkSize
                                property int upper: Math.ceil(bgRoot.lastWorkspaceId / chunkSize) * chunkSize
                                property int range: Math.max(1, upper - lower)
                                property real valueX: {
                                    let result = 0.5;
                                    if (Config.options.background.parallax.enableWorkspace && !bgRoot.verticalParallax) {
                                        let ratio = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                                        result = Config.options.background.parallax.invertHorizontal ? (1.0 - ratio) : ratio;
                                    }
                                    return result;
                                }
                                property real sidebarOffsetX: {
                                    if (!Config.options.background.parallax.enableSidebar)
                                        return 0;
                                    return (0.15 * GlobalStates.effectiveRightOpen - 0.15 * GlobalStates.effectiveLeftOpen);
                                }
                                property real valueY: {
                                    let result = 0.5;
                                    if (Config.options.background.parallax.enableWorkspace && bgRoot.verticalParallax) {
                                        let ratio = ((bgRoot.monitor.activeWorkspace?.id - lower) / range);
                                        result = Config.options.background.parallax.invertVertical ? (1.0 - ratio) : ratio;
                                    }
                                    return result;
                                }
                                property real effectiveValueX: Math.max(0, Math.min(1, valueX)) + sidebarOffsetX
                                property real effectiveValueY: Math.max(0, Math.min(1, valueY))

                                imageSource: bgRoot.wallpaperSafetyTriggered ? "" : bgRoot.wallpaperPath
                                animated: Config.options.background.animateWallpaperChanges
                                fillMode: Image.PreserveAspectCrop
                                // Performance: disable mipmapping on the central wallpaper
                                mipmap: false
                                antialiasing: false

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 400
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on y {
                                    NumberAnimation {
                                        duration: 400
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 500
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on height {
                                    NumberAnimation {
                                        duration: 500
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            Loader {
                                id: blurLoader
                                active: Config.options.lock.blur.enable && (GlobalStates.screenLocked || scaleAnim.running)
                                anchors.fill: wallpaper
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
                                sourceComponent: MultiEffect {
                                    source: wallpaper
                                    blurEnabled: true
                                    // Performance: MultiEffect uses separable blur, ~2-3x faster than GaussianBlur
                                    blurMax: 64
                                    blur: Math.min(Config.options.lock.blur.radius / 4, 24) / 64

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
                                        leftMargin: 0
                                        rightMargin: 0
                                        topMargin: 0
                                        bottomMargin: 0
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
                                        properties: "width,height,leftMargin,rightMargin,topMargin,bottomMargin"
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

                        MultiEffect {
                            id: windowBlurEffect
                            anchors.fill: parent

                            readonly property bool barVertical: wallpaperPlanes.barVertical
                            readonly property bool barBottom: wallpaperPlanes.barBottom
                            readonly property int barSz: wallpaperPlanes.barSize
                            readonly property int gp: wallpaperPlanes.gap
                            readonly property bool barEffective: GlobalStates.barOpen && !GlobalStates.screenLocked

                            readonly property int baseMargin: (Config.options.appearance.fakeScreenRounding === 3) ? Config.options.appearance.wrappedFrameThickness : gp
                            readonly property real leftSidebarOffset: (GlobalStates.policiesPinned && !GlobalStates.policiesDetached && GlobalStates.animatedLeftSidebarWidth > 0 && bgRoot.screen && bgRoot.screen.name === GlobalStates.activeLeftSidebarMonitor) ? GlobalStates.animatedLeftSidebarWidth : 0
                            readonly property real rightSidebarOffset: 0

                            readonly property int wbLeft: Math.max(baseMargin, (barEffective && barVertical && !barBottom) ? barSz : 0, leftSidebarOffset)
                            readonly property int wbRight: Math.max(baseMargin, (barEffective && barVertical && barBottom) ? barSz : 0, rightSidebarOffset)
                            readonly property int wbTop: Math.max(baseMargin, (barEffective && !barVertical && !barBottom) ? barSz : 0)
                            readonly property int wbBottom: Math.max(baseMargin, (barEffective && !barVertical && barBottom) ? barSz : 0)

                            property bool shouldBlur: Config.options.background.blurWhenWindowsOpen && bgRoot.hasWindowsInActiveWorkspace && !GlobalStates.screenLocked && !bgRoot.overviewOpen
                            visible: shouldBlur || opacity > 0.01
                            opacity: shouldBlur ? 1.0 : 0.0
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.OutCubic
                                }
                            }

                            source: windowBlurSource
                            blurEnabled: true
                            blurMax: 64
                            blur: Config.options.background.blurWhenWindowsOpenRadius / 100.0

                            maskEnabled: true
                            maskSource: windowBlurMask

                            Rectangle {
                                x: windowBlurEffect.wbLeft
                                y: windowBlurEffect.wbTop
                                width: parent.width - windowBlurEffect.wbLeft - windowBlurEffect.wbRight
                                height: parent.height - windowBlurEffect.wbTop - windowBlurEffect.wbBottom
                                radius: {
                                    if (wallpaperItem.wallpaperClipRadius > 0)
                                        return wallpaperItem.wallpaperClipRadius;
                                    if (Config.options.appearance.fakeScreenRounding > 0)
                                        return Appearance.rounding.screenRounding;
                                    return 0;
                                }
                                opacity: 1.0
                                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
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
                    opacity: mediaModeLoader.status === Loader.Ready ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }
    }

    // --- Compositor-level blur overlay over active windows and wallpaper ---
    // Uses the quickshell:workspaceBlurOverlay namespace to trigger Hyprland's hardware-accelerated
    // blur and dimming over the entire screen when the overview or cheatsheet is active (Mirrored style only).
    // Performance: simplified to reduce Wayland surface overhead. Only active for Mirrored style.
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

            readonly property bool barVertical: Config.options.bar.vertical
            readonly property bool barBottom: Config.options.bar.bottom
            readonly property int barSize: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
            readonly property int gap: Appearance.gapsOut
            readonly property bool barEffective: GlobalStates.barOpen && !GlobalStates.screenLocked

            readonly property int baseMargin: (Config.options.appearance.fakeScreenRounding === 3) ? Config.options.appearance.wrappedFrameThickness : gap
            readonly property real leftSidebarOffset: (GlobalStates.policiesPinned && !GlobalStates.policiesDetached && GlobalStates.animatedLeftSidebarWidth > 0 && screen && screen.name === GlobalStates.activeLeftSidebarMonitor) ? GlobalStates.animatedLeftSidebarWidth : 0
            readonly property real rightSidebarOffset: 0

            readonly property int wbLeft: Math.max(baseMargin, (barEffective && barVertical && !barBottom) ? barSize : 0, leftSidebarOffset)
            readonly property int wbRight: Math.max(baseMargin, (barEffective && barVertical && barBottom) ? barSize : 0, rightSidebarOffset)
            readonly property int wbTop: Math.max(baseMargin, (barEffective && !barVertical && !barBottom) ? barSize : 0)
            readonly property int wbBottom: Math.max(baseMargin, (barEffective && !barVertical && barBottom) ? barSize : 0)

            mask: Region {
                item: overlayDimRect
            }

            readonly property bool animEnabled: Config.options.background.zoomOutEnabled
            readonly property bool isMirroredStyle: Config.options.background.zoomOutStyle === 1
            readonly property bool isActive: animEnabled && isMirroredStyle && (GlobalStates.cheatsheetOpen || GlobalStates.overviewOpen) && (Hyprland.focusedMonitor?.name == Hyprland.monitorFor(modelData)?.name)

            visible: isActive || overlayDimRect.opacity > 0.01

            // Performance: use a simple Rectangle for dimming
            Rectangle {
                id: overlayDimRect
                x: blurOverlayWindow.wbLeft
                y: blurOverlayWindow.wbTop
                width: parent.width - blurOverlayWindow.wbLeft - blurOverlayWindow.wbRight
                height: parent.height - blurOverlayWindow.wbTop - blurOverlayWindow.wbBottom
                color: Qt.rgba(0, 0, 0, 0.25)
                opacity: blurOverlayWindow.isActive ? 1.0 : 0.0
                radius: {
                    if (Config.options.appearance.fakeScreenRounding > 0)
                        return Appearance.rounding.screenRounding;
                    return 0;
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }
}
