pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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
    readonly property var overviewController: GlobalStates.overviewBackgroundControllerFor(bgWidgetsWindow.screen ? bgWidgetsWindow.screen.name : "")
    readonly property bool isGnomeLikeOverview: overviewController && overviewController.isGnomeLike
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell:backgroundWidgets"
    // Wayland gives no client the global key stream: without keyboard focus,
    // Qt's modifier state stays empty and mouse.modifiers is always 0, which
    // makes the Ctrl-to-bypass-snap drag gesture undetectable. While a widget
    // drag is active we take OnDemand focus so real modifier events flow in;
    // dropping it on release hands focus back to the previously focused app.
    WlrLayershell.keyboardFocus: widgetCanvas.draggingActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Fullscreen deferral logic
    property var workspacesForMonitor: Hyprland.workspaces.values.filter(function (workspace) {
        return workspace.monitor && workspace.monitor.name == monitor.name;
    })
    readonly property bool isFullscreen: {
        const wl = HyprlandData.windowList;
        const monitorData = HyprlandData.monitors.find(m => m.name === (monitor ? monitor.name : ""));
        const activeWsId = monitorData?.activeWorkspace?.id;
        return wl.some(w => w.workspace?.id === activeWsId && w.fullscreen === 3);
    }
    property var activeWorkspace: workspacesForMonitor.filter(function (workspace) {
        return workspace.active;
    })[0]
    property bool hasWindowsInActiveWorkspace: {
        if (activeWorkspace == undefined)
            return false;
        let activeId = activeWorkspace.id;
        if (activeId > 1000000)
            activeId = 2147483647 - activeId;
        return HyprlandData.windowList.some(function (w) {
            return w.workspace.id === activeId;
        });
    }
    property bool deferredFullscreen: false
    Timer {
        id: fullscreenDeferTimer
        interval: 50
        repeat: false
        onTriggered: bgWidgetsWindow.deferredFullscreen = bgWidgetsWindow.isFullscreen
    }
    onIsFullscreenChanged: fullscreenDeferTimer.restart()

    readonly property bool isTargetMonitor: {
        const cfg = Config && Config.options && Config.options.background && Config.options.background.widgets;
        if (!cfg || !cfg.showOnlyOnSingleMonitor)
            return true;
        const target = cfg.targetMonitor ?? "";
        return target === "" || (modelData && modelData.name === target);
    }
    readonly property bool hasWidgets: widgetStateManager && widgetStateManager.model ? widgetStateManager.model.count > 0 : false

    // A mapped fullscreen layer costs a swapchain plus a render thread even when every widget on it
    // is hidden. Only keep it mapped while at least one widget is actually shown - the same rule
    // WidgetDelegate's FadeLoader uses - and for the whole lock/unlock sequence so lock-only widgets
    // fade in and out exactly as before. Setups with an always-visible widget never unmap.
    readonly property bool anyWidgetShown: {
        if (!hasWidgets)
            return false;
        void widgetStateManager.syncVersion; // re-evaluate when the model's roles are rewritten
        if (GlobalStates.screenLocked || lockAnim.lockAnimationActive)
            return true;
        const model = widgetStateManager.model;
        for (let i = 0; i < model.count; i++) {
            if (model.get(i).lockBehavior !== "lockOnly")
                return true;
        }
        return false;
    }
    property bool widgetsNeedSurface: false
    Timer {
        // Hold the surface until the last widget's fade-out has finished.
        id: surfaceReleaseTimer
        interval: Appearance.animation.elementMoveFast.duration + 50
        repeat: false
        onTriggered: bgWidgetsWindow.widgetsNeedSurface = false
    }
    function updateSurfaceNeed() {
        if (anyWidgetShown) {
            surfaceReleaseTimer.stop();
            widgetsNeedSurface = true;
        } else if (widgetsNeedSurface) {
            surfaceReleaseTimer.restart();
        }
    }
    onAnyWidgetShownChanged: updateSurfaceNeed()
    Component.onCompleted: updateSurfaceNeed()

    visible: isTargetMonitor && widgetsNeedSurface && (GlobalStates.screenLocked || !bgWidgetsWindow.deferredFullscreen || !(Config && Config.options && Config.options.background && Config.options.background.hideWhenFullscreen))

    // Z-ordering fix: when BackgroundRoot transitions from WlrLayer.Overlay back to
    // WlrLayer.Bottom after media mode closes, the compositor re-stacks it at the top
    // of the Bottom layer, covering this widgets window with the wallpaper image.
    // Force a re-map by briefly toggling visibility.
    property int _lastReStackTrigger: 0

    Connections {
        target: GlobalStates
        function onWidgetReStackTriggerChanged() {
            if (GlobalStates.widgetReStackTrigger > bgWidgetsWindow._lastReStackTrigger) {
                bgWidgetsWindow._lastReStackTrigger = GlobalStates.widgetReStackTrigger;
                // Only re-stack if we're supposed to be visible
                if (bgWidgetsWindow.visible) {
                    bgWidgetsWindow.visible = false;
                    Qt.callLater(function() {
                        bgWidgetsWindow.visible = Qt.binding(function() {
                            return isTargetMonitor && widgetsNeedSurface && (GlobalStates.screenLocked || !bgWidgetsWindow.deferredFullscreen || !(Config && Config.options && Config.options.background && Config.options.background.hideWhenFullscreen));
                        });
                    });
                }
            }
        }
    }

    // Monitor & Workspaces calculations
    property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
    readonly property bool isMonitorFocused: (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") == (monitor ? monitor.name : "")
    readonly property bool loopEnabled: !wallpaperIsVideo && Config.options.background.parallax.loop
    readonly property var intensitySpans: [20, 15, 12, 10, 8, 7, 5, 4, 3, 2]
    readonly property int chunkSize: {
        let intensity = Config.options.background.parallax.intensity;
        if (intensity === undefined || isNaN(intensity))
            intensity = 4;
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
        return Wallpapers.isVideoFile(path);
    }
    readonly property bool videoEffectsDisabled: wallpaperIsVideo || Config.options.background.useWallpaperEngine
    property string wallpaperPath: {
        const rawPath = wallpaperIsVideo ? (Config.options && Config.options.background && Config.options.background.thumbnailPath ? Config.options.background.thumbnailPath : "") : (Config.options && Config.options.background && Config.options.background.wallpaperPath ? Config.options.background.wallpaperPath : "");
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
        onSizeDetected: function (w, h) {
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

    function recalcWallpaperScale() {
        const width = bgWidgetsWindow.wallpaperWidth;
        const height = bgWidgetsWindow.wallpaperHeight;
        const screenW = bgWidgetsWindow.screen.width;
        const screenH = bgWidgetsWindow.screen.height;
        if (width <= 0 || height <= 0 || screenW <= 0 || screenH <= 0)
            return;

        let targetScale = bgWidgetsWindow.preferredWallpaperScale;

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
        wallpaperIsVideo: bgWidgetsWindow.videoEffectsDisabled
        activeWorkspaceId: {
            let activeId = bgWidgetsWindow.monitor && bgWidgetsWindow.monitor.activeWorkspace ? bgWidgetsWindow.monitor.activeWorkspace.id : 1;
            return activeId > 1000000 ? (2147483647 - activeId) : activeId;
        }
    }

    readonly property bool overviewOpen: GlobalStates.overviewOpen

    readonly property bool zoomInStyle: !videoEffectsDisabled && Config.options.overview.scrollingStyle.zoomStyle === "in"
    readonly property bool showOpeningAnimation: Config.options.overview.showOpeningAnimation
    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    readonly property var zoomLevels: ({
        "in": { default: 1.04, zoomed: 1 },
        "out": { default: 1, zoomed: 1.01 }
    })
    readonly property real defaultRatio: zoomInStyle ? zoomLevels.in.default : zoomLevels.out.default
    readonly property real zoomedRatio: zoomInStyle ? zoomLevels.in.zoomed : zoomLevels.out.zoomed

    // The window blur stays on through the launcher and the overview - the overview composes its
    // own dim on top of the blurred wallpaper rather than replacing it.
    readonly property bool windowBlurActive: !videoEffectsDisabled && Config.options.background.blurWhenWindowsOpen && hasWindowsInActiveWorkspace && !GlobalStates.screenLocked
    readonly property bool overviewAnimationVisible: overviewController && (overviewController.active || overviewController.progress > 0.001)
    readonly property bool isMaterialShapeOverview: overviewController && overviewController.isMaterialShape && overviewAnimationVisible

    Item {
        id: materialShapeMaskContainer
        x: 0
        y: 0
        width: bgWidgetsWindow.screen.width
        height: bgWidgetsWindow.screen.height
        visible: bgWidgetsWindow.isMaterialShapeOverview

        MaterialShape {
            id: materialShapeMask
            anchors.centerIn: parent
            width: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.maskTargetDiameter : 0
            height: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.maskTargetDiameter : 0
            shapeString: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.currentMaterialShape : "Flower"
            color: "#ffffff"

            transform: [
                Scale {
                    origin.x: materialShapeMask.width / 2
                    origin.y: materialShapeMask.height / 2
                    xScale: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.maskScale : 1.0
                    yScale: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.maskScale : 1.0
                },
                Rotation {
                    origin.x: materialShapeMask.width / 2
                    origin.y: materialShapeMask.height / 2
                    angle: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.maskRotation : 0.0
                }
            ]
        }
    }

    ShaderEffectSource {
        id: materialShapeMaskSource
        sourceItem: materialShapeMaskContainer
        hideSource: true
        live: bgWidgetsWindow.isMaterialShapeOverview
        visible: false
    }

    Item {
        id: transformContainer
        anchors.fill: parent

        layer.enabled: bgWidgetsWindow.isMaterialShapeOverview
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: materialShapeMaskSource
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        opacity: GlobalStates.isMediaModeActiveForScreen(bgWidgetsWindow.screen ? bgWidgetsWindow.screen.name : "")
            ? 0.0
            : (bgWidgetsWindow.isGnomeLikeOverview
                ? 1.0
                : (bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.opacityMultiplier : 1.0))
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation {
                duration: Math.round(350 * Appearance.animMultiplier)
                easing.type: Easing.OutCubic
            }
        }
        antialiasing: true
        smooth: true

        transform: [
            Scale {
                origin.x: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.scaleOriginX : bgWidgetsWindow.width / 2
                origin.y: bgWidgetsWindow.overviewController ? bgWidgetsWindow.overviewController.scaleOriginY : bgWidgetsWindow.height / 2
                xScale: bgWidgetsWindow.overviewController && bgWidgetsWindow.overviewController.followWidgetsScale ? bgWidgetsWindow.overviewController.scale : 1.0
                yScale: bgWidgetsWindow.overviewController && bgWidgetsWindow.overviewController.followWidgetsScale ? bgWidgetsWindow.overviewController.scale : 1.0
            },
            Translate {
                x: bgWidgetsWindow.overviewController && bgWidgetsWindow.overviewController.followWidgetsTranslation ? bgWidgetsWindow.overviewController.translateX : 0
                y: bgWidgetsWindow.overviewController && bgWidgetsWindow.overviewController.followWidgetsTranslation ? bgWidgetsWindow.overviewController.translateY : 0
            }
        ]

        scale: bgWidgetsWindow.isGnomeLikeOverview
            ? (!videoEffectsDisabled && showOpeningAnimation && overviewOpen && isScrollingLayout ? zoomedRatio : defaultRatio)
            : 1.0
        Behavior on scale {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(transformContainer)
        }

        WidgetCanvas {
            id: widgetCanvas
            layer.enabled: false
            antialiasing: true
            smooth: true
            gridOverlayEnabled: Config.options.background.widgets.enableGrid ?? false

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                horizontalCenter: undefined
                verticalCenter: undefined
                readonly property real parallaxFactor: videoEffectsDisabled ? 1.0 : Config.options.background.parallax.widgetsFactor
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
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }
                Behavior on topMargin {
                    NumberAnimation {
                        duration: Appearance.animation.elementMove.duration
                        easing.type: Appearance.animation.elementMove.type
                        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
                    }
                }
            }
            width: parent.width
            height: parent.height

            Binding {
                target: widgetStateManager
                property: "draggingActive"
                value: widgetCanvas.draggingActive
                when: typeof widgetStateManager !== "undefined" && widgetStateManager && widgetStateManager.hasOwnProperty("draggingActive")
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
