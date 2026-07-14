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
    property var configEntry: widgetInstance !== null ? widgetInstance : (Config.options.background.widgets[configEntryName] || null)
    property string placementStrategy: isPreview ? "free" : (widgetInstance !== null ? (widgetInstance.placementStrategy || "free") : (configEntry ? configEntry.placementStrategy : "free"))
    property string lockBehavior: widgetInstance ? (widgetInstance.lockBehavior || "hide") : "hide"
    property bool visibleWhenLocked: lockBehavior === "keep" || lockBehavior === "center" || lockBehavior === "lockOnly" || (
        Config.options.lock.centerWidget !== "none" && widgetInstance && widgetInstance.widgetId && widgetInstance.widgetId.startsWith(Config.options.lock.centerWidget)
    )
    property bool forceCenter: GlobalStates.screenLocked && (lockBehavior === "center" || (lockBehavior === "hide" && Config.options.lock.centerWidget !== "none" && widgetInstance && widgetInstance.widgetId && widgetInstance.widgetId.startsWith(Config.options.lock.centerWidget)))

    function getCenteredWidgetsList() {
        if (typeof widgetListModel === "undefined") return [];
        let result = [];
        for (let i = 0; i < widgetListModel.count; i++) {
            let w = widgetListModel.get(i);
            let lb = w.lockBehavior || "hide";
            let isCentered = lb === "center" || (lb === "hide" && Config.options.lock.centerWidget !== "none" && w.widgetId && w.widgetId.startsWith(Config.options.lock.centerWidget));
            if (isCentered) {
                result.push(w);
            }
        }
        return result;
    }

    readonly property var centeredWidgetsList: getCenteredWidgetsList()
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
        if ((Config.options.lock.centerAlignment || "vertical") === "horizontal") {
            let spacing = Config.options.lock.centerSpacing || 20;
            let totalWidth = centeredWidgetCount * (implicitWidth + spacing) - spacing;
            let myX = centeredWidgetIndex * (implicitWidth + spacing);
            return myX - (totalWidth - implicitWidth) / 2;
        }
        return 0;
    }

    readonly property real centeredOffsetY: {
        if (centeredWidgetCount <= 1) return 0;
        if ((Config.options.lock.centerAlignment || "vertical") === "vertical") {
            let spacing = Config.options.lock.centerSpacing || 20;
            let totalHeight = centeredWidgetCount * (implicitHeight + spacing) - spacing;
            let myY = centeredWidgetIndex * (implicitHeight + spacing);
            return myY - (totalHeight - implicitHeight) / 2;
        }
        return 0;
    }

    readonly property real centeringX: (screenWidth - implicitWidth) / 2 + centeredOffsetX
    readonly property real centeringY: (screenHeight - implicitHeight) / 2 + centeredOffsetY

    onForceCenterChanged: {
        if (forceCenter) {
            root.animDuration = 700;
            lockAnimResetTimer.restart();
        }
    }
    Timer {
        id: lockAnimResetTimer
        interval: 750
        repeat: false
        onTriggered: { root.animDuration = Appearance.animation.elementMove.duration; }
    }

    property real calculatedX: 0
    property real calculatedY: 0
    property real targetX: isPreview ? 0 : (forceCenter ? centeringX : ((placementStrategy === "free" || placementStrategy === "draggable") ? Math.max(0, Math.min(widgetInstance !== null ? widgetInstance.x : (configEntry ? configEntry.x : 0), scaledScreenWidth - width)) : calculatedX))
    property real targetY: isPreview ? 0 : (forceCenter ? centeringY : ((placementStrategy === "free" || placementStrategy === "draggable") ? Math.max(0, Math.min(widgetInstance !== null ? widgetInstance.y : (configEntry ? configEntry.y : 0), scaledScreenHeight - height)) : calculatedY))

    Binding {
        target: root
        property: "x"
        value: root.targetX
        when: !root.drag.active && !root.isPreview
    }
    Binding {
        target: root
        property: "y"
        value: root.targetY
        when: !root.drag.active && !root.isPreview
    }

    visible: opacity > 0
    opacity: {
        if (lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    scale: ((draggable && containsPress) ? 1.05 : 1.0) * (Config.options.background.widgets.widgetsScale ?? 1.0)
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    function applyGridAndSnapX(targetXVal) {
        if (Config.options.background.widgets.enableGrid ?? false) {
            targetXVal = Math.round(targetXVal / 10) * 10;
        }
        if (Config.options.background.widgets.enableSnap ?? false) {
            let snapThreshold = 15;
            if (typeof widgetListModel !== "undefined") {
                for (let i = 0; i < widgetListModel.count; i++) {
                    let w = widgetListModel.get(i);
                    if (widgetInstance && w.instanceId === widgetInstance.id) continue;
                    if (Math.abs(targetXVal - w.widgetX) < snapThreshold) {
                        targetXVal = w.widgetX;
                        break;
                    }
                }
            }
        }
        return targetXVal;
    }

    function applyGridAndSnapY(targetYVal) {
        if (Config.options.background.widgets.enableGrid ?? false) {
            targetYVal = Math.round(targetYVal / 10) * 10;
        }
        if (Config.options.background.widgets.enableSnap ?? false) {
            let snapThreshold = 15;
            if (typeof widgetListModel !== "undefined") {
                for (let i = 0; i < widgetListModel.count; i++) {
                    let w = widgetListModel.get(i);
                    if (widgetInstance && w.instanceId === widgetInstance.id) continue;
                    if (Math.abs(targetYVal - w.widgetY) < snapThreshold) {
                        targetYVal = w.widgetY;
                        break;
                    }
                }
            }
        }
        return targetYVal;
    }

    draggable: !isPreview && !(Config.options.background.widgets.lockWidgetPositions ?? false) && (placementStrategy === "free" || placementStrategy === "draggable")
    animateXPos: !drag.active
    animateYPos: !drag.active
    onXChanged: {
        if (drag.active) {
            let clamped = Math.max(0, Math.min(x, scaledScreenWidth - width));
            let finalX = applyGridAndSnapX(clamped);
            if (x !== finalX) x = finalX;
            if (widgetInstance === null && configEntry) configEntry.x = finalX;
        }
    }
    onYChanged: {
        if (drag.active) {
            let clamped = Math.max(0, Math.min(y, scaledScreenHeight - height));
            let finalY = applyGridAndSnapY(clamped);
            if (y !== finalY) y = finalY;
            if (widgetInstance === null && configEntry) configEntry.y = finalY;
        }
    }
    Connections {
        target: root.drag
        function onActiveChanged() {
            if (typeof bgRoot !== 'undefined') {
                bgRoot.anyWidgetIsDragging = root.drag.active;
            }
        }
    }
    onReleased: {
        if (isPreview) return;
        let finalX = applyGridAndSnapX(root.x);
        let finalY = applyGridAndSnapY(root.y);
        root.x = finalX;
        root.y = finalY;
        if (widgetInstance !== null) {
            Config.updateWidgetPosition(widgetInstance.id, finalX, finalY);
        } else if (configEntry) {
            configEntry.x = finalX;
            configEntry.y = finalY;
        }
    }

    property bool needsColText: false
    property color dominantColor: Appearance.colors.colPrimary
    property bool dominantColorIsDark: dominantColor.hslLightness < 0.5
    property color colText: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colPrimary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }
    property color colTextSecondary: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
        const adaptiveColor = ColorUtils.colorWithLightness(Appearance.colors.colSecondary, (dominantColorIsDark ? 0.8 : 0.12))
        return onNormalBackground ? Appearance.colors.colOnLayer0 : adaptiveColor;
    }
    property color colTextTertiary: {
        const onNormalBackground = (GlobalStates.screenLocked && Config.options.lock.blur.enable)
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

