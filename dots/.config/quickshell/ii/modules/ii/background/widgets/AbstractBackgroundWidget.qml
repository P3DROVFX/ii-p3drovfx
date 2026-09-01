import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets
import "WidgetDragMath.js" as WidgetDragMath

AbstractWidget {
    id: root

    antialiasing: true
    smooth: true

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
        if (backgroundScope && backgroundScope.widgetSyncVersion !== undefined) {
            backgroundScope.widgetSyncVersion; // dependency to force re-evaluation
        }
        return getCenteredWidgetsList() ?? [];
    }
    readonly property int centeredWidgetCount: (centeredWidgetsList ?? []).length
    readonly property int centeredWidgetIndex: {
        if (!widgetInstance) return 0;
        for (let i = 0; i < centeredWidgetsList.length; i++) {
            if (centeredWidgetsList[i].instanceId === widgetInstance.id) return i;
        }
        return 0;
    }

    readonly property real effectiveScale: Math.max(0.001, root.scale)

    // ── Supersampling factor ─────────────────────────────────────────────────
    // Item.scale stretches content that has already been rasterised, so anything
    // that produces its own bitmap at its own item size — a Canvas, an FBO
    // behind layer.enabled — comes out jagged once a widget is scaled up.
    // Wrap that content in `Supersampled { factor: root.renderScale }` (or feed
    // this to layer.textureSize) and it rasterises at the size it is really
    // shown at instead. Below 1 there is nothing to gain; above 3 the memory
    // stops paying for itself.
    // Deliberately the *settled* scale — the persisted value, not the live one.
    // Entry, drag lift, the lock animation and the resize gesture all ride on
    // `scale`, and re-rasterising every Canvas on the way through a transient
    // would be pure waste. The widget follows the grip at whatever sharpness it
    // already had and re-rasterises once, when the gesture commits.
    readonly property real renderScale: Math.max(1, Math.min(3,
        _persistedInstanceScale * (Config.options.background.widgets.widgetsScale ?? 1.0)))
    readonly property real visualWidth: width * effectiveScale
    readonly property real visualHeight: height * effectiveScale
    readonly property real visualLeftOffset: width * (1.0 - effectiveScale) / 2.0
    readonly property real visualRightOffset: width * (1.0 + effectiveScale) / 2.0
    readonly property real visualTopOffset: height * (1.0 - effectiveScale) / 2.0
    readonly property real visualBottomOffset: height * (1.0 + effectiveScale) / 2.0

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
                let w = (wSize && wSize.width > 0) ? (wSize.width * (wSize.scale || 1.0)) : root.visualWidth;
                widths.push(w);
                totalWidth += w;
            }
            totalWidth += (centeredWidgetCount - 1) * spacing;
            // Position of this widget within the group
            let myX = 0;
            for (let i = 0; i < centeredWidgetIndex; i++) {
                myX += widths[i] + spacing;
            }
            let result = myX - (totalWidth - root.visualWidth) / 2;
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
                let h = (wSize && wSize.height > 0) ? (wSize.height * (wSize.scale || 1.0)) : root.visualHeight;
                heights.push(h);
                totalHeight += h;
            }
            totalHeight += (centeredWidgetCount - 1) * spacing;
            // Position of this widget within the group
            let myY = 0;
            for (let i = 0; i < centeredWidgetIndex; i++) {
                myY += heights[i] + spacing;
            }
            return myY - (totalHeight - root.visualHeight) / 2;
        }
        return 0;
    }

    readonly property real centeringX: (screenWidth - width) / 2 + centeredOffsetX
    readonly property real centeringY: (screenHeight - height) / 2 + centeredOffsetY

    // Register own size in the shared map whenever width/height/scale changes
    function _registerOwnSize() {
        if (!widgetInstance) return;
        let id = widgetInstance.id;
        if (!id || width <= 0 || height <= 0) return;
        // Mutate in-place to preserve the shared reference across all widget instances
        root.widgetSizes[id] = {
            "width": width,
            "height": height,
            "scale": root.scale
        };
        // Bump the version counter on widgetStateManager to trigger binding re-evaluation
        if (typeof backgroundScope !== 'undefined' && backgroundScope.widgetStateManager) {
            backgroundScope.widgetStateManager.widgetSizesVersion++;
        }
    }
    onWidthChanged: _registerOwnSize()
    onHeightChanged: _registerOwnSize()
    onScaleChanged: _registerOwnSize()
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

    // ── Entry / exit ─────────────────────────────────────────────────────────
    // A widget used to be born at (0,0) with full opacity and then slide across
    // the whole screen to its spot, because the position Behavior was already
    // armed for the very first assignment. It now lands on its spot with the
    // Behavior still disabled and grows in from there.
    //
    // `exiting` is set by WidgetStateManager one animation before the model
    // entry is dropped, which is the only reason there is anything left on
    // screen to animate out.
    property bool exiting: false
    property bool entryDone: isPreview
    property real entryProgress: isPreview ? 1 : 0
    Behavior on entryProgress {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(root)
    }
    readonly property real lifecycleOpacity: exiting ? 0 : entryProgress
    // 0.92 → 1 on the way in, 0.94 on the way out: enough to read as arriving
    // and leaving without turning into a bounce.
    readonly property real lifecycleScale: exiting ? 0.94 : (0.92 + 0.08 * entryProgress)

    Timer {
        id: entryTimer
        interval: Math.max(1, root.staggerDelay)
        running: !root.isPreview
        repeat: false
        onTriggered: {
            root.entryDone = true;
            root.entryProgress = 1;
        }
    }
    property bool _pendingPosition: false
    property real targetX: isPreview ? 0 : (forceCenter ? centeringX : ((placementStrategy === "free" || placementStrategy === "draggable") ? WidgetDragMath.clamp(widgetInstance !== null ? widgetInstance.x : (configEntry ? configEntry.x : 0), dragMinimumX(), dragMaximumX()) : calculatedX))
    property real targetY: isPreview ? 0 : (forceCenter ? centeringY : ((placementStrategy === "free" || placementStrategy === "draggable") ? WidgetDragMath.clamp(widgetInstance !== null ? widgetInstance.y : (configEntry ? configEntry.y : 0), dragMinimumY(), dragMaximumY()) : calculatedY))
    property bool isDraggingOrSettling: false

    // Pointer coordinates and rendered coordinates are intentionally separate.
    // MouseArea.drag must not write root.x/y because snap/grid also write them.
    property bool _pointerGestureReady: false
    property bool _dragMovementActive: false
    property real _pressCanvasX: 0
    property real _pressCanvasY: 0
    property real _dragOriginX: 0
    property real _dragOriginY: 0
    property real _rawDragX: 0
    property real _rawDragY: 0

    // ── Snap hysteresis state ─────────────────────────────────────────────────
    // This is a Schmitt trigger: acquire close to a guide, release farther away.
    readonly property int _snapEnter: 18
    readonly property int _snapExit: 32
    readonly property int _snapOrthogonalRange: 600
    property bool _snapLockX: false
    property real _snapLockXTarget: 0
    property real _snapGuideX: -1
    property bool _snapLockY: false
    property real _snapLockYTarget: 0
    property real _snapGuideY: -1

    // Ctrl held during a drag bypasses grid and snap for precise placement.
    // Tracked per pointer event because modifiers may change mid-gesture.
    property bool _ctrlHeld: false

    // ── Grid anchor state ─────────────────────────────────────────────────────
    // Grid cells are 10px wide. The anchor stores the raw pointer position at the
    // time of the last cell commit. A new cell is committed only when raw has
    // moved >= _gridStep from the anchor. The anchor then updates to rawX so the
    // NEXT jump again requires a full _gridStep of mouse movement.
    //
    // Why this beats distance-from-cell-centre hysteresis:
    //   After each cell jump the "current cell" changes. If mouse jitters ±6px
    //   around the jump boundary, the cell alternates because the new cell's
    //   hysteresis zone is immediately triggered. With anchor tracking the
    //   required movement is ALWAYS relative to the raw position — stable.
    readonly property int _gridStep: {
        const canvas = findCanvas(root.parent);
        return Math.max(1, canvas ? canvas.alignmentGridStep : 10);
    }
    property real _gridAnchorX: 0   // raw x at last grid commit
    property real _gridAnchorY: 0   // raw y at last grid commit
    property real _lastGridX: 0     // last committed grid cell x
    property real _lastGridY: 0     // last committed grid cell y

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
            root.animateXPos = !root.isDragging;
            root.animateYPos = !root.isDragging;
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

    readonly property bool isDragging: _dragMovementActive
    onIsDraggingChanged: {
        let canvas = findCanvas(root.parent);
        if (canvas) {
            canvas.draggingActive = isDragging;
        }
        if (!isDragging) {
            if (canvas) {
                canvas.snapLineX = -1;
                canvas.snapLineY = -1;
            }
        }
    }

    function setCtrlBypass(ctrlNow) {
        if (ctrlNow === _ctrlHeld)
            return;
        _ctrlHeld = ctrlNow;
        if (ctrlNow) {
            // Entering free placement: drop any active snap locks and guides.
            _snapLockX = false;
            _snapLockY = false;
            _snapGuideX = -1;
            _snapGuideY = -1;
        } else {
            // Re-anchor the grid accumulator at the current raw position so
            // resuming the grid does not fling the widget across several cells.
            _gridAnchorX = _rawDragX;
            _gridAnchorY = _rawDragY;
            _lastGridX = WidgetDragMath.clamp(Math.round(_rawDragX / _gridStep) * _gridStep, dragMinimumX(), gridMaximumX());
            _lastGridY = WidgetDragMath.clamp(Math.round(_rawDragY / _gridStep) * _gridStep, dragMinimumY(), gridMaximumY());
        }
    }

    // ── Android-style corner scale handle ────────────────────────────────────
    // Dragging the bottom-right grip resizes a widget from its centre. Widgets
    // whose config section declares `widgetSize` follow that same value their
    // settings slider edits (implicit-size growth with x/y compensated); every
    // other widget falls back to a per-instance multiplier persisted on the
    // activeWidgets entry and applied as a visual Item scale around the centre.
    readonly property bool _positionsLocked: Config.options.background.widgets.lockWidgetPositions ?? false
    readonly property var _scaleSection: Config.options.background.widgets[configEntryName] ?? null
    readonly property bool _scaleHandleAvailable: !isPreview && draggable && !_positionsLocked && widgetInstance !== null
    // Path selection is consumer-based, not declaration-based: sections like
    // clock_nothing declare `widgetSize` while their layout ignores it, and
    // writing it there changes nothing (the widget "snaps back"). Only widgets
    // whose contentScale actually derives from the key follow the slider path;
    // everyone else uses the per-instance Item scale.
    readonly property var _widgetSizeConsumers: ({
        "android_search_bar": true, "at_a_glance": true,
        "circle_pointer_clock": true, "circular_media": true,
        "clock_expressive_card": true, "clock_flex": true,
        "clock_hori": true, "compact_media": true, "concentric_clock": true,
        "grid_card_clock": true, "media_cd": true, "month_clock": true,
        "photo_1x1": true, "resource_cpu_pill": true, "resource_disk_pill": true,
        "resource_fill_cards": true, "resource_nothing_cpu": true,
        "resource_nothing_disk": true, "resource_nothing_ram": true,
        "resource_ram_pill": true, "scallop_dot_clock": true,
        "scallop_number_clock": true, "search_pill": true,
        "triple_ring_clock": true, "wearos_arc_clock": true
    })
    readonly property bool _usesWidgetSizeKey: _scaleSection !== null && _scaleSection.widgetSize !== undefined && _widgetSizeConsumers[configEntryName] === true
    // >0 only while a resize gesture runs on the Item.scale path. It is what
    // makes the widget itself follow the grip instead of only an outline —
    // and it deliberately never touches the config, so the pointer never
    // drives a persisted write. The commit happens once, on release.
    property real _liveScaleOverride: 0
    readonly property real _effectiveInstanceScale: _liveScaleOverride > 0 ? _liveScaleOverride : _persistedInstanceScale
    // Authoritative source is the config list, not the ListModel role: roles
    // freeze at first append, so models created before `scale` existed read
    // back undefined and visually revert the widget on the next resync.
    readonly property real _persistedInstanceScale: {
        const id = widgetInstance !== null ? widgetInstance.id : "";
        const list = Config.options.background.activeWidgets || [];
        let result = 1.0;
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === id) {
                result = list[i].scale ?? 1.0;
                break;
            }
        }
        return result;
    }


    // ── Resize gesture ───────────────────────────────────────────────────────
    // The widget resizes live under the grip, but nothing is *persisted* until
    // release: the Item.scale path rides `_liveScaleOverride`, and only
    // `commitResizeScale()` ever writes. That keeps the pointer from driving a
    // config write per frame while still showing you the real widget rather
    // than an outline standing in for it.
    //
    // Uniform by design: widgets are drawn for one aspect ratio, so the grip
    // carries a single factor and never stretches one axis on its own.
    property bool _resizeActive: false
    property real _resizeStartScale: 1 // factor, not percent
    property real _resizeStartDist: 1
    property bool _resizeUsesGlobal: false
    property point _resizeStartGlobal: Qt.point(0, 0)  // screen-space pointer at press
    property point _resizeCentreGlobal: Qt.point(0, 0) // screen-space widget centre at press
    property real _resizeMinScale: 0.5
    property real _resizeMaxScale: 2
    property real _resizeStartX: 0
    property real _resizeStartY: 0
    property real _resizeStartW: 0
    property real _resizeStartH: 0
    property bool _resizeGestureMoved: false
    property bool _resizeFreeStep: false // Shift: skip the 5% quantisation

    // >0 only while a gesture runs. Drives the ghost and the readout.
    property real _resizePreviewScale: 0
    readonly property bool resizePreviewActive: _resizePreviewScale > 0
    readonly property int resizePreviewPercent: Math.round(_resizePreviewScale * 100)

    readonly property real _resizeStep: 0.05
    readonly property real _resizeDetent: 0.03 // magnetic pull back to 100%

    function _currentScaleFactor() {
        if (_usesWidgetSizeKey)
            return (_scaleSection !== null ? (_scaleSection.widgetSize ?? 100) : 100) / 100;
        return _persistedInstanceScale;
    }

    function _quantiseScale(raw) {
        const v = WidgetDragMath.clamp(raw, _resizeMinScale, _resizeMaxScale);
        if (_resizeFreeStep)
            return Math.round(v * 100) / 100;
        if (Math.abs(v - 1) <= _resizeDetent)
            return 1;
        return WidgetDragMath.clamp(Math.round(v / _resizeStep) * _resizeStep, _resizeMinScale, _resizeMaxScale);
    }

    function beginResizeGesture(mouse) {
        const canvas = findCanvas(root.parent);
        const frame = canvas ?? root;
        const p = resizeHandle.mapToItem(frame, mouse.x, mouse.y);
        const centre = frame === root ? Qt.point(width / 2, height / 2) : root.mapToItem(frame, width / 2, height / 2);
        // Measure the pointer against the widget centre in SCREEN space: both
        // are frozen at press (the physical centre is invariant under the
        // centre-origin scale), so no live geometry can feed back into the
        // ratio. The centre's screen offset comes from the press event itself,
        // which keeps this multi-monitor safe.
        const hasGlobal = mouse.globalPosition !== undefined;
        _resizeUsesGlobal = hasGlobal;
        if (hasGlobal) {
            const gp = mouse.globalPosition;
            _resizeStartGlobal = Qt.point(gp.x, gp.y);
            _resizeCentreGlobal = Qt.point(centre.x + (gp.x - p.x), centre.y + (gp.y - p.y));
        } else {
            _resizeStartGlobal = Qt.point(p.x, p.y);
            _resizeCentreGlobal = Qt.point(centre.x, centre.y);
        }
        _resizeStartDist = Math.max(1, Math.hypot(p.x - centre.x, p.y - centre.y));
        _resizeStartScale = _currentScaleFactor();
        _resizeMinScale = 0.5;
        if (_usesWidgetSizeKey) {
            // Never let the widget outgrow its monitor.
            const maxByWidth = (scaledScreenWidth / Math.max(1, width)) * _resizeStartScale;
            const maxByHeight = (scaledScreenHeight / Math.max(1, height)) * _resizeStartScale;
            _resizeMaxScale = Math.max(0.5, Math.min(2, maxByWidth, maxByHeight));
        } else {
            _resizeMaxScale = 2;
        }
        _resizeStartX = x;
        _resizeStartY = y;
        _resizeStartW = width;
        _resizeStartH = height;
        _resizeActive = true;
        _resizeGestureMoved = false;
        _resizeFreeStep = false;
        _resizePreviewScale = _resizeStartScale;
        isDraggingOrSettling = true;
        settleTimer.stop();
        staggerTimer.stop();
        _pendingPosition = false;
    }

    function updateResizeGesture(mouse) {
        if (!_resizeActive)
            return;
        _resizeGestureMoved = true;
        _resizeFreeStep = Boolean(mouse.modifiers & Qt.ShiftModifier);
        let dist;
        if (_resizeUsesGlobal && mouse.globalPosition !== undefined) {
            const gp = mouse.globalPosition;
            dist = Math.hypot(gp.x - _resizeCentreGlobal.x, gp.y - _resizeCentreGlobal.y);
        } else {
            const canvas = findCanvas(root.parent);
            const frame = canvas ?? root;
            const p = resizeHandle.mapToItem(frame, mouse.x, mouse.y);
            dist = Math.hypot(p.x - _resizeCentreGlobal.x, p.y - _resizeCentreGlobal.y);
        }
        dist = Math.max(1, dist);
        _resizePreviewScale = _quantiseScale(_resizeStartScale * (dist / _resizeStartDist));
        applyLiveResize();
    }

    // Live, but visual only. `widgetSize` is the widget's own layout input so
    // there is no way to preview that path without writing it; the Item.scale
    // path has an override precisely so it does not have to.
    function applyLiveResize() {
        if (_usesWidgetSizeKey) {
            if (_scaleSection === null || _scaleSection.widgetSize === undefined)
                return;
            _scaleSection.widgetSize = Math.round(_resizePreviewScale * 100);
            // Keep the centre pinned while the implicit size changes.
            x = WidgetDragMath.clamp(_resizeStartX - (width - _resizeStartW) / 2, dragMinimumX(), dragMaximumX());
            y = WidgetDragMath.clamp(_resizeStartY - (height - _resizeStartH) / 2, dragMinimumY(), dragMaximumY());
        } else {
            _liveScaleOverride = _resizePreviewScale;
        }
    }

    // Single commit point for both the grip release and the double-click reset.
    function commitResizeScale(factor) {
        const target = WidgetDragMath.clamp(factor, 0.5, 2);
        if (_usesWidgetSizeKey) {
            if (_scaleSection === null || _scaleSection.widgetSize === undefined)
                return;
            const widthBefore = width;
            const heightBefore = height;
            _scaleSection.widgetSize = Math.round(target * 100);
            // Keep the centre where the user left it while the box changes.
            x = WidgetDragMath.clamp(x - (width - widthBefore) / 2, dragMinimumX(), dragMaximumX());
            y = WidgetDragMath.clamp(y - (height - heightBefore) / 2, dragMinimumY(), dragMaximumY());
        } else {
            if (isPreview || widgetInstance === null)
                return;
            const rounded = Math.round(target * 100) / 100;
            Config.updateWidgetScale(widgetInstance.id, rounded);
            // Write the role directly too, so the scale binding re-evaluates
            // even if the config resync hiccups.
            if ((widgetInstance.scale ?? -1) !== rounded)
                widgetInstance.scale = rounded;
            x = WidgetDragMath.clamp(x, dragMinimumX(), dragMaximumX());
            y = WidgetDragMath.clamp(y, dragMinimumY(), dragMaximumY());
        }
        if (!isPreview) {
            if (widgetInstance !== null)
                Config.updateWidgetPosition(widgetInstance.id, x, y);
            else if (configEntry) {
                configEntry.x = x;
                configEntry.y = y;
            }
        }
    }

    function resetScaleFromHandle() {
        _resizeActive = false;
        _resizePreviewScale = 0;
        commitResizeScale(1.0);
        // Cleared only after the commit, so the scale binding never falls back
        // to the stale pre-resize value for a frame.
        _liveScaleOverride = 0;
        isDraggingOrSettling = false;
    }

    function endResizeGesture() {
        if (!_resizeActive)
            return;
        _resizeActive = false;
        // A click without pointer travel never entered updateResizeGesture, so
        // there is nothing to commit — persisting the untouched preview would
        // just rewrite the same value and fight the double-click reset.
        if (_resizeGestureMoved && _resizePreviewScale > 0)
            commitResizeScale(_resizePreviewScale);
        _resizePreviewScale = 0;
        _liveScaleOverride = 0;
        settleTimer.restart();
    }

    function beginPointerGesture(mouse) {
        if (!draggable)
            return;

        const canvas = findCanvas(root.parent);
        if (!canvas)
            return;

        settleTimer.stop();
        staggerTimer.stop();
        _pendingPosition = false;

        const pointer = root.mapToItem(canvas, mouse.x, mouse.y);
        _pointerGestureReady = true;
        setCtrlBypass(Boolean(mouse.modifiers & Qt.ControlModifier));
        _dragMovementActive = false;
        isDraggingOrSettling = true;
        _pressCanvasX = pointer.x;
        _pressCanvasY = pointer.y;
        _dragOriginX = root.x;
        _dragOriginY = root.y;
        _rawDragX = root.x;
        _rawDragY = root.y;

        _snapLockX = false;
        _snapLockY = false;
        _snapGuideX = -1;
        _snapGuideY = -1;

        _gridAnchorX = root.x;
        _gridAnchorY = root.y;
        _lastGridX = WidgetDragMath.clamp(Math.round(root.x / _gridStep) * _gridStep, dragMinimumX(), gridMaximumX());
        _lastGridY = WidgetDragMath.clamp(Math.round(root.y / _gridStep) * _gridStep, dragMinimumY(), gridMaximumY());
    }

    function updatePointerGesture(mouse) {
        if (!_pointerGestureReady || !pressed || !draggable)
            return;

        const canvas = findCanvas(root.parent);
        if (!canvas)
            return;

        const pointer = root.mapToItem(canvas, mouse.x, mouse.y);
        const deltaX = pointer.x - _pressCanvasX;
        const deltaY = pointer.y - _pressCanvasY;

        if (!_dragMovementActive) {
            const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);
            if (distance < root.drag.threshold)
                return;
            _dragMovementActive = true;
        }

        _rawDragX = WidgetDragMath.clamp(_dragOriginX + deltaX, dragMinimumX(), dragMaximumX());
        _rawDragY = WidgetDragMath.clamp(_dragOriginY + deltaY, dragMinimumY(), dragMaximumY());
        setCtrlBypass(Boolean(mouse.modifiers & Qt.ControlModifier));
        root.x = applyGridAndSnapX(_rawDragX, _rawDragY);
        root.y = applyGridAndSnapY(_rawDragY, _rawDragX);
    }

    onPressed: mouse => beginPointerGesture(mouse)
    onPositionChanged: mouse => updatePointerGesture(mouse)

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
    readonly property real lockOpacity: {
        if (lockBehavior === "lockOnly") return GlobalStates.lockScreenCentered ? 1 : 0;
        if (GlobalStates.lockScreenCentered && !visibleWhenLocked) return 0;
        return 1;
    }
    opacity: lockOpacity * lifecycleOpacity
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    readonly property real lockScaleFactor: lockBehavior === "center" ? 1.0 : (GlobalStates.lockAnimationActive ? 0.85 : 1.0)
    // Lift while dragging: the widget rises a little off the wallpaper, which is
    // the only feedback that the grab took.
    property real dragLift: isDragging ? 1.03 : 1.0
    Behavior on dragLift {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(root)
    }
    scale: _effectiveInstanceScale * (Config.options.background.widgets.widgetsScale ?? 1.0)
        * lockScaleFactor * lifecycleScale * dragLift
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

    function dragMinimumX() {
        return -visualLeftOffset;
    }

    function dragMaximumX() {
        return Math.max(dragMinimumX(), scaledScreenWidth - visualRightOffset);
    }

    function dragMinimumY() {
        return -visualTopOffset;
    }

    function dragMaximumY() {
        return Math.max(dragMinimumY(), scaledScreenHeight - visualBottomOffset);
    }

    function gridMaximumX() {
        const minX = dragMinimumX();
        const maxX = dragMaximumX();
        return minX + Math.floor((maxX - minX) / _gridStep) * _gridStep;
    }

    function gridMaximumY() {
        const minY = dragMinimumY();
        const maxY = dragMaximumY();
        return minY + Math.floor((maxY - minY) / _gridStep) * _gridStep;
    }

    function advanceGridX(rawX) {
        const state = WidgetDragMath.advanceGrid(rawX, _gridAnchorX, _lastGridX, _gridStep, dragMinimumX(), gridMaximumX());
        _gridAnchorX = state.anchor;
        _lastGridX = state.value;
        return _lastGridX;
    }

    function advanceGridY(rawY) {
        const state = WidgetDragMath.advanceGrid(rawY, _gridAnchorY, _lastGridY, _gridStep, dragMinimumY(), gridMaximumY());
        _gridAnchorY = state.anchor;
        _lastGridY = state.value;
        return _lastGridY;
    }

    function snapCandidateX(rawX, rawY) {
        const candidates = [];

        if (widgetListModel) {
            const myCenterX = rawX + root.width / 2;
            const myCenterY = rawY + root.height / 2;

            for (let i = 0; i < widgetListModel.count; i++) {
                const widget = widgetListModel.get(i);
                if (widgetInstance && widget.instanceId === widgetInstance.id)
                    continue;

                const widgetId = widget.instanceId || widget.id;
                let otherWidth = root.width;
                let otherHeight = root.height;
                let otherScale = 1.0;

                if (widgetSizes && widgetSizes[widgetId]) {
                    if (widgetSizes[widgetId].width > 0)
                        otherWidth = widgetSizes[widgetId].width;
                    if (widgetSizes[widgetId].height > 0)
                        otherHeight = widgetSizes[widgetId].height;
                    if (widgetSizes[widgetId].scale > 0)
                        otherScale = widgetSizes[widgetId].scale;
                    else if (widget.scale !== undefined && widget.scale > 0)
                        otherScale = widget.scale * (Config.options.background.widgets.widgetsScale ?? 1.0);
                } else if (widget.scale !== undefined && widget.scale > 0) {
                    otherScale = widget.scale * (Config.options.background.widgets.widgetsScale ?? 1.0);
                }

                const otherCenterY = widget.widgetY + otherHeight / 2;
                if (Math.abs(myCenterY - otherCenterY) >= _snapOrthogonalRange)
                    continue;

                const otherLeftOffset = otherWidth * (1 - otherScale) / 2;
                const otherRightOffset = otherWidth * (1 + otherScale) / 2;
                const otherVisualLeft = widget.widgetX + otherLeftOffset;
                const otherVisualRight = widget.widgetX + otherRightOffset;

                // 1. Align dragged widget's visual left with other widget's visual left
                const tLeftToLeft = otherVisualLeft - root.visualLeftOffset;
                candidates.push({
                    "target": tLeftToLeft,
                    "guide": otherVisualLeft,
                    "distance": Math.abs(rawX - tLeftToLeft)
                });

                // 2. Align dragged widget's visual right with other widget's visual right
                const tRightToRight = otherVisualRight - root.visualRightOffset;
                candidates.push({
                    "target": tRightToRight,
                    "guide": otherVisualRight,
                    "distance": Math.abs(rawX - tRightToRight)
                });

                // 3. Align dragged widget's visual left adjacent to other widget's visual right
                const tLeftToRight = otherVisualRight - root.visualLeftOffset;
                candidates.push({
                    "target": tLeftToRight,
                    "guide": otherVisualRight,
                    "distance": Math.abs(rawX - tLeftToRight)
                });

                // 4. Align dragged widget's visual right adjacent to other widget's visual left
                const tRightToLeft = otherVisualLeft - root.visualRightOffset;
                candidates.push({
                    "target": tRightToLeft,
                    "guide": otherVisualLeft,
                    "distance": Math.abs(rawX - tRightToLeft)
                });
            }
        }

        // Monitor-centre constraint: aligns the widget's visual centre with the vertical centre line.
        const screenCenterX = root.scaledScreenWidth / 2;
        const tCenter = screenCenterX - root.width / 2;
        candidates.push({
            "target": tCenter,
            "guide": screenCenterX,
            "distance": Math.abs(rawX - tCenter)
        });

        return WidgetDragMath.nearestValidCandidate(candidates, dragMinimumX(), dragMaximumX(), _snapEnter);
    }

    function snapCandidateY(rawY, rawX) {
        const candidates = [];

        if (widgetListModel) {
            const myCenterX = rawX + root.width / 2;
            const myCenterY = rawY + root.height / 2;

            for (let i = 0; i < widgetListModel.count; i++) {
                const widget = widgetListModel.get(i);
                if (widgetInstance && widget.instanceId === widgetInstance.id)
                    continue;

                const widgetId = widget.instanceId || widget.id;
                let otherWidth = root.width;
                let otherHeight = root.height;
                let otherScale = 1.0;

                if (widgetSizes && widgetSizes[widgetId]) {
                    if (widgetSizes[widgetId].width > 0)
                        otherWidth = widgetSizes[widgetId].width;
                    if (widgetSizes[widgetId].height > 0)
                        otherHeight = widgetSizes[widgetId].height;
                    if (widgetSizes[widgetId].scale > 0)
                        otherScale = widgetSizes[widgetId].scale;
                    else if (widget.scale !== undefined && widget.scale > 0)
                        otherScale = widget.scale * (Config.options.background.widgets.widgetsScale ?? 1.0);
                } else if (widget.scale !== undefined && widget.scale > 0) {
                    otherScale = widget.scale * (Config.options.background.widgets.widgetsScale ?? 1.0);
                }

                const otherCenterX = widget.widgetX + otherWidth / 2;
                if (Math.abs(myCenterX - otherCenterX) >= _snapOrthogonalRange)
                    continue;

                const otherTopOffset = otherHeight * (1 - otherScale) / 2;
                const otherBottomOffset = otherHeight * (1 + otherScale) / 2;
                const otherVisualTop = widget.widgetY + otherTopOffset;
                const otherVisualBottom = widget.widgetY + otherBottomOffset;

                // 1. Align dragged widget's visual top with other widget's visual top
                const tTopToTop = otherVisualTop - root.visualTopOffset;
                candidates.push({
                    "target": tTopToTop,
                    "guide": otherVisualTop,
                    "distance": Math.abs(rawY - tTopToTop)
                });

                // 2. Align dragged widget's visual bottom with other widget's visual bottom
                const tBottomToBottom = otherVisualBottom - root.visualBottomOffset;
                candidates.push({
                    "target": tBottomToBottom,
                    "guide": otherVisualBottom,
                    "distance": Math.abs(rawY - tBottomToBottom)
                });

                // 3. Align dragged widget's visual top adjacent to other widget's visual bottom
                const tTopToBottom = otherVisualBottom - root.visualTopOffset;
                candidates.push({
                    "target": tTopToBottom,
                    "guide": otherVisualBottom,
                    "distance": Math.abs(rawY - tTopToBottom)
                });

                // 4. Align dragged widget's visual bottom adjacent to other widget's visual top
                const tBottomToTop = otherVisualTop - root.visualBottomOffset;
                candidates.push({
                    "target": tBottomToTop,
                    "guide": otherVisualTop,
                    "distance": Math.abs(rawY - tBottomToTop)
                });
            }
        }

        // Monitor-centre constraint: aligns the widget's visual centre with the horizontal centre line.
        const screenCenterY = root.scaledScreenHeight / 2;
        const tCenter = screenCenterY - root.height / 2;
        candidates.push({
            "target": tCenter,
            "guide": screenCenterY,
            "distance": Math.abs(rawY - tCenter)
        });

        return WidgetDragMath.nearestValidCandidate(candidates, dragMinimumY(), dragMaximumY(), _snapEnter);
    }

    function applyGridAndSnapX(rawX, rawY) {
        const canvas = findCanvas(root.parent);
        if (_ctrlHeld) {
            // Precise placement: raw position only, no grid, no snap guides.
            if (canvas)
                canvas.snapLineX = -1;
            return rawX;
        }
        let targetXVal = (Config.options.background.widgets.enableGrid ?? false) ? advanceGridX(rawX) : rawX;
        let snapped = false;

        if (Config.options.background.widgets.enableSnap ?? false) {
            if (_snapLockX && WidgetDragMath.shouldHoldSnap(rawX, _snapLockXTarget, _snapExit)) {
                targetXVal = _snapLockXTarget;
                snapped = true;
            } else {
                _snapLockX = false;
                const candidate = snapCandidateX(rawX, rawY);
                if (candidate) {
                    _snapLockX = true;
                    _snapLockXTarget = candidate.target;
                    _snapGuideX = candidate.guide;
                    targetXVal = candidate.target;
                    snapped = true;
                }
            }
        } else {
            _snapLockX = false;
        }

        if (canvas)
            canvas.snapLineX = snapped && isDragging ? _snapGuideX : -1;
        return targetXVal;
    }

    function applyGridAndSnapY(rawY, rawX) {
        const canvas = findCanvas(root.parent);
        if (_ctrlHeld) {
            // Precise placement: raw position only, no grid, no snap guides.
            if (canvas)
                canvas.snapLineY = -1;
            return rawY;
        }
        let targetYVal = (Config.options.background.widgets.enableGrid ?? false) ? advanceGridY(rawY) : rawY;
        let snapped = false;

        if (Config.options.background.widgets.enableSnap ?? false) {
            if (_snapLockY && WidgetDragMath.shouldHoldSnap(rawY, _snapLockYTarget, _snapExit)) {
                targetYVal = _snapLockYTarget;
                snapped = true;
            } else {
                _snapLockY = false;
                const candidate = snapCandidateY(rawY, rawX);
                if (candidate) {
                    _snapLockY = true;
                    _snapLockYTarget = candidate.target;
                    _snapGuideY = candidate.guide;
                    targetYVal = candidate.target;
                    snapped = true;
                }
            }
        } else {
            _snapLockY = false;
        }

        if (canvas)
            canvas.snapLineY = snapped && isDragging ? _snapGuideY : -1;
        return targetYVal;
    }

    draggable: !isPreview && !(Config.options.background.widgets.lockWidgetPositions ?? false) && (placementStrategy === "free" || placementStrategy === "draggable")
    drag.target: undefined
    drag.threshold: 4
    preventStealing: true
    hoverEnabled: true
    animateXPos: entryDone && !isDragging && !isDraggingOrSettling && (visibleWhenLocked || !GlobalStates.screenLocked)
    animateYPos: entryDone && !isDragging && !isDraggingOrSettling && (visibleWhenLocked || !GlobalStates.screenLocked)

    onReleased: mouse => {
        setCtrlBypass(Boolean(mouse.modifiers & Qt.ControlModifier));
        if (!_pointerGestureReady) {
            isDraggingOrSettling = false;
            return;
        }
        if (isPreview || !_dragMovementActive) {
            _pointerGestureReady = false;
            _dragMovementActive = false;
            isDraggingOrSettling = false;
            return;
        }

        const finalX = applyGridAndSnapX(_rawDragX, _rawDragY);
        const finalY = applyGridAndSnapY(_rawDragY, _rawDragX);
        root.x = finalX;
        root.y = finalY;

        const canvas = findCanvas(root.parent);
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

        _pointerGestureReady = false;
        _dragMovementActive = false;
        console.warn("[ResizeDebug]", "moveRelease id=", widgetInstance !== null ? widgetInstance.id : "?", "model.scale=", widgetInstance !== null ? widgetInstance.scale : null, "final=", finalX, finalY);
        settleTimer.restart();
    }

    onCanceled: {
        if (_pointerGestureReady && _dragMovementActive) {
            root.x = _dragOriginX;
            root.y = _dragOriginY;
        }
        _pointerGestureReady = false;
        _dragMovementActive = false;
        isDraggingOrSettling = false;
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

    // ── Resize readout ───────────────────────────────────────────────────────
    // The widget itself is the preview now, so there is no outline — only the
    // number, which is the one thing the widget cannot tell you on its own.
    // Counter-scaled so it stays legible however far the widget has been taken.
    Rectangle {
        id: resizeReadout
        z: 98
        visible: root.resizePreviewActive
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.top
        anchors.bottomMargin: 10 / Math.max(0.001, root.effectiveScale)
        implicitWidth: readoutText.implicitWidth + 18
        implicitHeight: readoutText.implicitHeight + 8
        radius: Appearance.rounding.full
        color: Appearance.colors.colPrimary
        scale: 1 / Math.max(0.001, root.effectiveScale)
        transformOrigin: Item.Bottom

        StyledText {
            id: readoutText
            anchors.centerIn: parent
            text: root.resizePreviewPercent + "%"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnPrimary
        }
    }

    // ── Resize grip ──────────────────────────────────────────────────────────
    Item {
        id: resizeHandle
        visible: opacity > 0.001
        opacity: root._scaleHandleAvailable && !root.isDragging && (root.containsMouse || resizeDragArea.dragging) ? 1 : 0
        // Grow into place instead of only fading: at this size a pure opacity
        // ramp reads as a glitch rather than as something arriving.
        scale: opacity > 0.5 ? 1 : 0.7
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(resizeHandle)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(resizeHandle)
        }
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        // The visual grip sits inside the bounds; the hit area around it is
        // allowed to hang off the corner, which is what makes it grabbable.
        anchors.rightMargin: -6
        anchors.bottomMargin: -6
        width: 40
        height: 40
        z: 99

        Rectangle {
            id: grip
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: -3
            anchors.verticalCenterOffset: -3
            width: 22
            height: 22
            radius: 7
            color: resizeDragArea.dragging || resizeDragArea.containsMouse
                ? Appearance.colors.colPrimary
                : Appearance.colors.colSecondaryContainer

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(grip)
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: "open_in_full"
                iconSize: 13
                color: resizeDragArea.dragging || resizeDragArea.containsMouse
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colOnSecondaryContainer
            }
        }

        MouseArea {
            id: resizeDragArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor
            preventStealing: true

            onPressed: mouse => root.beginResizeGesture(mouse)
            onPositionChanged: mouse => root.updateResizeGesture(mouse)
            onReleased: root.endResizeGesture()
            onCanceled: root.endResizeGesture()
            onDoubleClicked: root.resetScaleFromHandle()
        }
    }


}
