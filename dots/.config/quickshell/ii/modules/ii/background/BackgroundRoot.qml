pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.common.functions as CF

import qs.modules.ii.background.widgets
import qs.modules.ii.background.wallpaper
import qs.modules.ii.background.lockscreen
import qs.modules.ii.background.parallax
import qs.modules.ii.background.overview
import qs.modules.ii.background.blur

PanelWindow {
    id: bgRoot

    required property var modelData
    required property var widgetStateManager

    property bool anyWidgetIsDragging: widgetCanvas.draggingActive
    property real baseWallpaperScale: 1 // Calculated scale from wallpaper size
    property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
    property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated

    // State controllers
    WallpaperSizeProbe {
        id: getWallpaperSizeProc
        path: bgRoot.wallpaperPath
        onSizeDetected: function(w, h) {
            bgRoot.wallpaperWidth = w;
            bgRoot.wallpaperHeight = h;
            bgRoot.recalcWallpaperScale();
        }
    }

    LockAnimController {
        id: lockAnim
        baseScale: bgRoot.baseWallpaperScale
        hasWindowsInActiveWorkspace: bgRoot.hasWindowsInActiveWorkspace
        onRequestRipple: function(x, y) {
            lockScreenRippleEffect.startRipple(x, y);
        }
    }

    ParallaxController {
        id: parallax
        movableXSpace: bgRoot.movableXSpace
        movableYSpace: bgRoot.movableYSpace
        firstWorkspaceId: bgRoot.firstWorkspaceId
        lastWorkspaceId: bgRoot.lastWorkspaceId
        chunkSize: bgRoot.chunkSize
        verticalParallax: bgRoot.verticalParallax
        parallaxFrozen: lockAnim.parallaxFrozen
        wallpaperCentered: lockAnim.wallpaperCentered
        activeWorkspaceId: {
            let activeId = bgRoot.monitor && bgRoot.monitor.activeWorkspace ? bgRoot.monitor.activeWorkspace.id : 1;
            return activeId > 1000000 ? (2147483647 - activeId) : activeId;
        }
    }

    OverviewZoomController {
        id: ovZoom
        wallpaperZoomedOut: (wallpaperImage ? wallpaperImage.wallpaperZoomedOut : false)
        minSafeScale: bgRoot.minSafeScale
        zoomOutCoverScale: (wallpaperImage && wallpaperImage.zoomOutCoverScale ? wallpaperImage.zoomOutCoverScale : 1.05)
        screenWidth: bgRoot.screen.width
        screenHeight: bgRoot.screen.height
    }

    // Publish zoom state so OverviewWindowTransition can sync its animation
    Binding {
        target: GlobalStates
        property: "overviewZoomScale"
        value: ovZoom.scaleValue
        when: (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") == (bgRoot.monitor ? bgRoot.monitor.name : "")
    }
    Binding {
        target: GlobalStates
        property: "overviewZoomOriginX"
        value: ovZoom.scaleOriginX
        when: (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") == (bgRoot.monitor ? bgRoot.monitor.name : "")
    }
    Binding {
        target: GlobalStates
        property: "overviewZoomOriginY"
        value: ovZoom.scaleOriginY
        when: (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") == (bgRoot.monitor ? bgRoot.monitor.name : "")
    }

    // Expose properties from controllers for backward compatibility / internal bindings
    readonly property bool lockAnimationActive: lockAnim.lockAnimationActive
    readonly property bool parallaxFrozen: lockAnim.parallaxFrozen
    readonly property bool rippleActive: lockAnim.rippleActive
    readonly property real effectiveWallpaperScale: lockAnim.effectiveWallpaperScale

    // Hide when fullscreen
    property var workspacesForMonitor: Hyprland.workspaces.values.filter(function(workspace) { return workspace.monitor && workspace.monitor.name == monitor.name; })
    property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(function(workspace) { return ((workspace.toplevels.values.filter(function(window) { return window.wayland && window.wayland.fullscreen; })[0] != undefined) && workspace.active); })[0]
    property bool isFullscreen: activeWorkspaceWithFullscreen != undefined
    property var activeWorkspace: workspacesForMonitor.filter(function(workspace) { return workspace.active; })[0]
    property bool hasWindowsInActiveWorkspace: {
        if (activeWorkspace == undefined) return false;
        let activeId = activeWorkspace.id;
        if (activeId > 1000000) activeId = 2147483647 - activeId;
        return HyprlandData.windowList.some(function(w) { return w.workspace.id === activeId; });
    }
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

    // Workspaces calculations
    property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
    readonly property bool isMonitorFocused: (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") == (monitor ? monitor.name : "")
    readonly property bool loopEnabled: Config.options.background.parallax.loop
    readonly property var intensitySpans: [20, 15, 12, 10, 8, 7, 5, 4, 3, 2]
    readonly property int chunkSize: {
        let intensity = Config.options.background.parallax.intensity;
        if (intensity === undefined || isNaN(intensity)) intensity = 4;
        let idx = Math.max(1, Math.min(10, intensity)) - 1;
        return intensitySpans[idx] !== undefined ? intensitySpans[idx] : 10;
    }
    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap
    readonly property var workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property int monitorIndex: Quickshell.screens.indexOf(modelData)
    readonly property int workspaceOffset: useWorkspaceMap ? workspaceMap[monitorIndex] : 0
    readonly property int workspaceGroup: {
        if (!loopEnabled)
            return 0;
        let activeId = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined;
        if (!activeId)
            return 0;
        if (activeId > 1000000)
            activeId = 2147483647 - activeId;
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

    // Wallpaper options
    property bool wallpaperIsVideo: {
        const path = Config.options && Config.options.background && Config.options.background.wallpaperPath ? Config.options.background.wallpaperPath : "";
        return path !== "" && (path.endsWith(".mp4") || path.endsWith(".webm") || path.endsWith(".mkv") || path.endsWith(".avi") || path.endsWith(".mov"));
    }
    property string wallpaperPath: {
        const rawPath = wallpaperIsVideo
            ? (Config.options && Config.options.background && Config.options.background.thumbnailPath ? Config.options.background.thumbnailPath : "")
            : (Config.options && Config.options.background && Config.options.background.wallpaperPath ? Config.options.background.wallpaperPath : "");
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
    property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * baseWallpaperScale) - screen.width) / 2
    property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * baseWallpaperScale) - screen.height) / 2

    readonly property real minSafeScale: {
        const w = wallpaperWidth / wallpaperToScreenRatio * baseWallpaperScale;
        const h = wallpaperHeight / wallpaperToScreenRatio * baseWallpaperScale;
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

    property var zoomLevels: ({
        "in": {
            default: 1.04,
            zoomed: 1
        },
        "out": {
            default: 1,
            zoomed: 1.01
        }
    })

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
    WlrLayershell.layer: WlrLayer.Bottom
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
    }
    onPreferredWallpaperScaleChanged: bgRoot.recalcWallpaperScale()

    function recalcWallpaperScale() {
        const width = bgRoot.wallpaperWidth;
        const height = bgRoot.wallpaperHeight;
        const screenW = bgRoot.screen.width;
        const screenH = bgRoot.screen.height;
        if (width <= 0 || height <= 0) return;
        
        let targetScale = 1.0;
        if (Config.options.background.scaleLargeWallpapers) {
            if (width <= screenW || height <= screenH) {
                targetScale = Math.max(screenW / width, screenH / height);
            } else {
                targetScale = Math.min(bgRoot.preferredWallpaperScale, width / screenW, height / screenH);
            }
        }
        
        if (Config.options.background.blurWhenWindowsOpen || Config.options.lock.blur.enable) {
            targetScale *= 1.03;
        }
        
        bgRoot.baseWallpaperScale = targetScale;
    }

    // Wallpaper zoom scale
    function updateZoomScale() {
        getWallpaperSizeProc.path = bgRoot.wallpaperPath;
        getWallpaperSizeProc.running = true;
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

    LockRippleEffect {
        id: lockScreenRippleEffect
    }

    Item {
        id: contentRoot
        anchors.fill: parent
        visible: GlobalStates.screenLocked || !bgRoot.deferredFullscreen || !(Config && Config.options && Config.options.background && Config.options.background.hideWhenFullscreen)

        WallpaperImage {
            id: wallpaperImage
            screen: bgRoot.screen
            wallpaperPath: bgRoot.wallpaperPath
            wallpaperIsVideo: bgRoot.wallpaperIsVideo
            wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
            preferredWallpaperScale: bgRoot.preferredWallpaperScale
            effectiveWallpaperScale: bgRoot.effectiveWallpaperScale
            baseWallpaperScale: bgRoot.baseWallpaperScale
            wallpaperWidth: bgRoot.wallpaperWidth
            wallpaperHeight: bgRoot.wallpaperHeight
            wallpaperToScreenRatio: bgRoot.wallpaperToScreenRatio
            movableXSpace: bgRoot.movableXSpace
            movableYSpace: bgRoot.movableYSpace
            minSafeScale: bgRoot.minSafeScale
            parallaxX: parallax.parallaxX
            parallaxY: parallax.parallaxY
            scaleValue: ovZoom.scaleValue
            scaleOriginX: ovZoom.scaleOriginX
            scaleOriginY: ovZoom.scaleOriginY
            scaleProgress: ovZoom.scaleProgress
            anyWidgetIsDragging: bgRoot.anyWidgetIsDragging
            mediaModeOpen: bgRoot.mediaModeOpen
            lockAnimationActive: bgRoot.lockAnimationActive
            hasWindowsInActiveWorkspace: bgRoot.hasWindowsInActiveWorkspace
        }

        BarGradientOverlay {
            sourceItem: wallpaperImage.clipRectItem
            screenWidth: bgRoot.screen.width
            screenHeight: bgRoot.screen.height
        }

        WidgetCanvas {
            id: widgetCanvas
            scale: 1 - (bgRoot.defaultRatio - 1)
            layer.enabled: false

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
                    const extraMove = (parallax.effectiveValueX * 2 * bgRoot.movableXSpace) * (parallaxFactor - 1);
                    return xOnWallpaper - extraMove;
                }
                topMargin: {
                    const yOnWallpaper = bgRoot.movableYSpace;
                    const extraMove = (parallax.effectiveValueY * 2 * bgRoot.movableYSpace) * (parallaxFactor - 1);
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
                when: GlobalStates.lockScreenCentered || GlobalStates.workspaceRestoreInProgress || bgRoot.wallpaperSafetyTriggered
                PropertyChanges {
                    target: widgetCanvas
                    anchors.leftMargin: 0
                    anchors.rightMargin: 0
                    anchors.topMargin: 0
                    anchors.bottomMargin: 0
                }
            }

            transitions: Transition {
                PropertyAnimation {
                    properties: "anchors.leftMargin,anchors.rightMargin,anchors.topMargin,anchors.bottomMargin"
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }

            Repeater {
                model: widgetStateManager.model
                delegate: WidgetDelegate {
                    widgetListModel: widgetStateManager.model
                    widgetSizes: widgetStateManager.widgetSizes
                    widgetSizesVersion: widgetStateManager.widgetSizesVersion
                    screenWidth: bgRoot.screen.width
                    screenHeight: bgRoot.screen.height
                    wallpaperScale: bgRoot.effectiveWallpaperScale
                    wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                    lockAnimationActive: bgRoot.lockAnimationActive
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
                GlobalStates.mediaModeCount = Math.max(0, GlobalStates.mediaModeCount + (mediaModeLoader.active ? 1 : -1));
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
