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
import qs.modules.ii.background.widgets.DateWidget
import qs.modules.ii.background.widgets.photo

Scope {
    id: backgroundScope

    ListModel {
        id: widgetListModel
        onCountChanged: console.log("[Background] widgetListModel count changed to: " + count)
    }
    property int widgetSyncVersion: 0

    function syncActiveWidgets() {
        let configList = Config.options.background.activeWidgets || [];
        console.log("[Background] syncActiveWidgets called. Config activeWidgets count: " + configList.length + ", current model count: " + widgetListModel.count);
        
        // 1. Remove items from ListModel that are no longer in Config
        for (let i = widgetListModel.count - 1; i >= 0; i--) {
            let modelId = widgetListModel.get(i).instanceId;
            let found = false;
            for (let j = 0; j < configList.length; j++) {
                if (configList[j].id === modelId) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                widgetListModel.remove(i);
            }
        }
        
        // 2. Add or update items in ListModel
        for (let j = 0; j < configList.length; j++) {
            let configItem = configList[j];
            let modelIndex = -1;
            for (let i = 0; i < widgetListModel.count; i++) {
                if (widgetListModel.get(i).instanceId === configItem.id) {
                    modelIndex = i;
                    break;
                }
            }
            
            if (modelIndex === -1) {
                widgetListModel.append({
                    "instanceId": configItem.id,
                    "widgetId": configItem.widgetId,
                    "widgetX": configItem.x,
                    "widgetY": configItem.y,
                    "placementStrategy": configItem.placementStrategy || "free",
                    "lockBehavior": configItem.lockBehavior || "hide"
                });
            } else {
                let modelItem = widgetListModel.get(modelIndex);
                if (modelItem.widgetId !== configItem.widgetId) {
                    modelItem.widgetId = configItem.widgetId;
                }
                if (Math.abs(modelItem.widgetX - configItem.x) > 0.01) modelItem.widgetX = configItem.x;
                if (Math.abs(modelItem.widgetY - configItem.y) > 0.01) modelItem.widgetY = configItem.y;
                if (modelItem.placementStrategy !== configItem.placementStrategy) {
                    modelItem.placementStrategy = configItem.placementStrategy || "free";
                }
                if (modelItem.lockBehavior !== (configItem.lockBehavior || "hide")) {
                    modelItem.lockBehavior = configItem.lockBehavior || "hide";
                }
            }
        }
        backgroundScope.widgetSyncVersion++;
    }

    function maybeMigrateWidgets() {
        if (Persistent.states.background.widgetsMigrated) return;
        
        console.log("[Background] Migrating legacy desktop widgets configuration...");
        let migrated = [];
        let centerWidget = Config.options.lock.centerWidget || "none";
        
        // Clock widget
        if (Config.options.background.widgets.clock.enable) {
            let style = Config.options.background.widgets.clock.style || "cookie";
            let widgetId = "clock_" + style;
            let lockBehavior = (centerWidget === "clock") ? "center" : "hide";
            migrated.push({
                "id": "widget_" + widgetId + "_migrated",
                "widgetId": widgetId,
                "x": Config.options.background.widgets.clock.x ?? 1518.98,
                "y": Config.options.background.widgets.clock.y ?? 168.8,
                "placementStrategy": Config.options.background.widgets.clock.placementStrategy || "free",
                "lockBehavior": lockBehavior
            });
        }
        
        // Media widget
        if (Config.options.background.widgets.media.enable) {
            let style = Config.options.background.widgets.media.style || "circular";
            let widgetId = "media_" + style;
            let lockBehavior = (centerWidget === "media") ? "center" : "hide";
            migrated.push({
                "id": "widget_" + widgetId + "_migrated",
                "widgetId": widgetId,
                "x": Config.options.background.widgets.media.x ?? 249.21,
                "y": Config.options.background.widgets.media.y ?? 612.92,
                "placementStrategy": Config.options.background.widgets.media.placementStrategy || "free",
                "lockBehavior": lockBehavior
            });
        }

        // Circular Media widget
        if (Config.options.background.widgets.circular_media && Config.options.background.widgets.circular_media.enable) {
            let lockBehavior = (centerWidget === "media") ? "center" : "hide";
            migrated.push({
                "id": "widget_circular_media_migrated",
                "widgetId": "circular_media",
                "x": Config.options.background.widgets.circular_media.x ?? 249.21,
                "y": Config.options.background.widgets.circular_media.y ?? 612.92,
                "placementStrategy": Config.options.background.widgets.circular_media.placementStrategy || "free",
                "lockBehavior": lockBehavior
            });
        }
        
        // Weather widget
        if (Config.options.background.widgets.weather.enable) {
            let style = Config.options.background.widgets.weather.style || "default";
            let widgetId = "weather_" + style;
            migrated.push({
                "id": "widget_" + widgetId + "_migrated",
                "widgetId": widgetId,
                "x": Config.options.background.widgets.weather.x ?? 400,
                "y": Config.options.background.widgets.weather.y ?? 100,
                "placementStrategy": Config.options.background.widgets.weather.placementStrategy || "free",
                "lockBehavior": "hide"
            });
        }
        
        // Date widget
        if (Config.options.background.widgets.date.enable) {
            migrated.push({
                "id": "widget_date_default_migrated",
                "widgetId": "date_default",
                "x": Config.options.background.widgets.date.x ?? 100,
                "y": Config.options.background.widgets.date.y ?? 100,
                "placementStrategy": Config.options.background.widgets.date.placementStrategy || "free",
                "lockBehavior": "hide"
            });
        }
        
        Config.options.background.activeWidgets = migrated;
        Persistent.states.background.widgetsMigrated = true;
        console.log("[Background] Widget migration complete. Migrated widgets count: " + migrated.length);
    }

    Connections {
        target: Config.ready ? Config.options.background : null
        ignoreUnknownSignals: true
        function onActiveWidgetsChanged() {
            backgroundScope.syncActiveWidgets();
        }
    }

    Connections {
        target: Config
        ignoreUnknownSignals: true
        function onReadyChanged() {
            if (Config.ready) {
                backgroundScope.maybeMigrateWidgets();
                Config.migrateWidgetLockBehavior();
                backgroundScope.syncActiveWidgets();
            }
        }
    }

    Component.onCompleted: {
        if (Config.ready) {
            backgroundScope.maybeMigrateWidgets();
            Config.migrateWidgetLockBehavior();
            backgroundScope.syncActiveWidgets();
        }
    }

    Variants {
        id: root
        model: Quickshell.screens

        PanelWindow {
            id: bgRoot

            required property var modelData

            property bool anyWidgetIsDragging: false
            property bool lockAnimationActive: false
            property bool parallaxFrozen: false
            property bool rippleActive: false  // mantém layer em Top durante ripple de unlock

            Connections {
                target: GlobalStates
                function onScreenLockedChanged() {
                    if (GlobalStates.screenLocked) {
                        // Zoom out immediately — if already at 1.0, briefly bump to base
                        // so the Behavior has a real value change to animate from
                        if (Math.abs(effectiveWallpaperScale - 1.0) < 0.001) {
                            effectiveWallpaperScale = baseWallpaperScale;
                        }
                        effectiveWallpaperScale = 1.0;
                        bgRoot.lockAnimationActive = true;
                        bgRoot.parallaxFrozen = false;
                        parallaxUnfreezeTimer.stop();
                    } else {
                        effectiveWallpaperScale = baseWallpaperScale;
                        bgRoot.parallaxFrozen = true;
                        parallaxUnfreezeTimer.restart();
                        if (!GlobalStates.workspaceRestoreInProgress) {
                            lockAnimResetTimer.restart();
                        }
                        // Ripple no unlock — pequeno delay para layer já estar visível
                        if (Config.options.lock.rippleEffect ?? true) {
                            rippleOnUnlockTimer.restart();
                        }
                    }
                }
                function onWorkspaceRestoreInProgressChanged() {
                    if (!GlobalStates.workspaceRestoreInProgress && !GlobalStates.screenLocked) {
                        lockAnimResetTimer.restart();
                    }
                }
            }
            // Dispara o ripple com delay após unlock para não colidir com troca de layer
            Timer {
                id: rippleOnUnlockTimer
                interval: 80
                repeat: false
                onTriggered: {
                    bgRoot.rippleActive = true;
                    lockScreenRippleEffect.startRipple(0, 0);
                    // Volta ao Bottom depois que o ripple terminar (750ms grow + 550ms fade + margem)
                    rippleLayerResetTimer.restart();
                }
            }
            Timer {
                id: rippleLayerResetTimer
                interval: 1500
                repeat: false
                onTriggered: bgRoot.rippleActive = false
            }
            Timer {
                id: lockAnimResetTimer
                interval: 650
                repeat: false
                onTriggered: bgRoot.lockAnimationActive = false
            }
            Timer {
                id: parallaxUnfreezeTimer
                interval: 700
                repeat: false
                onTriggered: bgRoot.parallaxFrozen = false
            }

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
            property real baseWallpaperScale: 1 // Calculated scale from wallpaper size
            property real effectiveWallpaperScale: 1 // Final scale applied to wallpaper
            property int wallpaperWidth: modelData.width // Some reasonable init value, to be updated
            property int wallpaperHeight: modelData.height // Some reasonable init value, to be updated
            property real movableXSpace: ((wallpaperWidth / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.width) / 2
            property real movableYSpace: ((wallpaperHeight / wallpaperToScreenRatio * effectiveWallpaperScale) - screen.height) / 2

            // Lockscreen zoom animation: animate effectiveWallpaperScale to 1.0 on lock, back to base on unlock
            Behavior on effectiveWallpaperScale {
                NumberAnimation {
                    duration: 450
                    easing.type: Easing.OutQuart
                }
            }

            onBaseWallpaperScaleChanged: {
                if (!GlobalStates.screenLocked) {
                    effectiveWallpaperScale = baseWallpaperScale;
                }
            }

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
            WlrLayershell.layer: (GlobalStates.screenLocked && !scaleAnim.running) || bgRoot.rippleActive ? WlrLayer.Top : WlrLayer.Bottom
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
            onPreferredWallpaperScaleChanged: bgRoot.recalcWallpaperScale()

            function recalcWallpaperScale() {
                const width = bgRoot.wallpaperWidth;
                const height = bgRoot.wallpaperHeight;
                const screenW = bgRoot.screen.width;
                const screenH = bgRoot.screen.height;
                if (width <= 0 || height <= 0) return;
                if (Config.options.background.scaleLargeWallpapers) {
                    if (width <= screenW || height <= screenH) {
                        bgRoot.baseWallpaperScale = Math.max(screenW / width, screenH / height);
                    } else {
                        bgRoot.baseWallpaperScale = Math.min(bgRoot.preferredWallpaperScale, width / screenW, height / screenH);
                    }
                } else {
                    bgRoot.baseWallpaperScale = 1.0;
                }
                if (!GlobalStates.screenLocked) {
                    bgRoot.effectiveWallpaperScale = bgRoot.baseWallpaperScale;
                }
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

                        if (Config.options.background.scaleLargeWallpapers) {
                            if (width <= screenWidth || height <= screenHeight) {
                                // Undersized/perfectly sized wallpapers
                                bgRoot.baseWallpaperScale = Math.max(screenWidth / width, screenHeight / height);
                            } else {
                                // Oversized = can be zoomed for parallax, yay
                                bgRoot.baseWallpaperScale = Math.min(bgRoot.preferredWallpaperScale, width / screenWidth, height / screenHeight);
                            }
                        } else {
                            bgRoot.baseWallpaperScale = 1.0;
                        }
                        if (!GlobalStates.screenLocked) {
                            bgRoot.effectiveWallpaperScale = bgRoot.baseWallpaperScale;
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

            // Lockscreen ripple — saindo do centro da tela ao desbloquear
            // Usa SequentialAnimation idêntico ao RippleButton: grow → depois fade
            Item {
                id: lockScreenRippleEffect
                anchors.fill: parent
                z: 100
                clip: true
                visible: rippleAnim.running || rippleFadeAnim.running

                function startRipple(x, y) {
                    // Sempre irradia do centro da tela, independente de onde foi clicado
                    const cx = bgRoot.width / 2;
                    const cy = bgRoot.height / 2;
                    // Raio = diagonal até o canto mais longe do centro
                    const maxRadius = Math.sqrt(cx * cx + cy * cy);

                    rippleCircle.x = cx;
                    rippleCircle.y = cy;
                    rippleAnim.radius = maxRadius;

                    // Mesmo padrão do RippleButton: para fade anterior, reinicia sequência
                    rippleFadeAnim.complete();
                    rippleAnim.restart();
                }

                // Sequência: set posição+opacidade → grow → (ao terminar) fade
                SequentialAnimation {
                    id: rippleAnim
                    property real radius: 0

                    PropertyAction { target: rippleCircle; property: "rippleSize"; value: 0 }
                    PropertyAction { target: rippleCircle; property: "opacity";    value: 0.75 }

                    NumberAnimation {
                        target: rippleCircle
                        property: "rippleSize"
                        from: 0
                        to: rippleAnim.radius * 2
                        duration: 750
                        easing.type: Easing.OutCubic
                    }

                    // Inicia fade após o grow
                    ScriptAction {
                        script: rippleFadeAnim.restart()
                    }
                }

                // Fade separado — começa só após grow terminar
                NumberAnimation {
                    id: rippleFadeAnim
                    target: rippleCircle
                    property: "opacity"
                    from: 0.75
                    to: 0
                    duration: 550
                    easing.type: Easing.InQuad
                }

                Item {
                    id: rippleCircle
                    property real rippleSize: 0
                    width: rippleSize
                    height: rippleSize
                    opacity: 0
                    visible: rippleSize > 0
                    transform: Translate {
                        x: -rippleCircle.width  / 2
                        y: -rippleCircle.height / 2
                    }

                    RadialGradient {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0;  color: Appearance.colors.colPrimary }
                            GradientStop { position: 0.35; color: Appearance.colors.colPrimary }
                            GradientStop {
                                position: 0.75
                                color: Qt.rgba(
                                    Appearance.colors.colPrimary.r,
                                    Appearance.colors.colPrimary.g,
                                    Appearance.colors.colPrimary.b,
                                    0.0)
                            }
                        }
                    }
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
                        property real parallaxX: (GlobalStates.screenLocked || GlobalStates.workspaceRestoreInProgress || bgRoot.parallaxFrozen) ? -(bgRoot.movableXSpace) : -(bgRoot.movableXSpace) - (wallpaper.effectiveValueX - 0.5) * 2 * bgRoot.movableXSpace
                        property real parallaxY: (GlobalStates.screenLocked || GlobalStates.workspaceRestoreInProgress || bgRoot.parallaxFrozen) ? -(bgRoot.movableYSpace) : -(bgRoot.movableYSpace) - (wallpaper.effectiveValueY - 0.5) * 2 * bgRoot.movableYSpace
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
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }
                            Behavior on y {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }
                            Behavior on width {
                                NumberAnimation {
                                    duration: 600
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on height {
                                NumberAnimation {
                                    duration: 600
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
                                sourceSize: Config.options.background.scaleLargeWallpapers ? Qt.size(bgRoot.screen.width > 0 ? Math.round(bgRoot.screen.width * bgRoot.preferredWallpaperScale) : 1920, bgRoot.screen.height > 0 ? Math.round(bgRoot.screen.height * bgRoot.preferredWallpaperScale) : 1080) : Qt.size(-1, -1)

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
                                property real effectiveValueX: bgRoot.parallaxFrozen ? 0.5 : Math.max(0, Math.min(1, valueX)) + sidebarOffsetX
                                property real effectiveValueY: bgRoot.parallaxFrozen ? 0.5 : Math.max(0, Math.min(1, valueY))

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
                                    SequentialAnimation {
                                        // Delay blur fade-in so zoom-out animation is visible first
                                        PauseAnimation { duration: GlobalStates.screenLocked ? 150 : 0 }
                                        NumberAnimation {
                                            duration: 350
                                            easing.type: Easing.OutCubic
                                        }
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

                            Rectangle {
                                id: wallpaperDimLayer
                                anchors.fill: wallpaper
                                color: "black"
                                opacity: bgRoot.anyWidgetIsDragging ? 0.45 : 0.0
                                visible: opacity > 0

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 350
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }


                            Loader {
                                id: gradientBlurLoader

                                active: Config.options.background.gradientBlur.enable
                                anchors.fill: wallpaper
                                visible: active
                                sourceComponent: Item {
                                    anchors.fill: parent

                                    Image {
                                        id: gradientBlurSource
                                        anchors.fill: parent
                                        source: bgRoot.wallpaperPath
                                        fillMode: Image.PreserveAspectCrop
                                        visible: false
                                    }

                                    // Light blur layer — full intensity at start, fading to 0
                                    Item {
                                        id: lightBlurWrapper
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: lightBlurMask
                                        }

                                        FastBlur {
                                            anchors.fill: parent
                                            source: gradientBlurSource
                                            radius: Math.round(Config.options.background.gradientBlur.radius * 0.32)
                                            transparentBorder: true
                                        }
                                    }

                                    Item {
                                        id: lightBlurMask
                                        anchors.fill: parent
                                        visible: false

                                        Canvas {
                                            anchors.fill: parent
                                            readonly property string dir: Config.options.background.gradientBlur.direction

                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ctx.reset();

                                                var gradient;
                                                if (dir === "left-to-right") {
                                                    gradient = ctx.createLinearGradient(0, 0, width, 0);
                                                } else if (dir === "right-to-left") {
                                                    gradient = ctx.createLinearGradient(width, 0, 0, 0);
                                                } else if (dir === "bottom-to-top") {
                                                    gradient = ctx.createLinearGradient(0, height, 0, 0);
                                                } else {
                                                    gradient = ctx.createLinearGradient(0, 0, 0, height);
                                                }

                                                gradient.addColorStop(0.0, "rgba(255, 255, 255, 1)");
                                                gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.5)");
                                                gradient.addColorStop(1.0, "rgba(255, 255, 255, 0)");

                                                ctx.fillStyle = gradient;
                                                ctx.fillRect(0, 0, width, height);
                                            }

                                            onWidthChanged: requestPaint()
                                            onHeightChanged: requestPaint()
                                        }
                                    }

                                    // Heavy blur layer — 0 at start, full intensity at end
                                    Item {
                                        id: heavyBlurWrapper
                                        anchors.fill: parent
                                        layer.enabled: true
                                        layer.effect: OpacityMask {
                                            maskSource: heavyBlurMask
                                        }

                                        FastBlur {
                                            anchors.fill: parent
                                            source: gradientBlurSource
                                            radius: Math.round(Config.options.background.gradientBlur.radius * 0.64)
                                            transparentBorder: true
                                        }
                                    }

                                    Item {
                                        id: heavyBlurMask
                                        anchors.fill: parent
                                        visible: false

                                        Canvas {
                                            anchors.fill: parent
                                            readonly property string dir: Config.options.background.gradientBlur.direction

                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ctx.reset();

                                                var gradient;
                                                if (dir === "left-to-right") {
                                                    gradient = ctx.createLinearGradient(0, 0, width, 0);
                                                } else if (dir === "right-to-left") {
                                                    gradient = ctx.createLinearGradient(width, 0, 0, 0);
                                                } else if (dir === "bottom-to-top") {
                                                    gradient = ctx.createLinearGradient(0, height, 0, 0);
                                                } else {
                                                    gradient = ctx.createLinearGradient(0, 0, 0, height);
                                                }

                                                gradient.addColorStop(0.0, "rgba(255, 255, 255, 0)");
                                                gradient.addColorStop(0.5, "rgba(255, 255, 255, 0.5)");
                                                gradient.addColorStop(1.0, "rgba(255, 255, 255, 1)");

                                                ctx.fillStyle = gradient;
                                                ctx.fillRect(0, 0, width, height);
                                            }

                                            onWidthChanged: requestPaint()
                                            onHeightChanged: requestPaint()

                                            Connections {
                                                target: Config.options.background.gradientBlur
                                                function onDirectionChanged() {
                                                    lightBlurMask.requestPaint();
                                                    heavyBlurMask.requestPaint();
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            WidgetCanvas {
                                id: widgetCanvas
                                scale: 1 - (defaultRatio - 1)
                                // Render widget tree as a single GPU texture during lock anim
                                // Eliminates per-frame relayout of the full widget tree
                                layer.enabled: bgRoot.lockAnimationActive
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
                                // Lock centering: animate margin offsets instead of AnchorChanges
                                // AnchorAnimation invalidates full layout each frame — too expensive
                                states: State {
                                    name: "centered"
                                    when: GlobalStates.screenLocked || GlobalStates.workspaceRestoreInProgress || bgRoot.wallpaperSafetyTriggered
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

                                Component {
                                    id: component_clock_cookie
                                    ClockWidget {
                                        styleOverride: "cookie"
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                                    }
                                }

                                Component {
                                    id: component_clock_digital
                                    ClockWidget {
                                        styleOverride: "digital"
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                                    }
                                }

                                Component {
                                    id: component_clock_nagasaki
                                    ClockWidget {
                                        styleOverride: "nagasaki"
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                                    }
                                }

                                Component {
                                    id: component_clock_dial
                                    ClockWidget {
                                        styleOverride: "dial"
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                        wallpaperSafetyTriggered: bgRoot.wallpaperSafetyTriggered
                                    }
                                }

                                Component {
                                    id: component_circular_media
                                    CircularMediaWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: component_clock_wearos
                                    WearOSClockWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: component_media_circular
                                    MediaWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: component_media_expressive
                                    ExpressiveMediaWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: component_media_android
                                    AndroidMediaWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: component_weather_default
                                    WeatherWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: component_weather_expressive
                                    ExpressiveWeatherWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: component_date_default
                                    DateWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                Component {
                                    id: component_photo_default
                                    PhotoWidget {
                                        screenWidth: bgRoot.screen.width
                                        screenHeight: bgRoot.screen.height
                                        scaledScreenWidth: bgRoot.screen.width / bgRoot.effectiveWallpaperScale
                                        scaledScreenHeight: bgRoot.screen.height / bgRoot.effectiveWallpaperScale
                                        wallpaperScale: bgRoot.effectiveWallpaperScale
                                    }
                                }

                                property var widgetComponentMap: ({
                                    "clock_cookie": component_clock_cookie,
                                    "clock_digital": component_clock_digital,
                                    "clock_nagasaki": component_clock_nagasaki,
                                    "clock_dial": component_clock_dial,
                                    "clock_wearos": component_clock_wearos,
                                    "circular_media": component_circular_media,
                                    "media_circular": component_media_circular,
                                    "media_expressive": component_media_expressive,
                                    "media_android": component_media_android,
                                    "weather_default": component_weather_default,
                                    "weather_expressive": component_weather_expressive,
                                    "date_default": component_date_default,
                                    "photo_default": component_photo_default
                                })

                                // Cache of dynamically created extension components keyed by extId.
                                // Busted when extensionsChanged fires so updates always get a fresh compile.
                                property var extComponentCache: ({})

                                Connections {
                                    target: WidgetExtensionManager
                                    function onExtensionsChanged() {
                                        widgetCanvas.extComponentCache = ({});
                                    }
                                }

                                function getExtUrl(extId) {
                                    // Returns the file:// URL of the ext widget QML.
                                    // Loader.source handles async loading correctly.
                                    let entry = WidgetExtensionManager.installedWidgets[extId];
                                    if (!entry) return "";
                                    let wj = entry.widgetJson || {};
                                    let qmlFile = wj.component ||
                                        (wj.widget && wj.widget.component ? wj.widget.component : "main.qml");
                                    return "file://" + entry.installedPath + "/" + qmlFile;
                                }

                                Repeater {
                                    model: widgetListModel
                                    delegate: Item {
                                        id: delegateRoot
                                        
                                        required property int index
                                        required property string widgetId
                                        required property string instanceId
                                        required property real widgetX
                                        required property real widgetY
                                        required property string placementStrategy
                                        required property string lockBehavior

                                        FadeLoader {
                                            id: widgetLoader
                                            shown: true
                                            visible: !bgRoot.lockAnimationActive 
                                                || (delegateRoot.widgetId && delegateRoot.widgetId.startsWith("clock") && !Config.options.background.widgets.clock.disableAnimationOnLock) 
                                                || delegateRoot.lockBehavior === "center" 
                                                || delegateRoot.lockBehavior === "keep"
                                            
                                            // Extension widgets use source (URL) — Loader handles async internally.
                                            // Builtin widgets use sourceComponent (static Component map).
                                            source: delegateRoot.widgetId.startsWith("ext:")
                                                ? widgetCanvas.getExtUrl(delegateRoot.widgetId.substring(4))
                                                : ""

                                            sourceComponent: delegateRoot.widgetId.startsWith("ext:")
                                                ? null
                                                : (widgetCanvas.widgetComponentMap[delegateRoot.widgetId] || null)

                                            Binding {
                                                target: widgetLoader.item
                                                property: "widgetInstance"
                                                value: {
                                                    return {
                                                        "id": delegateRoot.instanceId,
                                                        "widgetId": delegateRoot.widgetId,
                                                        "x": delegateRoot.widgetX,
                                                        "y": delegateRoot.widgetY,
                                                        "placementStrategy": delegateRoot.placementStrategy,
                                                        "lockBehavior": delegateRoot.lockBehavior
                                                    };
                                                }
                                                when: widgetLoader.status == Loader.Ready
                                            }

                                            // Inject extension-specific props when it's an ext: widget
                                            Binding {
                                                target: widgetLoader.item
                                                property: "widgetExtensionId"
                                                value: delegateRoot.widgetId.startsWith("ext:") ? delegateRoot.widgetId.substring(4) : ""
                                                when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
                                            }
                                            Binding {
                                                target: widgetLoader.item
                                                property: "widgetConfig"
                                                value: {
                                                    if (!delegateRoot.widgetId.startsWith("ext:")) return null;
                                                    let extId = delegateRoot.widgetId.substring(4);
                                                    return WidgetExtensionManager.widgetConfigs[extId] || ({});
                                                }
                                                when: widgetLoader.status == Loader.Ready && delegateRoot.widgetId.startsWith("ext:")
                                            }
                                        }

                                        // Placeholder shown when an ext:* widget is not installed
                                        Rectangle {
                                            id: missingWidgetPlaceholder
                                            visible: {
                                                if (!delegateRoot.widgetId.startsWith("ext:")) return false;
                                                if (!WidgetExtensionManager.ready) return false;
                                                let extId = delegateRoot.widgetId.substring(4);
                                                return !WidgetExtensionManager.isWidgetInstalled(extId);
                                            }

                                            x: delegateRoot.widgetX
                                            y: delegateRoot.widgetY
                                            width: 220
                                            height: 96
                                            radius: Appearance.rounding.large
                                            color: missingPlaceholderMouse.containsMouse
                                                ? Qt.rgba(0.12, 0, 0, 0.72)
                                                : Qt.rgba(0, 0, 0, 0.55)
                                            border.color: Qt.rgba(1, 0.4, 0.4, 0.5)
                                            border.width: 1

                                            Behavior on color { ColorAnimation { duration: 120 } }

                                            MouseArea {
                                                id: missingPlaceholderMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Config.removeWidgetFromDesktop(delegateRoot.widgetId)
                                            }

                                            Column {
                                                anchors {
                                                    left: parent.left
                                                    right: parent.right
                                                    verticalCenter: parent.verticalCenter
                                                }
                                                spacing: 4

                                                MaterialSymbol {
                                                    text: "extension_off"
                                                    iconSize: 18
                                                    color: "#ff8a8a"
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                }

                                                Text {
                                                    text: delegateRoot.widgetId.substring(4) + "\nnot installed"
                                                    color: "#ffaaaa"
                                                    font.pixelSize: 10
                                                    horizontalAlignment: Text.AlignHCenter
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                }

                                                // Remove hint
                                                Rectangle {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    width: removeHintRow.implicitWidth + 16
                                                    height: 20
                                                    radius: height / 2
                                                    color: Qt.rgba(1, 0.3, 0.3, 0.3)

                                                    Row {
                                                        id: removeHintRow
                                                        anchors.centerIn: parent
                                                        spacing: 3

                                                        MaterialSymbol {
                                                            text: "close"
                                                            iconSize: 10
                                                            color: "#ffaaaa"
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }

                                                        Text {
                                                            text: "Click to remove"
                                                            color: "#ffaaaa"
                                                            font.pixelSize: 9
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MultiEffect {
                            id: windowBlurEffect
                            anchors.fill: parent

                            
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

                            // Overscan slightly so the blur's edge fringe lands offscreen
                            

                            Rectangle {
                                anchors.fill: parent
                                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.4)
                            }
                        }
                    }
                }

                // Bar blur gradient — blur na borda da bar, mesma posição do dim
                Item {
                    id: barBlurOverlay
                    anchors.fill: wallpaperItem

                    readonly property bool shouldShow: Config.options.bar.barBackgroundStyle === 0
                        && Config.options.bar.transparentGlow
                        && GlobalStates.barOpen
                        && !GlobalStates.screenLocked

                    visible: opacity > 0.001
                    opacity: shouldShow ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    readonly property bool isVertical: Config.options.bar.vertical
                    readonly property bool isBottom: Config.options.bar.bottom
                    readonly property int barSize: isVertical
                        ? Appearance.sizes.verticalBarWidth
                        : Appearance.sizes.barHeight
                    readonly property int overlaySpan: barSize + 80
                    readonly property int overlayX: isVertical ? (isBottom ? parent.width - overlaySpan : 0) : 0
                    readonly property int overlayY: !isVertical ? (isBottom ? parent.height - overlaySpan : 0) : 0
                    readonly property int overlayW: isVertical ? overlaySpan : parent.width
                    readonly property int overlayH: !isVertical ? overlaySpan : parent.height

                    Item {
                        x: barBlurOverlay.overlayX
                        y: barBlurOverlay.overlayY
                        width: barBlurOverlay.overlayW
                        height: barBlurOverlay.overlayH
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: barBlurGradientMask
                        }

                        ShaderEffectSource {
                            id: barBlurShaderSource
                            sourceItem: centralWallpaperClipRect
                            sourceRect: Qt.rect(barBlurOverlay.overlayX, barBlurOverlay.overlayY, barBlurOverlay.overlayW, barBlurOverlay.overlayH)
                            width: barBlurOverlay.overlayW
                            height: barBlurOverlay.overlayH
                            live: true
                            hideSource: false
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: barBlurShaderSource
                            blurEnabled: true
                            blurMax: 64
                            blur: 0.35
                        }
                    }

                    Item {
                        id: barBlurGradientMask
                        x: barBlurOverlay.overlayX
                        y: barBlurOverlay.overlayY
                        width: barBlurOverlay.overlayW
                        height: barBlurOverlay.overlayH
                        opacity: 0 // Invisible visually, but OpacityMask reads it internally

                        Canvas {
                            anchors.fill: parent
                            readonly property bool isVertical: barBlurOverlay.isVertical
                            readonly property bool isBottom: barBlurOverlay.isBottom

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();

                                // Gradient direction: always TOWARD the bar side
                                // Bar side = opaque (max blur), far side = transparent
                                var gradient;
                                if (isVertical) {
                                    // Horizontal gradient
                                    gradient = isBottom
                                        ? ctx.createLinearGradient(0, 0, width, 0)   // left→right (right bar)
                                        : ctx.createLinearGradient(width, 0, 0, 0);   // right→left (left bar)
                                } else {
                                    // Vertical gradient
                                    gradient = isBottom
                                        ? ctx.createLinearGradient(0, 0, 0, height)  // top→bottom (bottom bar)
                                        : ctx.createLinearGradient(0, height, 0, 0);  // bottom→top (top bar)
                                }

                                gradient.addColorStop(0.0, "rgba(255, 255, 255, 0)");
                                gradient.addColorStop(0.55, "rgba(255, 255, 255, 0.4)");
                                gradient.addColorStop(1.0, "rgba(255, 255, 255, 1)");

                                ctx.fillStyle = gradient;
                                ctx.fillRect(0, 0, width, height);
                            }

                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onIsVerticalChanged: requestPaint()
                            onIsBottomChanged: requestPaint()
                        }
                    }
                }

                // Bar gradient overlay — overlay simples sobre o wallpaper na borda da bar
                // Sem ShaderEffectSource/MultiEffect: não mexe no wallpaper, só sobrepõe
                Item {
                    id: barGradientOverlay
                    anchors.fill: wallpaperItem

                    readonly property bool shouldShow: Config.options.bar.barBackgroundStyle === 0
                        && Config.options.bar.transparentGlow
                        && GlobalStates.barOpen
                        && !GlobalStates.screenLocked

                    visible: opacity > 0.001
                    opacity: shouldShow ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }

                    readonly property bool isVertical: Config.options.bar.vertical
                    readonly property bool isBottom: Config.options.bar.bottom
                    readonly property int barSize: isVertical
                        ? Appearance.sizes.verticalBarWidth
                        : Appearance.sizes.barHeight

                    // Faixa de gradiente apenas na borda da bar
                    // Largura/altura = tamanho da bar + fade
                    readonly property int overlaySpan: barSize + 80

                    // Posição e dimensões dependem de onde a bar está
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

                            // Lado onde a bar fica — mais escuro
                            GradientStop {
                                position: 0.0
                                color: barGradientOverlay.isVertical
                                    ? (barGradientOverlay.isBottom ? "transparent" : Qt.rgba(0,0,0,0.45))
                                    : (!barGradientOverlay.isBottom ? Qt.rgba(0,0,0,0.45) : "transparent")
                            }
                            GradientStop {
                                position: 0.55
                                color: barGradientOverlay.isVertical
                                    ? (barGradientOverlay.isBottom ? "transparent" : Qt.rgba(0,0,0,0.15))
                                    : (!barGradientOverlay.isBottom ? Qt.rgba(0,0,0,0.15) : "transparent")
                            }
                            GradientStop {
                                position: 1.0
                                color: barGradientOverlay.isVertical
                                    ? (barGradientOverlay.isBottom ? Qt.rgba(0,0,0,0.45) : "transparent")
                                    : (!barGradientOverlay.isBottom ? "transparent" : Qt.rgba(0,0,0,0.45))
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
