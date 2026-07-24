import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractWidget {
    id: root

    property string configEntryName: ""
    property var widgetInstance: null
    property bool isPreview: false
    property string styleOverride: widgetInstance ? (WidgetsRegistry.getStyleOverride(widgetInstance.widgetId) || "") : ""

    property int screenWidth: 1920
    property int screenHeight: 1080
    property int scaledScreenWidth: 1920
    property int scaledScreenHeight: 1080
    property real wallpaperScale: 1.0
    property var widgetListModel: null
    property var widgetSizes: ({})
    property int widgetSizesVersion: 0
    property var configEntry: widgetInstance !== null ? widgetInstance : (Config.options.background.widgets[configEntryName] || null)
    property string placementStrategy: isPreview ? "free" : (widgetInstance !== null ? (widgetInstance.placementStrategy || "free") : (configEntry ? configEntry.placementStrategy : "free"))
    property string lockBehavior: widgetInstance ? (widgetInstance.lockBehavior || "hide") : "hide"
    property bool visibleWhenLocked: lockBehavior === "keep" || lockBehavior === "center" || lockBehavior === "lockOnly"
    property bool forceCenter: (GlobalStates.lockScreenCentered || GlobalStates.workspaceRestoreInProgress) && lockBehavior === "center"

    function getCenteredWidgetsList() {
        if (!widgetListModel) return [];
        let result = [];
        for (let i = 0; i < widgetListModel.count; i++) {
            let w = widgetListModel.get(i);
            let lb = w.lockBehavior || "hide";
            let isCentered = lb === "center";
            if (isCentered) {
                result.push(w);
            }
        }
        return result;
    }

    readonly property var centeredWidgetsList: {
        backgroundScope.widgetSyncVersion; // dependency to force re-evaluation
        return getCenteredWidgetsList();
    }
    readonly property int centeredWidgetCount: centeredWidgetsList.length
    readonly property int centeredWidgetIndex: {
        if (!widgetInstance) return 0;
        for (let i = 0; i < centeredWidgetsList.length; i++) {
            if (centeredWidgetsList[i].instanceId === widgetInstance.id) return i;
        }
        return 0;
    }

    readonly property real centeredOffsetX: {
        if (centeredWidgetCount <= 1) return 0;
        let alignment = Config.options.lock.centerAlignment;
        if (alignment === "horizontal" || alignment === undefined || alignment === "") {
            let spacing = Config.options.lock.centerSpacing || 20;
            // Depend on widgetSizesVersion so binding re-evaluates after in-place mutations
            root.widgetSizesVersion;
            let sizes = root.widgetSizes || {};
            // Accumulate actual widths of all centered widgets
            let totalWidth = 0;
            let widths = [];
            for (let i = 0; i < centeredWidgetCount; i++) {
                let wInstanceId = centeredWidgetsList[i].instanceId || centeredWidgetsList[i].id;
                let wSize = sizes[wInstanceId];
                let w = (wSize && wSize.width > 0) ? wSize.width : root.width;
                widths.push(w);
                totalWidth += w;
            }
            totalWidth += (centeredWidgetCount - 1) * spacing;
            // Position of this widget within the group
            let myX = 0;
            for (let i = 0; i < centeredWidgetIndex; i++) {
                myX += widths[i] + spacing;
            }
            let result = myX - (totalWidth - root.width) / 2;
            return result;
        }
        return 0;
    }

    readonly property real centeredOffsetY: {
        if (centeredWidgetCount <= 1) return 0;
        let alignment = Config.options.lock.centerAlignment;
        if (alignment === "vertical") {
            let spacing = Config.options.lock.centerSpacing || 20;
            root.widgetSizesVersion;
            let sizes = root.widgetSizes || {};
            // Accumulate actual heights of all centered widgets
            let totalHeight = 0;
            let heights = [];
            for (let i = 0; i < centeredWidgetCount; i++) {
                let wInstanceId = centeredWidgetsList[i].instanceId || centeredWidgetsList[i].id;
                let wSize = sizes[wInstanceId];
                let h = (wSize && wSize.height > 0) ? wSize.height : root.height;
                heights.push(h);
                totalHeight += h;
            }
            totalHeight += (centeredWidgetCount - 1) * spacing;
            // Position of this widget within the group
            let myY = 0;
            for (let i = 0; i < centeredWidgetIndex; i++) {
                myY += heights[i] + spacing;
            }
            return myY - (totalHeight - root.height) / 2;
        }
        return 0;
    }

    readonly property real centeringX: (screenWidth - width) / 2 + centeredOffsetX
    readonly property real centeringY: (screenHeight - height) / 2 + centeredOffsetY

    // Register own size in the shared map whenever width/height changes
    function _registerOwnSize() {
        if (!widgetInstance) return;
        let id = widgetInstance.id;
        if (!id || width <= 0 || height <= 0) return;
        // Mutate in-place to preserve the shared reference across all widget instances
        root.widgetSizes[id] = { "width": width, "height": height };
        // Bump the version counter on widgetStateManager to trigger binding re-evaluation
        if (typeof backgroundScope !== 'undefined' && backgroundScope.widgetStateManager) {
            backgroundScope.widgetStateManager.widgetSizesVersion++;
        }
    }
    onWidthChanged: _registerOwnSize()
    onHeightChanged: _registerOwnSize()
    onWidgetInstanceChanged: _registerOwnSize()

    onForceCenterChanged: {
        root.animDuration = Math.round(450 * Appearance.animMultiplier);
        if (forceCenter) {
            lockAnimResetTimer.restart();
        } else {
            unlockAnimResetTimer.restart();
        }
    }
    Timer {
        id: lockAnimResetTimer
        interval: Math.round(450 * Appearance.animMultiplier)
        repeat: false
        onTriggered: { root.animDuration = Appearance.animation.elementMove.duration; }
    }
    Timer {
        id: unlockAnimResetTimer
        interval: Math.round(450 * Appearance.animMultiplier)
        repeat: false
        onTriggered: { root.animDuration = Appearance.animation.elementMove.duration; }
    }

    property real calculatedX: 0
    property real calculatedY: 0
    property real staggerDelay: 0
    property bool _pendingPosition: false
    property real targetX: isPreview ? 0 : (forceCenter ? centeringX : ((placementStrategy === "free" || placementStrategy === "draggable") ? Math.max(0, Math.min(widgetInstance !== null ? widgetInstance.x : (configEntry ? configEntry.x : 0), scaledScreenWidth - width)) : calculatedX))
    property real targetY: isPreview ? 0 : (forceCenter ? centeringY : ((placementStrategy === "free" || placementStrategy === "draggable") ? Math.max(0, Math.min(widgetInstance !== null ? widgetInstance.y : (configEntry ? configEntry.y : 0), scaledScreenHeight - height)) : calculatedY))
    property bool isDraggingOrSettling: false

    onIsPreviewChanged: {
        if (isPreview) {
            root.x = 0;
            root.y = 0;
        }
    }

    Component.onCompleted: {
        root.animateXPos = false;
        root.animateYPos = false;
        if (root.isPreview) {
            root.x = 0;
            root.y = 0;
        } else {
            root.x = root.targetX;
            root.y = root.targetY;
        }
        Qt.callLater(() => {
            root.animateXPos = !root.drag.active;
            root.animateYPos = !root.drag.active;
        });
    }

    Timer {
        id: staggerTimer
        repeat: false
        onTriggered: {
            root._pendingPosition = false;
            if (!root.isDragging && !root.isDraggingOrSettling && !root.isPreview) {
                if (root.x !== root.targetX) root.x = root.targetX;
                if (root.y !== root.targetY) root.y = root.targetY;
            }
        }
    }

    Timer {
        id: settleTimer
        interval: 350
        repeat: false
        onTriggered: {
            root.isDraggingOrSettling = false;
            if (!root.isPreview) {
                if (root.x !== root.targetX) root.x = root.targetX;
                if (root.y !== root.targetY) root.y = root.targetY;
            }
        }
    }

    Item {
        id: dragProxy
        parent: root.parent
        x: root.x
        y: root.y
    }

    readonly property bool isDragging: drag.active
    onIsDraggingChanged: {
        let canvas = findCanvas(root.parent);
        if (canvas) {
            canvas.draggingActive = isDragging;
        }
        if (!isDragging) {
            dragProxy.x = root.x;
            dragProxy.y = root.y;
            if (canvas) {
                canvas.snapLineX = -1;
                canvas.snapLineY = -1;
            }
        }
    }

    Binding {
        target: root
        property: "x"
        value: applyGridAndSnapX(dragProxy.x)
        when: isDragging && !root.isPreview
        restoreMode: Binding.RestoreNone
    }
    Binding {
        target: root
        property: "y"
        value: applyGridAndSnapY(dragProxy.y)
        when: isDragging && !root.isPreview
        restoreMode: Binding.RestoreNone
    }

    onPressedChanged: {
        if (pressed) {
            isDraggingOrSettling = true;
        }
    }

    onTargetXChanged: {
        if (!isDragging && !root.isDraggingOrSettling && !root.isPreview) {
            if (root.staggerDelay > 0) {
                root._pendingPosition = true;
                staggerTimer.interval = root.staggerDelay;
                staggerTimer.restart();
            } else {
                root.x = targetX;
            }
        }
    }
    onTargetYChanged: {
        if (!isDragging && !root.isDraggingOrSettling && !root.isPreview) {
            if (root.staggerDelay > 0) {
                root._pendingPosition = true;
                staggerTimer.interval = root.staggerDelay;
                staggerTimer.restart();
            } else {
                root.y = targetY;
            }
        }
    }



    visible: opacity > 0
    opacity: {
        if (lockBehavior === "lockOnly") return GlobalStates.lockScreenCentered ? 1 : 0;
        if (GlobalStates.lockScreenCentered && !visibleWhenLocked) return 0;
        return 1;
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    readonly property real lockScaleFactor: lockBehavior === "center" ? 1.0 : (GlobalStates.lockAnimationActive ? 0.85 : 1.0)
    scale: ((draggable && containsPress) ? 1.05 : 1.0) * (Config.options.background.widgets.widgetsScale ?? 1.0) * lockScaleFactor
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    function findCanvas(item) {
        var p = item
        while (p) {
            if (p.isWidgetCanvas === true) return p
            p = p.parent
        }
        return null
    }

    function applyGridAndSnapX(targetXVal) {
        if (Config.options.background.widgets.enableGrid ?? false) {
            targetXVal = Math.round(targetXVal / 10) * 10;
        }
        let canvas = findCanvas(root.parent);
        let snapped = false;
        if (Config.options.background.widgets.enableSnap ?? false) {
            let snapThreshold = 20;
            if (widgetListModel) {
                for (let i = 0; i < widgetListModel.count; i++) {
                    let w = widgetListModel.get(i);
                    if (widgetInstance && w.instanceId === widgetInstance.id) continue;
                    
                    let verticallyClose = Math.abs(root.y - w.widgetY) < 600;
                    if (!verticallyClose) continue;

                    let wId = w.instanceId || w.id;
                    let wWidth = (widgetSizes && widgetSizes[wId] && widgetSizes[wId].width > 0) ? widgetSizes[wId].width : root.width;
                    
                    // 1. Align Left-to-Left: root.x = w.widgetX
                    if (Math.abs(targetXVal - w.widgetX) < snapThreshold) {
                        targetXVal = w.widgetX;
                        if (isDragging && canvas) canvas.snapLineX = w.widgetX;
                        snapped = true;
                        break;
                    }
                    // 2. Align Right-to-Right: root.x + root.width = w.widgetX + wWidth => root.x = w.widgetX + wWidth - root.width
                    if (Math.abs((targetXVal + root.width) - (w.widgetX + wWidth)) < snapThreshold) {
                        targetXVal = w.widgetX + wWidth - root.width;
                        if (isDragging && canvas) canvas.snapLineX = w.widgetX + wWidth;
                        snapped = true;
                        break;
                    }
                    // 3. Align Left-to-Right (Adjacent): root.x = w.widgetX + wWidth
                    if (Math.abs(targetXVal - (w.widgetX + wWidth)) < snapThreshold) {
                        targetXVal = w.widgetX + wWidth;
                        if (isDragging && canvas) canvas.snapLineX = w.widgetX + wWidth;
                        snapped = true;
                        break;
                    }
                    // 4. Align Right-to-Left (Adjacent): root.x + root.width = w.widgetX => root.x = w.widgetX - root.width
                    if (Math.abs((targetXVal + root.width) - w.widgetX) < snapThreshold) {
                        targetXVal = w.widgetX - root.width;
                        if (isDragging && canvas) canvas.snapLineX = w.widgetX;
                        snapped = true;
                        break;
                    }
                }
            }
        }
        if (!snapped && canvas) canvas.snapLineX = -1;
        return targetXVal;
    }

    function applyGridAndSnapY(targetYVal) {
        if (Config.options.background.widgets.enableGrid ?? false) {
            targetYVal = Math.round(targetYVal / 10) * 10;
        }
        let canvas = findCanvas(root.parent);
        let snapped = false;
        if (Config.options.background.widgets.enableSnap ?? false) {
            let snapThreshold = 20;
            if (widgetListModel) {
                for (let i = 0; i < widgetListModel.count; i++) {
                    let w = widgetListModel.get(i);
                    if (widgetInstance && w.instanceId === widgetInstance.id) continue;
                    
                    let horizontallyClose = Math.abs(root.x - w.widgetX) < 600;
                    if (!horizontallyClose) continue;

                    let wId = w.instanceId || w.id;
                    let wHeight = (widgetSizes && widgetSizes[wId] && widgetSizes[wId].height > 0) ? widgetSizes[wId].height : root.height;
                    
                    // 1. Align Top-to-Top: root.y = w.widgetY
                    if (Math.abs(targetYVal - w.widgetY) < snapThreshold) {
                        targetYVal = w.widgetY;
                        if (isDragging && canvas) canvas.snapLineY = w.widgetY;
                        snapped = true;
                        break;
                    }
                    // 2. Align Bottom-to-Bottom: root.y + root.height = w.widgetY + wHeight => root.y = w.widgetY + wHeight - root.height
                    if (Math.abs((targetYVal + root.height) - (w.widgetY + wHeight)) < snapThreshold) {
                        targetYVal = w.widgetY + wHeight - root.height;
                        if (isDragging && canvas) canvas.snapLineY = w.widgetY + wHeight;
                        snapped = true;
                        break;
                    }
                    // 3. Align Top-to-Bottom (Adjacent): root.y = w.widgetY + wHeight
                    if (Math.abs(targetYVal - (w.widgetY + wHeight)) < snapThreshold) {
                        targetYVal = w.widgetY + wHeight;
                        if (isDragging && canvas) canvas.snapLineY = w.widgetY + wHeight;
                        snapped = true;
                        break;
                    }
                    // 4. Align Bottom-to-Top (Adjacent): root.y + root.height = w.widgetY => root.y = w.widgetY - root.height
                    if (Math.abs((targetYVal + root.height) - w.widgetY) < snapThreshold) {
                        targetYVal = w.widgetY - root.height;
                        if (isDragging && canvas) canvas.snapLineY = w.widgetY;
                        snapped = true;
                        break;
                    }
                }
            }
        }
        if (!snapped && canvas) canvas.snapLineY = -1;
        return targetYVal;
    }

    draggable: !isPreview && !(Config.options.background.widgets.lockWidgetPositions ?? false) && (placementStrategy === "free" || placementStrategy === "draggable")
    drag.target: draggable ? dragProxy : undefined
    drag.minimumX: 0
    drag.maximumX: scaledScreenWidth - width
    drag.minimumY: 0
    drag.maximumY: scaledScreenHeight - height

    animateXPos: !isDragging && !isDraggingOrSettling && (visibleWhenLocked || !GlobalStates.screenLocked)
    animateYPos: !isDragging && !isDraggingOrSettling && (visibleWhenLocked || !GlobalStates.screenLocked)
    onXChanged: {
        if (isDragging) {
            if (widgetInstance === null && configEntry) configEntry.x = x;
        }
    }
    onYChanged: {
        if (isDragging) {
            if (widgetInstance === null && configEntry) configEntry.y = y;
        }
    }
    onReleased: {
        if (isPreview) return;
        let finalX = applyGridAndSnapX(dragProxy.x);
        let finalY = applyGridAndSnapY(dragProxy.y);
        root.x = finalX;
        root.y = finalY;
        
        let canvas = findCanvas(root.parent);
        if (canvas) {
            canvas.snapLineX = -1;
            canvas.snapLineY = -1;
        }
        
        if (widgetInstance !== null) {
            Config.updateWidgetPosition(widgetInstance.id, finalX, finalY);
        } else if (configEntry) {
            configEntry.x = finalX;
            configEntry.y = finalY;
        }
        settleTimer.restart();
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.lockScreenCentered && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }
    property color colTextSecondary: {
        const onNormalBackground = (GlobalStates.lockScreenCentered && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colSecondary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }
    property color colTextTertiary: {
        const onNormalBackground = (GlobalStates.lockScreenCentered && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colTertiary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }

    property bool wallpaperIsVideo: Config.options.background.wallpaperPath.endsWith(".mp4") || Config.options.background.wallpaperPath.endsWith(".webm") || Config.options.background.wallpaperPath.endsWith(".mkv") || Config.options.background.wallpaperPath.endsWith(".avi") || Config.options.background.wallpaperPath.endsWith(".mov")
    property string wallpaperPath: wallpaperIsVideo ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    
    onWallpaperPathChanged: refreshPlacementIfNeeded()
    onPlacementStrategyChanged: refreshPlacementIfNeeded()
    Connections {
        target: Config
        function onReadyChanged() { refreshPlacementIfNeeded() }
    }
    function refreshPlacementIfNeeded() {
        if (isPreview) return;
        if (!Config.ready) return;
        if ((root.placementStrategy === "free" || root.placementStrategy === "draggable") && !root.needsColText) return;
        leastBusyRegionProc.wallpaperPath = root.wallpaperPath;
        leastBusyRegionProc.running = false;
        leastBusyRegionProc.running = true;
    }
    Process {
        id: leastBusyRegionProc
        property string wallpaperPath: root.wallpaperPath
        // TODO: make these less arbitrary
        property int contentWidth: 300
        property int contentHeight: 300
        property int horizontalPadding: 200
        property int verticalPadding: 200
        command: [Quickshell.shellPath("scripts/images/least-busy-region-venv.sh") // Comments to force the formatter to break lines
            , "--screen-width", Math.round(root.scaledScreenWidth) //
            , "--screen-height", Math.round(root.scaledScreenHeight) //
            , "--width", contentWidth //
            , "--height", contentHeight //
            , "--horizontal-padding", horizontalPadding //
            , "--vertical-padding", verticalPadding //
            , wallpaperPath //
            , ...(root.placementStrategy === "mostBusy" || root.placementStrategy === "most_busy" ? ["--busiest"] : [])
            // "--visual-output",
        ]
        stdout: StdioCollector {
            id: leastBusyRegionOutputCollector
            onStreamFinished: {
                const output = leastBusyRegionOutputCollector.text;
                // console.log("[Background] Least busy region output:", output)
                if (output.length === 0) return;
                const parsedContent = JSON.parse(output);
                root.dominantColor = parsedContent.dominant_color || Appearance.colors.colPrimary;
                root.calculatedX = parsedContent.center_x * root.wallpaperScale - root.width / 2;
                root.calculatedY  = parsedContent.center_y * root.wallpaperScale - root.height / 2;
            }
        }
    }


}

