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

    property bool anyWidgetIsDragging: (widgetStateManager?.draggingActive) ?? false
    property real baseWallpaperScale: 1 // Calculated scale from wallpaper size
    property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
    property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
    // Those init values are the screen's, not the wallpaper file's, so the wallpaper plane changes
    // size the moment the probe answers. Effects that capture the plane into a texture must wait
    // for it: the capture is taken once, when the effect is created, and is never retaken, so a
    // plane that grows underneath one leaves a band the blurred texture no longer reaches.
    property bool wallpaperSizeKnown: false

    // State controllers
    WallpaperSizeProbe {
        id: getWallpaperSizeProc
        path: bgRoot.wallpaperPath
        onSizeDetected: function(w, h) {
            bgRoot.wallpaperWidth = w;
            bgRoot.wallpaperHeight = h;
            bgRoot.recalcWallpaperScale();
            bgRoot.wallpaperSizeKnown = true;
        }
        // A missing or failing `magick` must never keep the wallpaper effects switched off for the
        // whole session - let them capture the screen-sized guess instead.
        onExited: (exitCode, exitStatus) => {
            bgRoot.wallpaperSizeKnown = true;
        }
    }

    Timer {
        id: wallpaperProbeTimeout
        interval: 3000
        repeat: false
        onTriggered: bgRoot.wallpaperSizeKnown = true
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
        wallpaperIsVideo: bgRoot.videoEffectsDisabled
        activeWorkspaceId: {
            let activeId = bgRoot.monitor && bgRoot.monitor.activeWorkspace ? bgRoot.monitor.activeWorkspace.id : 1;
            return activeId > 1000000 ? (2147483647 - activeId) : activeId;
        }
    }

    OverviewBackgroundController {
        id: overviewController
        active: GlobalStates.overviewBackgroundActive && bgRoot.isMonitorFocused
        style: Config.options.background.overviewBackgroundStyle
        legacyStyle: Config.options.background.zoomOutStyle
        videoEffectsDisabled: bgRoot.videoEffectsDisabled
        screenWidth: bgRoot.screen.width
        screenHeight: bgRoot.screen.height
        wallpaperWidth: bgRoot.wallpaperWidth
        wallpaperHeight: bgRoot.wallpaperHeight
        baseWallpaperScale: bgRoot.baseWallpaperScale
        parallaxX: bgRoot.videoEffectsDisabled ? 0 : parallax.parallaxX
        parallaxY: bgRoot.videoEffectsDisabled ? 0 : parallax.parallaxY
        wallpaperPath: bgRoot.wallpaperPath
        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
    }

    readonly property bool isGnomeLikeOverview: overviewController.isGnomeLike

    // Publish the overview background transform for the focused monitor.
    Binding {
        target: GlobalStates
        property: "overviewZoomScale"
        value: bgRoot.isGnomeLikeOverview ? overviewController.scale : 1.0
        when: bgRoot.isMonitorFocused
    }
    Binding {
        target: GlobalStates
        property: "overviewZoomOriginX"
        value: bgRoot.isGnomeLikeOverview ? overviewController.scaleOriginX : 0.5
        when: bgRoot.isMonitorFocused
    }
    Binding {
        target: GlobalStates
        property: "overviewZoomOriginY"
        value: bgRoot.isGnomeLikeOverview ? overviewController.scaleOriginY : 0.5
        when: bgRoot.isMonitorFocused
    }

    // Expose properties from controllers for internal bindings
    readonly property bool lockAnimationActive: lockAnim.lockAnimationActive
    readonly property bool parallaxFrozen: lockAnim.parallaxFrozen
    readonly property bool rippleActive: lockAnim.rippleActive
    readonly property real effectiveWallpaperScale: lockAnim.effectiveWallpaperScale
    readonly property real overviewCoverScale: overviewController.overviewCoverScale

    // Hide when fullscreen
    property var workspacesForMonitor: Hyprland.workspaces.values.filter(function(workspace) { return workspace.monitor && workspace.monitor.name == monitor.name; })
    readonly property bool isFullscreen: {
        const wl = HyprlandData.windowList;
        const monitorData = HyprlandData.monitors.find(m => m.name === (monitor ? monitor.name : ""));
        const activeWsId = monitorData?.activeWorkspace?.id;
        return wl.some(w => w.workspace?.id === activeWsId && w.fullscreen === 3);
    }
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
    visible: GlobalStates.screenLocked || !bgRoot.deferredFullscreen || !(Config && Config.options && Config.options.background && Config.options.background.hideWhenFullscreen)

    // Workspaces calculations
    property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
    readonly property bool isMonitorFocused: (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") == (monitor ? monitor.name : "")
    readonly property bool loopEnabled: !wallpaperIsVideo && Config.options.background.parallax.loop
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
    property bool useSeparateLightModeWallpaper: Config.options && Config.options.background ? (Config.options.background.useSeparateLightModeWallpaper ?? false) : false
    property string lightModeWallpaperPath: Config.options && Config.options.background && Config.options.background.lightModeWallpaperPath ? Config.options.background.lightModeWallpaperPath : ""
    property bool wallpaperIsVideo: {
        const path = Config.options && Config.options.background && Config.options.background.wallpaperPath ? Config.options.background.wallpaperPath : "";
        return Wallpapers.isVideoFile(path);
    }
    readonly property bool videoEffectsDisabled: wallpaperIsVideo || Config.options.background.useWallpaperEngine
    property string wallpaperPath: {
        if (!Appearance.m3colors.darkmode && useSeparateLightModeWallpaper && lightModeWallpaperPath !== "") {
            return lightModeWallpaperPath;
        }
        if (wallpaperIsVideo) {
            const thumb = Config.options && Config.options.background && Config.options.background.thumbnailPath ? Config.options.background.thumbnailPath : "";
            if (thumb !== "") return thumb;
            return "";
        }
        const rawPath = Config.options && Config.options.background && Config.options.background.wallpaperPath ? Config.options.background.wallpaperPath : "";
        if (rawPath !== "")
            return rawPath;
        return `${Directories.assetsPath}/images/default_wallpaper.png`;
    }
    property bool useSeparateLockscreenWallpaper: Config.options && Config.options.background ? (Config.options.background.useSeparateLockscreenWallpaper ?? false) : false
    property string lockscreenWallpaperPath: {
        const rawPath = Config.options && Config.options.background && Config.options.background.lockscreenWallpaperPath ? Config.options.background.lockscreenWallpaperPath : "";
        if (rawPath !== "")
            return rawPath;
        return wallpaperPath;
    }
    property bool wallpaperSafetyTriggered: {
        const enabled = Config.options.workSafety.enable.wallpaper;
        const sensitiveWallpaper = (CF.StringUtils.stringListContainsSubstring(wallpaperPath.toLowerCase(), Config.options.workSafety.triggerCondition.fileKeywords));
        const sensitiveNetwork = (CF.StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveWallpaper && sensitiveNetwork;
    }
    property real wallpaperToScreenRatio: Math.min(wallpaperWidth / screen.width, wallpaperHeight / screen.height)
    property real preferredWallpaperScale: videoEffectsDisabled ? 1.0 : Config.options.background.parallax.workspaceZoom
    property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * baseWallpaperScale) - screen.width) / 2
    property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * baseWallpaperScale) - screen.height) / 2

    readonly property real minSafeScale: {
        const w = wallpaperWidth / wallpaperToScreenRatio * baseWallpaperScale;
        const h = wallpaperHeight / wallpaperToScreenRatio * baseWallpaperScale;
        if (w <= 0 || h <= 0)
            return 1.0;
        return Math.max(screen.width / w, screen.height / h);
    }

    readonly property bool verticalParallax: !videoEffectsDisabled && ((Config.options.background.parallax.autoVertical && wallpaperHeight > wallpaperWidth) || Config.options.background.parallax.vertical)
    // Colors
    property bool shouldBlur: (GlobalStates.screenLocked && Config.options.lock.blur.enable)
    property color dominantColor: Appearance.colors.colPrimary // Default, to be changed
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        if (wallpaperSafetyTriggered)
            return CF.ColorUtils.mix(Appearance.colors.colOnLayer0, Appearance.colors.colPrimary, 0.75);
        return (GlobalStates.screenLocked && shouldBlur) ? Appearance.colors.colOnLayer0 : CF.ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12));
    }
    // Video Wallpaper Parallax via mpv IPC
    readonly property real videoPanX: (0.5 - parallax.effectiveValueX) * 0.08
    readonly property real videoPanY: (0.5 - parallax.effectiveValueY) * 0.08

    onVideoPanXChanged: bgRoot.sendMpvPan()
    onVideoPanYChanged: bgRoot.sendMpvPan()

    function sendMpvPan() {
        if (!bgRoot.wallpaperIsVideo || !bgRoot.screen) return;
        const sock = "/tmp/mpvpaper-" + bgRoot.screen.name + ".sock";
        const px = videoPanX.toFixed(4);
        const py = videoPanY.toFixed(4);
        const cmdX = '{"command":["set_property","video-pan-x",' + px + ']}';
        const cmdY = '{"command":["set_property","video-pan-y",' + py + ']}';
        Quickshell.execDetached(["bash", "-c", "printf '%s\\n%s\\n' '" + cmdX + "' '" + cmdY + "' | socat - UNIX-CONNECT:" + sock + " >/dev/null 2>&1"]);
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

    readonly property bool zoomInStyle: !videoEffectsDisabled && Config.options.overview.scrollingStyle.zoomStyle === "in"
    readonly property bool showOpeningAnimation: Config.options.overview.showOpeningAnimation

    property bool overviewOpen: GlobalStates.overviewOpen

    property real scaleAnimated: !videoEffectsDisabled && GlobalStates.overviewOpen && showOpeningAnimation ? zoomedRatio : defaultRatio
    Behavior on scaleAnimated {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    // Layer props
    screen: modelData
    exclusionMode: ExclusionMode.Ignore
    // Keep the wallpaper below the dedicated widgets surface. Both used to be
    // mapped in WlrLayer.Bottom, where Hyprland's map order could leave the
    // wallpaper above the widgets after startup or a reload.
    // Media Mode has its own short-lived Overlay window. Promoting this
    // permanent fullscreen surface as well creates two competing input regions
    // and can leave the wallpaper above the interactive media controls.
    WlrLayershell.layer: WlrLayer.Background
    // Media Mode owns focus in a short-lived dedicated PanelWindow. Keeping the
    // persistent wallpaper window focusable would make both surfaces compete.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
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
        if (width <= 0 || height <= 0 || screenW <= 0 || screenH <= 0) return;
        
        let targetScale = bgRoot.preferredWallpaperScale;
        
        if (Config.options.background.blurWhenWindowsOpen || Config.options.lock.blur.enable) {
            targetScale *= 1.03;
        }
        
        bgRoot.baseWallpaperScale = targetScale;
    }

    // Wallpaper zoom scale
    function updateZoomScale() {
        getWallpaperSizeProc.path = bgRoot.wallpaperPath;
        getWallpaperSizeProc.running = true;
        wallpaperProbeTimeout.restart();
    }

    property bool mediaModeOpen: mediaModeLoader.active
    property bool mediaModeRegistered: false
    property string registeredMediaModeScreenName: ""

    function registerMediaMode() {
        if (bgRoot.mediaModeRegistered)
            return;

        const screenName = bgRoot.screen ? bgRoot.screen.name : "";
        bgRoot.mediaModeRegistered = true;
        bgRoot.registeredMediaModeScreenName = screenName;
        GlobalStates.setMediaModeActiveForScreen(screenName, true);
        GlobalStates.mediaModeCount++;
        LyricsService.mediaModeOpenCount++;
    }

    function releaseMediaModeRegistration() {
        if (!bgRoot.mediaModeRegistered)
            return;

        const screenName = bgRoot.registeredMediaModeScreenName;
        bgRoot.mediaModeRegistered = false;
        bgRoot.registeredMediaModeScreenName = "";
        GlobalStates.setMediaModeActiveForScreen(screenName, false);
        GlobalStates.mediaModeCount = Math.max(0, GlobalStates.mediaModeCount - 1);
        LyricsService.mediaModeOpenCount = Math.max(0, LyricsService.mediaModeOpenCount - 1);
    }

    function openMediaMode() {
        if (mediaModeLoader.active || !MprisController.activePlayer)
            return;
        mediaModeLoader.active = true;
    }

    // The media mode surface takes keyboard focus on demand, and it is a
    // short-lived window: destroying it while it still holds that focus leaves
    // the compositor routing input at a surface that no longer exists, and every
    // click on the shell is swallowed until some other focus-taking window (the
    // dashboard, a popup) resets the seat.
    //
    // Before media mode got its own window this could not happen: the surface
    // was the wallpaper's, it outlived the mode, and its focus was bound to
    // `mediaModeOpen ? OnDemand : None` — released while the surface was still
    // alive. The dedicated window has to do that release explicitly.
    property Timer mediaModeTeardown: Timer {
        // One frame is enough for the set_keyboard_interactivity(none) commit to
        // reach the compositor; this is deliberately a little longer.
        interval: 60
        repeat: false
        onTriggered: {
            if (mediaModeLoader.active)
                mediaModeLoader.active = false;
            bgRoot.releaseMediaModeRegistration();
        }
    }

    function closeMediaMode() {
        MusicVideoService.stopVideo();
        if (!mediaModeLoader.active) {
            // Idempotent: teardown also has to work while a monitor is
            // disappearing, when the loader is already gone.
            bgRoot.releaseMediaModeRegistration();
            return;
        }
        if (mediaModeLoader.item) {
            mediaModeLoader.item.releasingFocus = true;
            bgRoot.mediaModeTeardown.restart();
            return;
        }
        mediaModeLoader.active = false;
        bgRoot.releaseMediaModeRegistration();
    }

    function restoreWallpaperColors() {
        if (Config.options.appearance.palette.type.startsWith("scheme")
                && !GlobalStates.mediaModeActive
                && bgRoot.isMonitorFocused) {
            // Restore only after every BackgroundRoot has released its media
            // mode registration.
            Quickshell.execDetached([
                Directories.wallpaperSwitchScriptPath,
                "--noswitch",
                "--color", "clear",
                "--mode", Appearance.m3colors.darkmode ? "dark" : "light"
            ]);
        }
    }

    function applyCurrentWallpaper() {
        if (useSeparateLightModeWallpaper && !Appearance.m3colors.darkmode && lightModeWallpaperPath !== "") {
            Wallpapers.applyLightModeWallpaper(lightModeWallpaperPath);
        } else if (Config.options.background.wallpaperPath !== "") {
            Wallpapers.apply(Config.options.background.wallpaperPath);
        }
    }

    Connections {
        target: GlobalStates
        function onMediaModeActiveChanged() {
            if (!GlobalStates.mediaModeActive) {
                LyricsService.shellColorChanged = false;
                bgRoot.restoreWallpaperColors();
            }
        }
    }

    Connections {
        target: MprisController
        function onActivePlayerChanged() {
            if (!MprisController.activePlayer)
                bgRoot.closeMediaMode();
        }
    }

    // ── Media mode entrance ──────────────────────────────────────────────────
    // Promoting this window from WlrLayer.Background to WlrLayer.Overlay is a
    // hard cut: the wallpaper lands in front of every window in a single frame,
    // and the media UI fading in behind that reads as "no animation at all".
    // Fading the surface content instead makes media mode dissolve in over
    // whatever was on screen.
    //
    // Guarded on there being something behind us. On an empty workspace the
    // promotion is invisible anyway, and fading from zero would flash the
    // compositor's black through — this window *is* the wallpaper.
    property real mediaModeContentFade: 1.0

    SequentialAnimation {
        id: mediaModeEnterFade
        // Not a Behavior: the drop to zero has to land in the same frame as the
        // promotion, and only the way back up is animated.
        PropertyAction {
            target: bgRoot
            property: "mediaModeContentFade"
            value: 0
        }
        NumberAnimation {
            target: bgRoot
            property: "mediaModeContentFade"
            to: 1
            duration: Math.round(320 * Appearance.animMultiplier)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    onMediaModeOpenChanged: {
        if (mediaModeOpen) {
            if (bgRoot.hasWindowsInActiveWorkspace)
                mediaModeEnterFade.restart();
            else
                bgRoot.mediaModeContentFade = 1;
        } else {
            mediaModeEnterFade.stop();
            bgRoot.mediaModeContentFade = 1;
        }
        if (!mediaModeOpen) {
            // Force widgets window to re-stack after our layer transition from
            // WlrLayer.Overlay → WlrLayer.Bottom. Without this, the compositor
            // re-stacks us at the top of the Bottom layer, covering the widgets
            // PanelWindow with the wallpaper image.
            Qt.callLater(function() {
                GlobalStates.widgetReStackTrigger++;
            });
        }
    }

    Component.onCompleted: {
        GlobalStates.registerOverviewBackgroundController(bgRoot.screen ? bgRoot.screen.name : "", overviewController);
        // Do not re-run matugen / switchwall on quickshell reload/startup.
        // Theme colors and wallpaper are already persisted on disk.
        // The path-changed handler cannot carry the first probe on its own: when the config is
        // already loaded by the time this is created the path never changes, and the plane would
        // keep the screen-sized guess for the whole session.
        bgRoot.updateZoomScale();
    }

    Component.onDestruction: {
        if (bgRoot.mediaModeRegistered)
            MusicVideoService.stopVideo();
        bgRoot.releaseMediaModeRegistration();
        GlobalStates.unregisterOverviewBackgroundController(bgRoot.screen ? bgRoot.screen.name : "", overviewController);
    }

    LockRippleEffect {
        id: lockScreenRippleEffect
    }

    Item {
        id: contentRoot
        anchors.fill: parent
        opacity: bgRoot.mediaModeContentFade
        visible: GlobalStates.screenLocked || !bgRoot.deferredFullscreen || !(Config && Config.options && Config.options.background && Config.options.background.hideWhenFullscreen)

        WallpaperImage {
            id: wallpaperImage
            overviewController: overviewController
            screen: bgRoot.screen
            wallpaperPath: bgRoot.wallpaperPath
            lockscreenWallpaperPath: bgRoot.lockscreenWallpaperPath
            useSeparateLockscreenWallpaper: bgRoot.useSeparateLockscreenWallpaper
            wallpaperIsVideo: bgRoot.wallpaperIsVideo
            wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
            preferredWallpaperScale: bgRoot.preferredWallpaperScale
            effectiveWallpaperScale: bgRoot.effectiveWallpaperScale
            baseWallpaperScale: bgRoot.baseWallpaperScale
            wallpaperWidth: bgRoot.wallpaperWidth
            wallpaperHeight: bgRoot.wallpaperHeight
            wallpaperSizeKnown: bgRoot.wallpaperSizeKnown
            wallpaperToScreenRatio: bgRoot.wallpaperToScreenRatio
            movableXSpace: bgRoot.movableXSpace
            movableYSpace: bgRoot.movableYSpace
            minSafeScale: bgRoot.minSafeScale
            parallaxX: bgRoot.videoEffectsDisabled ? 0 : parallax.parallaxX
            parallaxY: bgRoot.videoEffectsDisabled ? 0 : parallax.parallaxY
            effectiveValueX: bgRoot.videoEffectsDisabled ? 0.5 : parallax.effectiveValueX
            effectiveValueY: bgRoot.videoEffectsDisabled ? 0.5 : parallax.effectiveValueY
            scaleValue: overviewController ? overviewController.scale : 1.0
            scaleOriginX: overviewController ? overviewController.scaleOriginX : bgRoot.screen.width / 2
            scaleOriginY: overviewController ? overviewController.scaleOriginY : bgRoot.screen.height / 2
            scaleProgress: overviewController ? overviewController.scaleProgress : 0.0
            anyWidgetIsDragging: bgRoot.anyWidgetIsDragging
            mediaModeOpen: bgRoot.mediaModeOpen
            lockAnimationActive: bgRoot.lockAnimationActive
            hasWindowsInActiveWorkspace: bgRoot.hasWindowsInActiveWorkspace
            widgetStateManager: bgRoot.widgetStateManager
        }

        GlobalShortcut {
            name: "mediaModeToggle"
            description: "Toggles media mode on press"

            onPressed: {
                if (!monitor.focused && Config.options.background.mediaMode.togglePerMonitor)
                    return;
                if (mediaModeLoader.active)
                    bgRoot.closeMediaMode();
                else
                    bgRoot.openMediaMode();
            }
        }

        property int _lastCloseAllTrigger: 0

        Connections {
            target: GlobalStates
            function onMediaModeCloseAllTriggerChanged() {
                if (GlobalStates.mediaModeCloseAllTrigger <= bgRoot._lastCloseAllTrigger)
                    return;
                bgRoot._lastCloseAllTrigger = GlobalStates.mediaModeCloseAllTrigger;
                if (mediaModeLoader.active || bgRoot.mediaModeRegistered)
                    bgRoot.closeMediaMode();
            }
        }

        // Fullscreen effects must not share the wallpaper's permanent QQuickWindow.
        // Destroying only their Item tree leaves large render targets in that
        // window's scenegraph/resource pools. A dedicated short-lived window gives
        // Qt/RHI a real teardown boundary on every close.
        Scope {
            id: mediaModeWindowScope

            LazyLoader {
                id: mediaModeLoader

                active: false
                onActiveChanged: {
                    if (active) {
                        if (!MprisController.activePlayer) {
                            active = false;
                            return;
                        }
                        bgRoot.registerMediaMode();
                    } else {
                        bgRoot.releaseMediaModeRegistration();
                    }
                }

                component: PanelWindow {
                    id: mediaModeWindow

                    screen: bgRoot.screen
                    visible: true
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0

                    WlrLayershell.namespace: "quickshell:mediaMode"
                    WlrLayershell.layer: WlrLayer.Overlay
                    // Handed back before the window is destroyed — see
                    // closeMediaMode(). A short-lived layer surface must never
                    // die holding keyboard focus.
                    property bool releasingFocus: false
                    WlrLayershell.keyboardFocus: mediaModeWindow.releasingFocus
                        ? WlrKeyboardFocus.None
                        : WlrKeyboardFocus.OnDemand

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }

                    MediaMode {
                        anchors.fill: parent
                        onCloseRequested: function(allMonitors) {
                            if (allMonitors)
                                GlobalStates.mediaModeCloseAllTrigger++;
                            else
                                bgRoot.closeMediaMode();
                        }
                    }
                }
            }
        }
    }
}
