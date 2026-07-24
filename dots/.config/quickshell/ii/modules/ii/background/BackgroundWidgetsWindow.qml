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
    id: bgWidgetsWindow

    required property var modelData
    required property var widgetStateManager

    screen: modelData
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:backgroundWidgets"
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Fullscreen deferral logic
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
    property bool deferredFullscreen: false
    Timer {
        id: fullscreenDeferTimer
        interval: 50
        repeat: false
        onTriggered: bgWidgetsWindow.deferredFullscreen = bgWidgetsWindow.isFullscreen
    }
    onIsFullscreenChanged: fullscreenDeferTimer.restart()
    visible: GlobalStates.screenLocked || !bgWidgetsWindow.deferredFullscreen || !(Config && Config.options && Config.options.background && Config.options.background.hideWhenFullscreen)

    // Monitor & Workspaces calculations
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

    // Wallpaper options & bounds
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

    property int wallpaperWidth: modelData.width
    property int wallpaperHeight: modelData.height
    property real baseWallpaperScale: 1

    WallpaperSizeProbe {
        id: getWallpaperSizeProc
        path: bgWidgetsWindow.wallpaperPath
        onSizeDetected: function(w, h) {
            bgWidgetsWindow.wallpaperWidth = w;
            bgWidgetsWindow.wallpaperHeight = h;
            bgWidgetsWindow.recalcWallpaperScale();
        }
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

    function recalcWallpaperScale() {
        const width = bgWidgetsWindow.wallpaperWidth;
        const height = bgWidgetsWindow.wallpaperHeight;
        const screenW = bgWidgetsWindow.screen.width;
        const screenH = bgWidgetsWindow.screen.height;
        if (width <= 0 || height <= 0) return;
        
        let targetScale = 1.0;
        if (Config.options.background.scaleLargeWallpapers) {
            if (width <= screenW || height <= screenH) {
                targetScale = Math.max(screenW / width, screenH / height);
            } else {
                targetScale = Math.min(bgWidgetsWindow.preferredWallpaperScale, width / screenW, height / screenH);
            }
        }
        
        if (Config.options.background.blurWhenWindowsOpen || Config.options.lock.blur.enable) {
            targetScale *= 1.03;
        }
        
        bgWidgetsWindow.baseWallpaperScale = targetScale;
    }

    LockAnimController {
        id: lockAnim
        baseScale: bgWidgetsWindow.baseWallpaperScale
        hasWindowsInActiveWorkspace: bgWidgetsWindow.hasWindowsInActiveWorkspace
    }

    ParallaxController {
        id: parallax
        movableXSpace: bgWidgetsWindow.movableXSpace
        movableYSpace: bgWidgetsWindow.movableYSpace
        firstWorkspaceId: bgWidgetsWindow.firstWorkspaceId
        lastWorkspaceId: bgWidgetsWindow.lastWorkspaceId
        chunkSize: bgWidgetsWindow.chunkSize
        verticalParallax: bgWidgetsWindow.verticalParallax
        parallaxFrozen: lockAnim.parallaxFrozen
        wallpaperCentered: lockAnim.wallpaperCentered
        activeWorkspaceId: {
            let activeId = bgWidgetsWindow.monitor && bgWidgetsWindow.monitor.activeWorkspace ? bgWidgetsWindow.monitor.activeWorkspace.id : 1;
            return activeId > 1000000 ? (2147483647 - activeId) : activeId;
        }
    }

    readonly property bool scratchpadOpen: GlobalStates.scratchpadOpen
    readonly property bool wallpaperZoomedOut: Config.options.background.zoomOutEnabled && (GlobalStates.cheatsheetOpen || GlobalStates.overviewOpen || scratchpadOpen) && (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name == screen.name : false)

    OverviewZoomController {
        id: ovZoom
        wallpaperZoomedOut: bgWidgetsWindow.wallpaperZoomedOut
        minSafeScale: bgWidgetsWindow.minSafeScale
        zoomOutCoverScale: 1.05
        screenWidth: bgWidgetsWindow.screen.width
        screenHeight: bgWidgetsWindow.screen.height
    }

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
    readonly property bool zoomInStyle: Config.options.overview.scrollingStyle.zoomStyle === "in"
    readonly property bool showOpeningAnimation: Config.options.overview.showOpeningAnimation
    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    readonly property bool overviewOpen: GlobalStates.overviewOpen

    property real defaultRatio: zoomInStyle ? zoomLevels.in.default : zoomLevels.out.default
    property real zoomedRatio: zoomInStyle ? zoomLevels.in.zoomed : zoomLevels.out.zoomed

    readonly property bool windowBlurActive: Config.options.background.blurWhenWindowsOpen && hasWindowsInActiveWorkspace && !GlobalStates.screenLocked && !overviewOpen

    Item {
        id: transformContainer
        anchors.fill: parent

        opacity: 1.0
        antialiasing: true
        smooth: true

        transform: Scale {
            origin.x: ovZoom.scaleOriginX
            origin.y: ovZoom.scaleOriginY
            xScale: ovZoom.scaleValue
            yScale: ovZoom.scaleValue
        }

        scale: showOpeningAnimation && overviewOpen && isScrollingLayout ? zoomedRatio : 1.0
        Behavior on scale {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(transformContainer)
        }

        WidgetCanvas {
            id: widgetCanvas
            layer.enabled: false
            antialiasing: true
            smooth: true

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                horizontalCenter: undefined
                verticalCenter: undefined
                readonly property real parallaxFactor: Config.options.background.parallax.widgetsFactor
                leftMargin: {
                    const xOnWallpaper = bgWidgetsWindow.movableXSpace;
                    const extraMove = (parallax.effectiveValueX * 2 * bgWidgetsWindow.movableXSpace) * (parallaxFactor - 1);
                    return xOnWallpaper - extraMove;
                }
                topMargin: {
                    const yOnWallpaper = bgWidgetsWindow.movableYSpace;
                    const extraMove = (parallax.effectiveValueY * 2 * bgWidgetsWindow.movableYSpace) * (parallaxFactor - 1);
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

            Binding {
                target: widgetStateManager
                property: "draggingActive"
                value: widgetCanvas.draggingActive
            }

            states: State {
                name: "centered"
                when: GlobalStates.lockScreenCentered || GlobalStates.workspaceRestoreInProgress || bgWidgetsWindow.wallpaperSafetyTriggered
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
                    screenWidth: bgWidgetsWindow.screen.width
                    screenHeight: bgWidgetsWindow.screen.height
                    wallpaperScale: lockAnim.effectiveWallpaperScale
                    wallpaperSafetyTriggered: bgWidgetsWindow.wallpaperSafetyTriggered
                    lockAnimationActive: lockAnim.lockAnimationActive
                }
            }
        }
    }
}
