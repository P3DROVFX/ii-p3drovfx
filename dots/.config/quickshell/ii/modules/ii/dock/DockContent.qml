import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import QtQuick.Controls
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell.Services.Mpris

import "./widgets"

Item {
    id: root

    signal togglePinRequested

    property var currentScreen: null
    property bool isPinned: false
    property bool dockRevealed: false
    property bool dockWindowVisible: true

    readonly property real dockPadding: 0
    readonly property bool isVertical: dock.isVertical
    readonly property real dotMargin: ((Config.options && Config.options.dock) ? Config.options.dock.height : 60) * 0.2 - 2
    readonly property real dotMarginV: dotMargin
    readonly property real sepThickness: Math.max(3, Math.round(Appearance.sizes.dockButtonSize * 0.06))
    readonly property real buttonSlotSize: Appearance.sizes.dockButtonSize + dotMargin * 2
    readonly property real buttonSlotHeight: Appearance.sizes.dockButtonSize + dotMarginV * 2
    readonly property real sportsWidgetSlots: 4
    readonly property real livePreviewWidgetSlots: {
        const slots = (Config.options && Config.options.dock) ? Config.options.dock.livePreviewSlots : 2
        return Math.max(2, Math.min(6, slots !== undefined ? slots : 2))
    }
    readonly property string dockPos: dock.dockEffectivePosition
    readonly property string effectiveDockStyle: {
        const st = (Config.options && Config.options.dock) ? Config.options.dock.dockStyle : ""
        if (st === "islands" || st === "dynamic_island" || st === "hug" || st === "floating")
            return st
        return (Config.options && Config.options.dock && Config.options.dock.islandsStyle) ? "islands" : "floating"
    }
    readonly property bool isDynamicIsland: effectiveDockStyle === "dynamic_island"
    readonly property bool isHug: effectiveDockStyle === "hug"
    readonly property bool isAttachedToEdge: isDynamicIsland || isHug
    readonly property bool islandsStyle: effectiveDockStyle === "islands"
    readonly property real islandSpacing: Math.max(0, (Config.options && Config.options.dock && Config.options.dock.islandSpacing !== undefined) ? Config.options.dock.islandSpacing : 8)
    readonly property real islandExtraGap: islandsStyle
        ? Math.max(0, islandSpacing - ((Config.options && Config.options.dock && Config.options.dock.iconSpacing !== undefined) ? Config.options.dock.iconSpacing : 0))
        : 0
    readonly property bool effectiveShowDividers: ((Config.options && Config.options.dock && Config.options.dock.showDividers !== undefined) ? Config.options.dock.showDividers : true) && !islandsStyle
    readonly property real dockCornerRadius: {
        const rad = (Config.options && Config.options.dock && Config.options.dock.dockRadius !== undefined) ? Config.options.dock.dockRadius : -1
        if (rad >= 0) return rad
        return isAttachedToEdge ? Appearance.rounding.windowRounding : Appearance.rounding.windowRounding + 12
    }

    readonly property real layoutVisualMainExtent: isVertical ? unifiedColumn.height : unifiedRow.width
    readonly property real animatedVisualMainExtent: layoutVisualMainExtent
    readonly property real visualWidth: isVertical ? buttonSlotSize : animatedVisualMainExtent
    readonly property real visualHeight: isVertical ? animatedVisualMainExtent : buttonSlotHeight
    readonly property real baseVisualWidth: isVertical ? buttonSlotSize : baseMetrics.totalMainExtent
    readonly property real baseVisualHeight: isVertical ? baseMetrics.totalMainExtent : buttonSlotHeight

    readonly property bool requestDockShow: (previewPopupLoader.item && previewPopupLoader.item.visible) || anyContextMenuOpen

    // PanelWindow.visible stays true while the auto-hide surface is moved off
    // screen. Expensive visual widgets must follow reveal, not only the
    // lifetime of the panel window.
    readonly property bool dockWidgetsActive: root.dockRevealed && root.dockWindowVisible

    readonly property real maxWindowPreviewHeight: 200
    readonly property real maxWindowPreviewWidth: 300
    readonly property real windowControlsHeight: 30

    property int _contextMenuOpenCount: 0
    function registerContextMenuOpen() {
        _contextMenuOpenCount++;
        _contextMenuSafetyTimer.restart();
    }
    function registerContextMenuClose() {
        _contextMenuOpenCount = Math.max(0, _contextMenuOpenCount - 1);
        _contextMenuSafetyTimer.restart();
    }
    readonly property bool anyContextMenuOpen: _contextMenuOpenCount > 0

    // Safety: if the counter stays > 0 for too long (e.g. a menu was destroyed
    // while open without properly decrementing), reset it to unstick the dock.
    Timer {
        id: _contextMenuSafetyTimer
        interval: 8000
        onTriggered: {
            if (_contextMenuOpenCount > 0) {
                _contextMenuOpenCount = 0;
            }
        }
    }
    property bool popupIsResizing: false
    property Item lastHoveredButton: null
    property Item hoveredSlot: null
    property bool buttonHovered: false
    property bool suppressHover: false
    property point hoveredButtonCenter: Qt.point(0, 0)
    property string externalDragIcon: ""
    property bool externalDragOver: false

    readonly property bool enableMagnification: (Config.options && Config.options.dock && Config.options.dock.enableMagnification !== undefined) ? Config.options.dock.enableMagnification : false
    readonly property real magnificationScale: (Config.options && Config.options.dock && Config.options.dock.magnificationScale !== undefined) ? Config.options.dock.magnificationScale : 1.5
    readonly property real magnificationInfluenceRadiusSlots: (Config.options && Config.options.dock && Config.options.dock.magnificationInfluenceRadius !== undefined) ? Config.options.dock.magnificationInfluenceRadius : 2.35
    readonly property real magnificationInfluenceRadiusPx: Math.max(
        Appearance.sizes.dockButtonSize,
        buttonSlotSize * magnificationInfluenceRadiusSlots
    )
    readonly property string magnificationCurve: (Config.options && Config.options.dock && Config.options.dock.magnificationCurve !== undefined) ? Config.options.dock.magnificationCurve : "cosine"
    readonly property string magnificationMotion: (Config.options && Config.options.dock && Config.options.dock.magnificationMotion !== undefined) ? Config.options.dock.magnificationMotion : "balanced"
    readonly property bool magnificationDynamicSpacing: (Config.options && Config.options.dock && Config.options.dock.magnificationDynamicSpacing !== undefined) ? Config.options.dock.magnificationDynamicSpacing : true
    readonly property var magnificationMotionProfile: {
        switch (magnificationMotion) {
        case "fast":
            return Appearance.animation.dockMagnificationScale.fast;
        case "smooth":
            return Appearance.animation.dockMagnificationScale.smooth;
        default:
            return Appearance.animation.dockMagnificationScale.balanced;
        }
    }
    property real magnificationPointerMain: 0
    property bool magnificationHovered: false
    readonly property bool magnificationInteractionActive: enableMagnification
        && magnificationHovered
        && !dragging
        && !islandDragging
        && !anyContextMenuOpen
        && !suppressHover
        && !externalDragOver
    readonly property real magnificationPointerContentMain: magnificationPointerMain
        + (isVertical ? scrollArea.contentY : scrollArea.contentX)
    readonly property string magnificationHoveredIslandId: {
        if (!islandsStyle || !hoveredSlot)
            return "";
        let item = hoveredSlot;
        for (let depth = 0; item && depth < 8; depth++) {
            if (typeof item._islandId !== "undefined")
                return String(item._islandId);
            item = item.parent;
        }
        return "";
    }

    // Stable metrics are based only on the unscaled layout. Animated wrapper
    // widths never feed back into the proximity field.
    readonly property var baseMetrics: {
        const items = [];
        const spacing = Config.options?.dock?.iconSpacing ?? 0;
        let cursor = 0;
        const itemCount = root.flattenedItems.length;
        for (let i = 0; i < itemCount; i++) {
            const leadingGap = root._leadingIslandGapForIndex(i);
            const bodyExtent = root._baseItemMainExtentForIndex(i);
            const mainExtent = leadingGap + bodyExtent;
            items.push({
                baseStart: cursor,
                bodyStart: cursor + leadingGap,
                baseCenter: cursor + leadingGap + bodyExtent / 2,
                baseExtent: mainExtent,
                bodyExtent: bodyExtent,
                islandId: root._islandIdForIndex(i),
                magnifiable: root._isMagnifiableItem(root.flattenedItems[i])
            });
            cursor += mainExtent;
            if (i < itemCount - 1)
                cursor += spacing;
        }
        return {
            items: items,
            totalMainExtent: Math.max(0, cursor)
        };
    }

    // The main-axis reserve keeps the PanelWindow stable while the visible
    // tray follows the animated layout width/height.
    readonly property real maximumMagnificationExtra: {
        if (!enableMagnification || baseMetrics.items.length === 0)
            return 0;

        let maximum = 0;
        const candidates = baseMetrics.items.filter(metric => metric.magnifiable);
        for (const candidate of candidates) {
            let total = 0;
            for (const metric of baseMetrics.items) {
                if (!metric.magnifiable)
                    continue;
                if (root.islandsStyle && metric.islandId !== candidate.islandId)
                    continue;
                total += root.magnificationSafetyExtraForFactor(root.magnificationFactorForDistance(Math.abs(candidate.baseCenter - metric.baseCenter)));
            }
            maximum = Math.max(maximum, total);
        }
        return Math.ceil(maximum + Appearance.sizes.elevationMargin);
    }

    readonly property real maximumMagnificationCrossExtra: enableMagnification
        ? Math.ceil(Appearance.sizes.dockButtonSize * Math.max(0, magnificationScale - 1.0))
        : 0
    readonly property bool enableAppGroups: Config.options?.dock?.enableAppGroups ?? true
    readonly property int maxGroupApps: 6
    readonly property int groupAnimationDuration: Appearance.animation.elementMoveFast.duration

    // Group changes replace Repeater delegates. Keep the old surface alive for
    // one animation cycle before committing the persistent model so apps can
    // visibly leave a group instead of disappearing synchronously.
    property bool groupMutationPending: false
    property int groupMutationRevision: 0
    property string groupMutationKind: ""
    property string groupMutationGroupId: ""
    property var groupMutationAppIds: []
    property var pendingGroupMutationGroups: []
    property var pendingGroupOrderRequest: null

    // This second state describes the delegates created by the committed
    // mutation. It is intentionally transient and never persisted.
    property int groupTransitionRevision: 0
    property string groupTransitionKind: ""
    property string groupTransitionGroupId: ""
    property var groupTransitionAppIds: []

    Timer {
        id: groupMutationTimer
        interval: root.groupAnimationDuration
        repeat: false
        onTriggered: root._commitGroupMutation()
    }

    Timer {
        id: groupTransitionClearTimer
        interval: root.groupAnimationDuration * 2
        repeat: false
        onTriggered: {
            root.groupTransitionKind = ""
            root.groupTransitionGroupId = ""
            root.groupTransitionAppIds = []
            root.groupTransitionRevision++
        }
    }

    // Islands are derived from the final flattened order. Keeping this model
    // independent from the visual surfaces preserves global drag indices.
    readonly property var islandSegments: root._buildIslandSegments(root.flattenedItems)
    readonly property var islandByItemIndex: {
        const lookup = [];
        for (const segment of root.islandSegments) {
            for (let i = segment.startIndex; i <= segment.endIndex; i++)
                lookup[i] = segment;
        }
        return lookup;
    }

    function _islandKind(item) {
        if (!item)
            return "single";
        switch (item.type) {
        case "app": return "apps";
        case "action": return "actions";
        case "appGroup": return "apps";
        case "runningAppsGroup": return "apps";
        case "file": return "file";
        case "media": return "media";
        case "weather": return "weather";
        case "sports": return "sports";
        case "livePreview": return "livePreview";
        case "phone": return "phone";
        default: return "single";
        }
    }

    function _isLauncherItem(item) {
        if (!item)
            return false;
        return item.type === "app"
            || item.type === "appGroup"
            || item.type === "runningAppsGroup";
    }

    function _canMergeIslandItems(previous, current) {
        if (!previous || !current)
            return false;
        return (root._isLauncherItem(previous) && root._isLauncherItem(current))
            || (previous.type === "action" && current.type === "action");
    }

    function _islandIdForItem(item, index) {
        if (!item)
            return "single:" + String(index);
        switch (item.type) {
        case "app":
            return "apps:" + String(item.orderKey ?? item.appId ?? index);
        case "action":
            return "actions:" + String(item.actionId ?? index);
        case "appGroup":
            return "group:" + String(item.groupId ?? index);
        case "runningAppsGroup":
            return "apps:" + String(item.orderKey ?? index);
        case "file":
            return "file:" + String(item.path ?? index);
        case "media":
            return "widget:media";
        case "weather":
            return "widget:weather";
        case "sports":
            return "widget:sports";
        case "livePreview":
            return "widget:livePreview";
        case "phone":
            return "widget:phone";
        default:
            return "single:" + String(item.orderKey ?? index);
        }
    }

    function _buildIslandSegments(items) {
        const segments = [];
        let current = null;
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            if (current && root._canMergeIslandItems(items[i - 1], item)) {
                current.endIndex = i;
                continue;
            }

            current = {
                id: root._islandIdForItem(item, i),
                kind: root._islandKind(item),
                startIndex: i,
                endIndex: i
            };
            segments.push(current);
        }
        return segments;
    }

    function _islandMetaForIndex(index) {
        return root.islandByItemIndex[index] ?? null;
    }

    function _islandIdForIndex(index) {
        return root._islandMetaForIndex(index)?.id ?? "";
    }

    function _islandStartsAt(index) {
        const meta = root._islandMetaForIndex(index);
        return !!meta && meta.startIndex === index;
    }

    function _leadingIslandGapForIndex(index) {
        return index > 0 && root._islandStartsAt(index) ? root.islandExtraGap : 0;
    }

    function _islandSegmentIndexForId(islandId) {
        for (let i = 0; i < root.islandSegments.length; i++) {
            if (String(root.islandSegments[i].id) === String(islandId))
                return i;
        }
        return -1;
    }

    function _islandBoundsForSegment(segment) {
        if (!segment)
            return null;

        const first = root.getItemWrapper(segment.startIndex);
        const last = root.getItemWrapper(segment.endIndex);
        if (!first || !last || !first.parent || !last.parent)
            return null;

        const firstMain = first.bodyMainStart;
        const lastMain = last.bodyMainEnd;
        const firstPoint = first.parent.mapToItem(
            root,
            root.isVertical ? first.x : firstMain,
            root.isVertical ? firstMain : first.y
        );
        const lastPoint = last.parent.mapToItem(
            root,
            root.isVertical ? last.x : lastMain,
            root.isVertical ? lastMain : last.y
        );
        return {
            start: root.isVertical ? firstPoint.y : firstPoint.x,
            end: root.isVertical ? lastPoint.y : lastPoint.x
        };
    }

    function _islandMainCoordinateFromScene(scenePosition) {
        if (!scenePosition)
            return 0;
        const point = root.mapFromItem(null, scenePosition.x, scenePosition.y);
        return root.isVertical ? point.y : point.x;
    }

    function _orderKeysForIslandItem(item, currentOrder) {
        if (!item)
            return [];

        if (item.type === "appGroup") {
            return (item.appIds ?? []).map(appId => root._orderKeyForAppId(currentOrder, appId));
        }

        if (item.type === "runningAppsGroup") {
            return (item.apps ?? []).map(app => root._orderKeyForAppId(currentOrder, app?.appId ?? app));
        }

        const key = String(item.orderKey ?? "");
        return key ? [key] : [];
    }

    function _orderKeysForIsland(segment, currentOrder) {
        const keys = [];
        const seen = {};
        for (let i = segment.startIndex; i <= segment.endIndex; i++) {
            const itemKeys = root._orderKeysForIslandItem(root.flattenedItems[i], currentOrder);
            for (const key of itemKeys) {
                if (!key || seen[key])
                    continue;
                seen[key] = true;
                keys.push(key);
            }
        }
        return keys;
    }

    function _resetIslandDrag() {
        root.islandDragging = false;
        root.islandDragId = "";
        root.islandDragSourceIndex = -1;
        root.islandDragTargetIndex = -1;
        root.islandDragCursorMain = 0;
    }

    function startIslandDrag(islandId, scenePosition) {
        if (!root.islandsStyle || root.dragging || root.anyContextMenuOpen)
            return false;

        const sourceIndex = root._islandSegmentIndexForId(islandId);
        if (sourceIndex < 0)
            return false;

        root.islandDragging = true;
        root.islandDragId = String(islandId);
        root.islandDragSourceIndex = sourceIndex;
        root.islandDragTargetIndex = sourceIndex;
        root.islandDragCursorMain = root._islandMainCoordinateFromScene(scenePosition);
        root._suppressTranslateAnim = true;
        root.buttonHovered = false;
        root.lastHoveredButton = null;
        return true;
    }

    function moveIslandDrag(scenePosition) {
        if (!root.islandDragging)
            return;

        root.islandDragCursorMain = root._islandMainCoordinateFromScene(scenePosition);
        let targetIndex = root.islandDragSourceIndex;
        for (let i = 0; i < root.islandSegments.length; i++) {
            if (i === root.islandDragSourceIndex)
                continue;
            const bounds = root._islandBoundsForSegment(root.islandSegments[i]);
            if (!bounds)
                continue;
            if (root.islandDragCursorMain < (bounds.start + bounds.end) / 2) {
                targetIndex = i;
                break;
            }
            targetIndex = i;
        }
        root.islandDragTargetIndex = targetIndex;
    }

    function _moveIslandBlock(sourceIndex, targetIndex) {
        if (sourceIndex < 0 || targetIndex < 0
                || sourceIndex >= root.islandSegments.length
                || targetIndex >= root.islandSegments.length
                || sourceIndex === targetIndex)
            return false;

        const currentOrder = Array.from(Config.options?.dock?.order ?? []);
        const sourceKeys = root._orderKeysForIsland(root.islandSegments[sourceIndex], currentOrder);
        const targetKeys = root._orderKeysForIsland(root.islandSegments[targetIndex], currentOrder);
        if (sourceKeys.length === 0 || targetKeys.length === 0)
            return false;

        const sourceSet = {};
        for (const key of sourceKeys)
            sourceSet[key] = true;
        const nextOrder = currentOrder.filter(key => !sourceSet[key]);

        let insertionIndex = -1;
        if (sourceIndex < targetIndex) {
            for (const key of targetKeys) {
                const index = nextOrder.indexOf(key);
                if (index >= 0)
                    insertionIndex = Math.max(insertionIndex, index + 1);
            }
        } else {
            for (const key of targetKeys) {
                const index = nextOrder.indexOf(key);
                if (index >= 0) {
                    insertionIndex = index;
                    break;
                }
            }
        }

        if (insertionIndex < 0)
            insertionIndex = nextOrder.length;
        nextOrder.splice(insertionIndex, 0, ...sourceKeys);

        if (nextOrder.length === currentOrder.length
                && nextOrder.every((entry, index) => entry === currentOrder[index]))
            return false;

        Config.options.dock.order = nextOrder;
        TaskbarApps.syncPinnedFileOrder();
        return true;
    }

    function endIslandDrag() {
        if (!root.islandDragging)
            return;

        const sourceIndex = root.islandDragSourceIndex;
        const targetIndex = root.islandDragTargetIndex;
        if (sourceIndex >= 0 && targetIndex >= 0 && sourceIndex !== targetIndex) {
            root._reordering = true;
            root._moveIslandBlock(sourceIndex, targetIndex);
        }

        root._resetIslandDrag();
        root.buttonHovered = false;
        root.lastHoveredButton = null;
        root.suppressHover = true;
        suppressHoverTimer.restart();
        Qt.callLater(function () {
            root._reordering = false;
            root._suppressTranslateAnim = false;
        });
    }

    function _isMagnifiableItem(item) {
        if (!item)
            return false;
        return item.type === "app"
            || item.type === "appGroup"
            || item.type === "file"
            || item.type === "action"
            || item.type === "phone";
    }

    function _rawItemMainExtent(item) {
        if (isVertical || !item)
            return buttonSlotSize;
        switch (item.type) {
        case "media":
        case "weather":
            return buttonSlotSize * 3;
        case "sports":
            return buttonSlotSize * sportsWidgetSlots;
        case "livePreview":
            return buttonSlotSize * livePreviewWidgetSlots;
        default:
            return buttonSlotSize;
        }
    }

    function _separatorBeforeSpaceFor(index) {
        if (!root.effectiveShowDividers || index <= 0)
            return 0;
        const item = root.flattenedItems[index];
        const previous = root.flattenedItems[index - 1];
        if (Config.options?.dock?.smartGrouping)
            return root.getItemCategory(item) !== root.getItemCategory(previous) ? Math.max(root.dotMargin, root.sepThickness * 2) : 0;
        return root.isSpecialItem(item) ? Math.max(root.dotMargin, root.sepThickness * 2) : 0;
    }

    function _separatorAfterSpaceFor(index) {
        if (!root.effectiveShowDividers || index >= root.flattenedItems.length - 1)
            return 0;
        if (Config.options?.dock?.smartGrouping)
            return 0;
        const item = root.flattenedItems[index];
        const next = root.flattenedItems[index + 1];
        return root.isSpecialItem(item) && !root.isSpecialItem(next)
            ? Math.max(root.dotMargin, root.sepThickness * 2)
            : 0;
    }

    function _baseMainExtentForIndex(index) {
        return root._leadingIslandGapForIndex(index) + root._baseItemMainExtentForIndex(index);
    }

    function _baseItemMainExtentForIndex(index) {
        const item = root.flattenedItems[index];
        return root._rawItemMainExtent(item)
            + root._separatorBeforeSpaceFor(index)
            + root._separatorAfterSpaceFor(index);
    }

    function magnificationFactorForDistance(distancePx) {
        const radius = Math.max(1, magnificationInfluenceRadiusPx);
        if (distancePx >= radius)
            return 0;
        const t = Math.max(0, Math.min(1, distancePx / radius));
        if (magnificationCurve === "gaussian") {
            const sigma = radius / 2.5;
            const cutoff = Math.exp(-(radius * radius) / (2 * sigma * sigma));
            return Math.max(0, (Math.exp(-(distancePx * distancePx) / (2 * sigma * sigma)) - cutoff) / (1 - cutoff));
        }
        return 0.5 * (1 + Math.cos(Math.PI * t));
    }

    function magnificationLayoutExtraForFactor(factor) {
        if (!magnificationDynamicSpacing)
            return 0;
        return Appearance.sizes.dockButtonSize * Math.max(0, magnificationScale - 1.0) * factor;
    }

    function magnificationSafetyExtraForFactor(factor) {
        return Appearance.sizes.dockButtonSize * Math.max(0, magnificationScale - 1.0) * factor;
    }

    function _targetMagScaleForIndex(index) {
        const metric = baseMetrics.items[index];
        if (!metric || !metric.magnifiable || !magnificationInteractionActive)
            return 1.0;
        if (root.islandsStyle && (!root.magnificationHoveredIslandId || metric.islandId !== root.magnificationHoveredIslandId))
            return 1.0;
        const factor = magnificationFactorForDistance(Math.abs(magnificationPointerContentMain - metric.baseCenter));
        return 1.0 + (magnificationScale - 1.0) * factor;
    }

    // Compatibility helper for tooltip/preview code. Main button scale is
    // owned by the delegate wrapper, so this no longer scans repeater items.
    function _getSlotMagScale(targetSlot) {
        let item = targetSlot;
        for (let depth = 0; item && depth < 6; depth++) {
            if (typeof item.dockMagnificationScale !== "undefined")
                return item.dockMagnificationScale;
            if (typeof item._magnificationScale !== "undefined")
                return item._magnificationScale;
            item = item.parent;
        }
        return 1.0;
    }

    function onButtonEntered(slotItem) {
        if (suppressHover || dragging)
            return;
        hoverGraceTimer.stop();
        hoveredSlot = slotItem;
        lastHoveredButton = slotItem;
        buttonHovered = true;
    }

    function onButtonExited(slotItem) {
        if (lastHoveredButton === slotItem || hoveredSlot === slotItem) {
            hoverGraceTimer.restart();
        }
    }

    Timer {
        id: hoverGraceTimer
        interval: 150
        onTriggered: {
            root.buttonHovered = false;
            root.hoveredSlot = null;
        }
    }

    Timer {
        id: magnificationExitTimer
        interval: Appearance.animation.dockMagnificationScale.hoverExitGrace
        onTriggered: root.magnificationHovered = false
    }

    function setMagnificationHovered(value) {
        if (value) {
            magnificationExitTimer.stop();
            root.magnificationHovered = true;
        } else {
            magnificationExitTimer.restart();
        }
    }

    function updateMagnificationPointerFrom(item, x, y) {
        if (!item)
            return;
        const targetContainer = root.isVertical ? unifiedColumn : unifiedRow;
        const mapped = item.mapToItem(targetContainer, x, y);
        const visualExtra = root.isVertical
            ? Math.max(0, root.visualHeight - root.baseVisualHeight)
            : Math.max(0, root.visualWidth - root.baseVisualWidth);
        const pointerMain = root.isVertical ? mapped.y : mapped.x;
        root.magnificationPointerMain = pointerMain - visualExtra / 2;
    }

    readonly property var activePlayer: MprisController.activePlayer
    readonly property string rawTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || ""
    readonly property bool hasRealData: activePlayer !== null && rawTitle !== ""
    property bool showMusicPlayer: hasRealData

    onHasRealDataChanged: {
        if (hasRealData) {
            switchHoldTimer.stop();
            showMusicPlayer = true;
        } else
            switchHoldTimer.restart();
    }

    Timer {
        id: suppressHoverTimer
        interval: 250
        onTriggered: root.suppressHover = false
    }
    Timer {
        id: switchHoldTimer
        interval: 2000
        onTriggered: if (!root.hasRealData)
            root.showMusicPlayer = false
    }

    function updateHoveredButtonCenter() {
        const btn = root.lastHoveredButton;
        if (!btn)
            return;
        // Mapping the live visual center includes wrapper reflow and the
        // delegate's current animated scale without duplicating transform math.
        root.hoveredButtonCenter = btn.mapToItem(null, btn.width / 2, btn.height / 2);
    }

    onLastHoveredButtonChanged: root.updateHoveredButtonCenter()
    onVisualWidthChanged: root.updateHoveredButtonCenter()
    onVisualHeightChanged: root.updateHoveredButtonCenter()

    Connections {
        target: root.lastHoveredButton
        function onXChanged() { root.updateHoveredButtonCenter(); }
        function onYChanged() { root.updateHoveredButtonCenter(); }
        function onWidthChanged() { root.updateHoveredButtonCenter(); }
        function onHeightChanged() { root.updateHoveredButtonCenter(); }
        function onScaleChanged() { root.updateHoveredButtonCenter(); }
    }

    readonly property bool showPin: Config.options?.dock?.showPinButton ?? true
    readonly property bool showOverview: Config.options?.dock?.showOverviewButton ?? true
    readonly property bool showTrash: Config.options?.dock?.showTrashButton ?? true
    readonly property bool showMedia: (Config.options?.dock?.enableMediaWidget ?? false) && root.showMusicPlayer
    readonly property bool showWeather: Config.options?.dock?.enableWeatherWidget ?? false
    readonly property bool showSports: (Config.options?.dock?.enableSportsWidget ?? true) && !root.isVertical
        && SportsService.allGames.length > 0
    readonly property bool showLivePreview: Config.options?.dock?.enableLivePreviewWidget ?? false
    readonly property bool showPhone: (Config.options?.dock?.showPhoneButton ?? true)
        && KdeConnectService.activeReachable

    // ── Drag-to-reorder state (dots-hyprland pattern, adapted for variable-width items) ──
    property bool dragging: false
    property bool _reordering: false
    property bool _suppressTranslateAnim: false
    property int dragSourceIndex: -1
    property real dragCursorX: 0
    property real dragStartCursorX: 0
    property real slotWidth: 0
    property int _dragTargetIndex: -1
    property int _groupDropTargetIndex: -1
    property bool _groupDropWillCreate: false
    property bool _groupDropBlocked: false

    // Islands are reordered as contiguous blocks of the existing dock.order.
    // This keeps item-level ordering and grouping data in one persistent model.
    property bool islandDragging: false
    property string islandDragId: ""
    property int islandDragSourceIndex: -1
    property int islandDragTargetIndex: -1
    property real islandDragCursorMain: 0

    // ── Helper: get the active Repeater instance ─────────────────────────
    function _getActiveRepeater() {
        return root.isVertical ? columnItemRepeater : itemRepeater;
    }
    function getItemWrapper(index) {
        var repeater = _getActiveRepeater();
        return repeater ? repeater.itemAt(index) : null;
    }

    // Return the layout slot without the delegate's temporary drag transform.
    // Grouping should only lock the order when the pointer is actually over
    // the target item; crossing the gap between items must still allow normal
    // reordering to resume.
    function _getUntransformedSlot(index) {
        var wrapper = getItemWrapper(index);
        if (!wrapper)
            return null;

        var parentItem = wrapper.parent;
        var mapped = parentItem
            ? parentItem.mapToItem(root, wrapper.x, wrapper.y)
            : wrapper.mapToItem(root, 0, 0);
        var start = root.isVertical ? mapped.y : mapped.x;
        var size = root.isVertical ? wrapper.height : wrapper.width;
        return {
            start: start,
            end: start + size
        };
    }

    function _isPointerOverSlot(index) {
        var slot = root._getUntransformedSlot(index);
        if (!slot)
            return false;
        return root.dragCursorX >= slot.start && root.dragCursorX <= slot.end;
    }

    // ── Helper: estimate item width in the current orientation ───────────
    function getItemWidth(index) {
        var wrapper = getItemWrapper(index);
        if (wrapper) {
            return root.isVertical ? wrapper.height : wrapper.width;
        }
        // Fallback: estimate from model data
        var entry = flattenedItems[index];
        if (!entry)
            return buttonSlotSize;
        switch (entry.type) {
        case "media":
        case "weather":
            return root.isVertical ? buttonSlotSize : buttonSlotSize * 3;
        case "sports":
            return root.isVertical ? buttonSlotSize : buttonSlotSize * root.sportsWidgetSlots;
        case "livePreview":
            return root.isVertical ? buttonSlotSize : buttonSlotSize * root.livePreviewWidgetSlots;
        default:
            return buttonSlotSize;
        }
    }

    function _orderEntryAppId(entry) {
        const key = String(entry ?? "");
        if (key.startsWith("app:"))
            return key.substring(4);
        if (key.startsWith("runningApp:"))
            return key.substring(11);
        return "";
    }

    function _appDataForId(appId) {
        return root.pinnedAppMap[appId] || root.runningAppMap[appId] || {
            appId: appId,
            pinned: true,
            toplevels: []
        };
    }

    function _makeAppGroupItem(group) {
        return {
            type: "appGroup",
            groupId: group.id,
            appIds: Array.from(group.apps),
            apps: group.apps.map(appId => root._appDataForId(appId)),
            orderKey: "group:" + group.id
        };
    }

    function isGroupDropTarget(index) {
        return root.enableAppGroups && root.dragging && root._groupDropTargetIndex === index;
    }

    function groupDropIsBlocked(index) {
        return root.isGroupDropTarget(index) && root._groupDropBlocked;
    }

    function groupDropWillCreate(index) {
        return root.isGroupDropTarget(index) && root._groupDropWillCreate && !root._groupDropBlocked;
    }

    function updateGroupDropTarget() {
        root._groupDropTargetIndex = -1;
        root._groupDropWillCreate = false;
        root._groupDropBlocked = false;

        if (!root.enableAppGroups || !root.dragging)
            return;

        const source = root.flattenedItems[root.dragSourceIndex];
        const target = root.flattenedItems[root._dragTargetIndex];
        if (!source || source.type !== "app" || !target || root.dragSourceIndex === root._dragTargetIndex)
            return;

        if (target.type === "app") {
            if (source.appId === target.appId)
                return;
            if (!root._isPointerOverSlot(root._dragTargetIndex))
                return;
            root._groupDropTargetIndex = root._dragTargetIndex;
            root._groupDropWillCreate = true;
            return;
        }

        if (target.type === "appGroup") {
            if (!root._isPointerOverSlot(root._dragTargetIndex))
                return;
            root._groupDropTargetIndex = root._dragTargetIndex;
            root._groupDropBlocked = target.appIds.length >= root.maxGroupApps
                || target.appIds.includes(source.appId);
        }
    }

    function _newAppGroupId() {
        const prefix = "group-" + Date.now().toString(36);
        let candidate = prefix;
        let suffix = 1;
        while (root.appGroupById[candidate])
            candidate = prefix + "-" + String(suffix++);
        return candidate;
    }

    function _reorderAppGroupInOrder(appIds, anchorAppId, preferredKeys) {
        const currentOrder = Array.from(Config.options?.dock?.order ?? []);
        const memberIds = {};
        for (const appId of appIds)
            memberIds[appId] = true;

        let anchorIndex = -1;
        for (let i = 0; i < currentOrder.length; i++) {
            if (root._orderEntryAppId(currentOrder[i]) === anchorAppId) {
                anchorIndex = i;
                break;
            }
        }

        let insertionIndex = currentOrder.length;
        if (anchorIndex >= 0) {
            insertionIndex = 0;
            for (let i = 0; i < anchorIndex; i++) {
                if (!memberIds[root._orderEntryAppId(currentOrder[i])])
                    insertionIndex++;
            }
        }

        const groupOrderKeys = appIds.map(appId => {
            for (const entry of currentOrder) {
                if (root._orderEntryAppId(entry) === appId)
                    return entry;
            }
            const preferred = preferredKeys?.[appId] ?? "";
            if (preferred.startsWith("app:") || preferred.startsWith("runningApp:"))
                return preferred;
            return root.runningAppMap[appId] ? "runningApp:" + appId : "app:" + appId;
        });

        const nextOrder = currentOrder.filter(entry => !memberIds[root._orderEntryAppId(entry)]);
        nextOrder.splice(insertionIndex, 0, ...groupOrderKeys);
        Config.options.dock.order = nextOrder;
        TaskbarApps.syncPinnedFileOrder();
    }

    function isGroupAppExiting(appId) {
        return root.groupMutationPending
            && (root.groupMutationKind === "create" || root.groupMutationKind === "add")
            && root.groupMutationAppIds.includes(String(appId ?? ""));
    }

    function isGroupExiting(groupId) {
        return root.groupMutationPending
            && root.groupMutationKind === "dissolve"
            && root.groupMutationGroupId === String(groupId ?? "");
    }

    function isGroupEntryTransition(groupId) {
        return root.groupTransitionGroupId === String(groupId ?? "")
            && (root.groupTransitionKind === "create" || root.groupTransitionKind === "add");
    }

    function shouldAnimateGroupAppReturn(appId) {
        return root.groupTransitionKind === "dissolve"
            && root.groupTransitionAppIds.includes(String(appId ?? ""));
    }

    function _startGroupTransition(kind, groupId, appIds) {
        root.groupTransitionKind = kind;
        root.groupTransitionGroupId = String(groupId ?? "");
        root.groupTransitionAppIds = Array.from(appIds ?? []).map(value => String(value ?? ""));
        root.groupTransitionRevision++;
        groupTransitionClearTimer.restart();
    }

    function _queueGroupMutation(nextGroups, kind, groupId, appIds, orderRequest) {
        if (root.groupMutationPending)
            return false;

        root.groupMutationPending = true;
        root.groupMutationKind = kind;
        root.groupMutationGroupId = String(groupId ?? "");
        root.groupMutationAppIds = Array.from(appIds ?? []).map(value => String(value ?? ""));
        root.pendingGroupMutationGroups = nextGroups;
        root.pendingGroupOrderRequest = orderRequest;
        root.groupMutationRevision++;
        groupMutationTimer.restart();
        return true;
    }

    function _commitGroupMutation() {
        if (!root.groupMutationPending)
            return;

        const nextGroups = root.pendingGroupMutationGroups;
        const orderRequest = root.pendingGroupOrderRequest;
        const mutationKind = root.groupMutationKind;
        const mutationGroupId = root.groupMutationGroupId;
        const mutationAppIds = root.groupMutationAppIds;

        // Set the post-commit state before changing Config so newly created
        // delegates can read it during their first evaluation.
        const transitionKind = mutationKind === "dissolve"
            ? "dissolve"
            : (mutationKind === "create" ? "create" : "add");
        root._startGroupTransition(transitionKind, mutationGroupId, mutationAppIds);

        Config.options.dock.appGroups = nextGroups;
        if (orderRequest)
            root._reorderAppGroupInOrder(orderRequest.appIds, orderRequest.anchorAppId, orderRequest.preferredKeys);
        else
            TaskbarApps.syncPinnedFileOrder();

        root.groupMutationPending = false;
        root.groupMutationKind = "";
        root.groupMutationGroupId = "";
        root.groupMutationAppIds = [];
        root.pendingGroupMutationGroups = [];
        root.pendingGroupOrderRequest = null;
        root.groupMutationRevision++;
    }

    function completeGroupDrop() {
        if (!root.enableAppGroups || root._groupDropTargetIndex < 0)
            return false;

        const source = root.flattenedItems[root.dragSourceIndex];
        const target = root.flattenedItems[root._groupDropTargetIndex];
        if (!source || source.type !== "app" || !target || root._groupDropBlocked)
            return false;

        const sourceId = source.appId;
        let groupApps = [];
        let anchorAppId = "";
        const nextGroups = root.appGroups.map(group => ({
            id: group.id,
            apps: Array.from(group.apps)
        }));

        if (target.type === "appGroup") {
            const existing = nextGroups.find(group => group.id === target.groupId);
            if (!existing || existing.apps.length >= root.maxGroupApps || existing.apps.includes(sourceId))
                return false;
            existing.apps.push(sourceId);
            groupApps = existing.apps;
            anchorAppId = existing.apps[0];
        } else if (target.type === "app") {
            const group = {
                id: root._newAppGroupId(),
                apps: [target.appId, sourceId]
            };
            nextGroups.push(group);
            groupApps = group.apps;
            anchorAppId = target.appId;
        } else {
            return false;
        }

        const preferredKeys = {};
        preferredKeys[sourceId] = source.orderKey;
        if (target.type === "app")
            preferredKeys[target.appId] = target.orderKey;
        const transitionAppIds = target.type === "appGroup"
            ? [sourceId]
            : [target.appId, sourceId];
        return root._queueGroupMutation(
            nextGroups,
            target.type === "appGroup" ? "add" : "create",
            target.type === "appGroup" ? target.groupId : nextGroups[nextGroups.length - 1].id,
            transitionAppIds,
            {
                appIds: groupApps,
                anchorAppId: anchorAppId,
                preferredKeys: preferredKeys
            }
        );
    }

    function removeAppFromGroup(groupId, appId) {
        const targetId = String(groupId ?? "").trim();
        const targetAppId = String(appId ?? "").trim();
        if (!targetId || !targetAppId)
            return false;

        const currentGroups = Config.options?.dock?.appGroups ?? [];
        const nextGroups = [];
        let removedGroup = null;
        let removed = false;

        for (const rawGroup of currentGroups) {
            if (!rawGroup)
                continue;

            const currentId = String(rawGroup.id ?? "").trim();
            const apps = Array.from(rawGroup.apps ?? []).map(value => String(value ?? "").trim()).filter(value => value !== "");
            if (currentId !== targetId) {
                nextGroups.push({ id: currentId, apps: apps });
                continue;
            }

            removedGroup = { id: currentId, apps: apps };
            const nextApps = apps.filter(value => value !== targetAppId);
            removed = nextApps.length !== apps.length;
            // Keep a one-member group after detaching an app. This makes a
            // right-click on a popup app remove only that app; the group is
            // removed explicitly by its own right-click or when its last
            // member is detached.
            if (nextApps.length >= 1)
                nextGroups.push({ id: currentId, apps: nextApps });
        }

        if (!removed)
            return false;

        if (removedGroup && removedGroup.apps.length === 1) {
            return root._queueGroupMutation(nextGroups, "dissolve", targetId, removedGroup.apps, null);
        }

        root._startGroupTransition("remove", targetId, [targetAppId]);
        Config.options.dock.appGroups = nextGroups;
        TaskbarApps.syncPinnedFileOrder();
        return true;
    }

    function removeAppGroup(groupId) {
        const targetId = String(groupId ?? "").trim();
        if (!targetId)
            return false;

        const currentGroups = Config.options?.dock?.appGroups ?? [];
        const groupToRemove = currentGroups.find(group => group && String(group.id ?? "").trim() === targetId);
        if (!groupToRemove)
            return false;

        const nextGroups = currentGroups
            .filter(group => group && String(group.id ?? "").trim() !== targetId)
            .map(group => ({
                id: String(group.id ?? "").trim(),
                apps: Array.from(group.apps ?? []).map(value => String(value ?? "").trim()).filter(value => value !== "")
            }));

        return root._queueGroupMutation(
            nextGroups,
            "dissolve",
            targetId,
            Array.from(groupToRemove.apps ?? []),
            null
        );
    }

    function _orderKeyForAppId(order, appId) {
        for (const entry of order) {
            if (root._orderEntryAppId(entry) === appId)
                return entry;
        }
        return root.runningAppMap[appId] ? "runningApp:" + appId : "app:" + appId;
    }

    function moveDockItem(sourceItem, targetItem) {
        if (!sourceItem || !targetItem || sourceItem.orderKey === targetItem.orderKey)
            return false;

        const currentOrder = Array.from(Config.options?.dock?.order ?? []);
        const sourceIsGroup = sourceItem.type === "appGroup";
        const sourceIds = sourceIsGroup ? sourceItem.appIds : [];
        const sourceKeys = sourceIsGroup
            ? sourceIds.map(appId => root._orderKeyForAppId(currentOrder, appId))
            : [sourceItem.orderKey];
        const sourceKeySet = {};
        for (const key of sourceKeys)
            sourceKeySet[key] = true;

        let targetOriginalIndex = -1;
        if (targetItem.type === "appGroup") {
            const anchorId = targetItem.appIds[0];
            targetOriginalIndex = currentOrder.findIndex(entry => root._orderEntryAppId(entry) === anchorId);
        } else if (targetItem.type === "app") {
            targetOriginalIndex = currentOrder.findIndex(entry => root._orderEntryAppId(entry) === targetItem.appId);
        } else {
            targetOriginalIndex = currentOrder.indexOf(targetItem.orderKey);
        }

        if (sourceIsGroup && targetItem.type === "appGroup"
                && sourceItem.groupId === targetItem.groupId)
            return false;

        let insertionIndex = currentOrder.length;
        if (targetOriginalIndex >= 0) {
            insertionIndex = 0;
            for (let i = 0; i < targetOriginalIndex; i++) {
                if (!sourceKeySet[currentOrder[i]])
                    insertionIndex++;
            }
        }

        const nextOrder = currentOrder.filter(entry => !sourceKeySet[entry]);
        nextOrder.splice(insertionIndex, 0, ...sourceKeys);
        if (nextOrder.length === currentOrder.length
                && nextOrder.every((entry, index) => entry === currentOrder[index]))
            return false;

        Config.options.dock.order = nextOrder;
        TaskbarApps.syncPinnedFileOrder();
        return true;
    }

    // ── Compute drag target by walking through variable-width items ──────
    function recomputeDragTarget() {
        if (!dragging) {
            _dragTargetIndex = dragSourceIndex;
            root.updateGroupDropTarget();
            return;
        }
        var delta = dragCursorX - dragStartCursorX;
        var src = dragSourceIndex;
        var count = flattenedItems.length;
        if (count <= 1 || Math.abs(delta) < 5) {
            _dragTargetIndex = src;
            root.updateGroupDropTarget();
            return;
        }
        var spacing = Config.options.dock.iconSpacing;
        var step = delta > 0 ? 1 : -1;
        var remaining = Math.abs(delta);
        var current = src;
        while (remaining > 0) {
            var next = current + step;
            if (next < 0 || next >= count)
                break;
            // Distance from current item's center to next item's center
            var curHalf = (getItemWidth(current) + spacing) / 2;
            var nextHalf = (getItemWidth(next) + spacing) / 2;
            var threshold = curHalf + nextHalf;
            if (remaining < threshold)
                break;
            remaining -= threshold;
            current = next;
        }
        _dragTargetIndex = current;
        root.updateGroupDropTarget();
        // While the cursor is inside a valid group target, keep the layout in
        // its original order. Leaving the target slot restores the calculated
        // reorder target, so moving farther continues to behave like a normal
        // dock reorder gesture.
        if (root._groupDropTargetIndex >= 0)
            _dragTargetIndex = src;
    }

    function _resetDragState() {
        dragging = false;
        dragSourceIndex = -1;
        _dragTargetIndex = -1;
        _groupDropTargetIndex = -1;
        _groupDropWillCreate = false;
        _groupDropBlocked = false;
        dragCursorX = 0;
        dragStartCursorX = 0;
    }

    function finishDrag() {
        _suppressTranslateAnim = true;
        var src = dragSourceIndex;
        var tgt = _dragTargetIndex;

        if (dragging && _groupDropTargetIndex >= 0 && !_groupDropBlocked) {
            _reordering = true;
            if (root.completeGroupDrop()) {
                root._resetDragState();
                buttonHovered = false;
                lastHoveredButton = null;
                suppressHover = true;
                suppressHoverTimer.restart();
                Qt.callLater(function () {
                    _reordering = false;
                    _suppressTranslateAnim = false;
                });
                return;
            }
        }

        if (dragging && src !== tgt) {
            _reordering = true;
            if (src >= 0 && src < flattenedItems.length && tgt >= 0 && tgt < flattenedItems.length) {
                var srcEntry = flattenedItems[src];
                var tgtEntry = flattenedItems[tgt];
                if (srcEntry && tgtEntry)
                    root.moveDockItem(srcEntry, tgtEntry);
            }
        }
        root._resetDragState();
        buttonHovered = false;
        lastHoveredButton = null;
        suppressHover = true;
        suppressHoverTimer.restart();
        Qt.callLater(function () {
            _reordering = false;
            _suppressTranslateAnim = false;
        });
    }

    function cancelDrag() {
        _suppressTranslateAnim = true;
        root._resetDragState();
        Qt.callLater(function () {
            _suppressTranslateAnim = false;
        });
    }

    function startItemDrag(delegateIndex, child, eventX, eventY) {
        _suppressTranslateAnim = true;
        dragSourceIndex = delegateIndex;
        _dragTargetIndex = delegateIndex;
        var mapped = child.mapToItem(root, eventX, eventY);
        var mappedCoord = isVertical ? mapped.y : mapped.x;
        dragStartCursorX = mappedCoord;
        dragCursorX = mappedCoord;
        // Get the dragged item's actual wrapper for slotWidth
        var wrapper = getItemWrapper(delegateIndex);
        slotWidth = (wrapper ? (isVertical ? wrapper.height : wrapper.width) : buttonSlotSize) + 2;
        _groupDropTargetIndex = -1;
        _groupDropWillCreate = false;
        _groupDropBlocked = false;
        dragging = true;
        buttonHovered = false;
        if (previewPopupLoader.item)
            previewPopupLoader.item.show = false;
        Qt.callLater(function () {
            _suppressTranslateAnim = false;
        });
    }

    function moveItemDrag(child, eventX, eventY) {
        if (!dragging)
            return;
        var mapped = child.mapToItem(root, eventX, eventY);
        dragCursorX = isVertical ? mapped.y : mapped.x;
        recomputeDragTarget();
    }

    function endItemDrag() {
        finishDrag();
    }

    function mapDragToRoot(item, x, y) {
        return item.mapToItem(root, x, y);
    }

    // ── Flattened items model ─────────────────────────────────────────────
    readonly property var pinnedAppMap: {
        var m = {};
        var allApps = TaskbarApps.apps ?? [];
        for (var i = 0; i < allApps.length; i++) {
            var a = allApps[i];
            if (a.pinned)
                m[a.appId] = a;
        }
        return m;
    }

    readonly property var runningAppMap: {
        var m = {};
        var allApps = TaskbarApps.apps ?? [];
        for (var i = 0; i < allApps.length; i++) {
            var a = allApps[i];
            if (!a.pinned && a.toplevels && a.toplevels.length > 0)
                m[a.appId] = a;
        }
        return m;
    }

    // Groups are persisted independently from dock.order. The order keeps
    // every app key, which means disabling groups can safely reveal members
    // individually without destroying the user's group definitions.
    readonly property var appGroups: {
        const rawGroups = Config.options?.dock?.appGroups ?? [];
        const groups = [];
        const seenApps = {};

        for (const rawGroup of rawGroups) {
            if (!rawGroup)
                continue;
            const groupId = String(rawGroup.id ?? "").trim();
            if (!groupId)
                continue;

            const apps = [];
            for (const rawAppId of Array.from(rawGroup.apps ?? [])) {
                const appId = String(rawAppId ?? "").trim();
                if (!appId || seenApps[appId] || apps.includes(appId))
                    continue;
                apps.push(appId);
                seenApps[appId] = true;
                if (apps.length >= root.maxGroupApps)
                    break;
            }

            if (apps.length >= 1)
                groups.push({
                    id: groupId,
                    apps: apps
                });
        }
        return groups;
    }

    readonly property var appGroupByAppId: {
        const result = {};
        for (const group of root.appGroups) {
            for (const appId of group.apps)
                result[appId] = group;
        }
        return result;
    }

    readonly property var appGroupById: {
        const result = {};
        for (const group of root.appGroups)
            result[group.id] = group;
        return result;
    }

    readonly property var pinnedFileMap: {
        var m = {};
        var files = Config.options?.dock?.pinnedFiles ?? [];
        for (var i = 0; i < files.length; i++)
            m[files[i]] = {
                path: files[i]
            };
        return m;
    }

    // Islands mode presents launchers as one continuous app surface. The
    // persisted order may contain widgets or actions between launcher keys,
    // so coalesce the derived visual list without changing dock.order. This
    // also keeps a group whose keys were appended by an older config version
    // with the other pinned/running launchers.
    function _coalesceLauncherItems(items) {
        if (!root.islandsStyle || !items || items.length < 2)
            return items;

        const launchers = [];
        let firstLauncherIndex = -1;
        for (let i = 0; i < items.length; i++) {
            if (!root._isLauncherItem(items[i]))
                continue;
            if (firstLauncherIndex < 0)
                firstLauncherIndex = i;
            launchers.push(items[i]);
        }

        if (launchers.length < 2)
            return items;

        const result = items.filter(item => !root._isLauncherItem(item));
        result.splice(firstLauncherIndex, 0, ...launchers);
        return result;
    }

    readonly property var flattenedItems: {
        var result = [];
        var order = Config.options.dock.order ?? [];
        var allApps = TaskbarApps.apps ?? [];
        var allAppIds = [];
        for (var i = 0; i < allApps.length; i++)
            allAppIds.push(allApps[i].appId);

        // Track seen orderKeys to avoid duplicates
        var seenOrderKeys = {};
        var seenGroupIds = {};

        // Pre-scan explicit running apps and apps to avoid them being swallowed by "runningApps" marker
        var explicitKeys = {};
        for (var e_i = 0; e_i < order.length; e_i++) {
            if (order[e_i].startsWith("runningApp:") || order[e_i].startsWith("app:")) {
                explicitKeys[order[e_i]] = true;
            }
        }

        for (var oi = 0; oi < order.length; oi++) {
            var entry = order[oi];

            if (root.enableAppGroups && (entry.startsWith("app:") || entry.startsWith("runningApp:"))) {
                const groupedAppId = root._orderEntryAppId(entry);
                const groupedApp = root.appGroupByAppId[groupedAppId];
                if (groupedApp) {
                    if (!seenGroupIds[groupedApp.id]) {
                        result.push(root._makeAppGroupItem(groupedApp));
                        seenGroupIds[groupedApp.id] = true;
                    }
                    for (const memberId of groupedApp.apps) {
                        seenOrderKeys["app:" + memberId] = true;
                        seenOrderKeys["runningApp:" + memberId] = true;
                    }
                    continue;
                }
            }

            if (entry === "pin" && root.showPin) {
                result.push({
                    type: "action",
                    actionId: "pin",
                    orderKey: "pin"
                });
                seenOrderKeys["pin"] = true;
            } else if (entry === "trash" && root.showTrash) {
                result.push({
                    type: "action",
                    actionId: "trash",
                    orderKey: "trash"
                });
                seenOrderKeys["trash"] = true;
            } else if (entry === "overview" && root.showOverview) {
                result.push({
                    type: "action",
                    actionId: "overview",
                    orderKey: "overview"
                });
                seenOrderKeys["overview"] = true;
            } else if (entry === "media" && root.showMedia) {
                result.push({
                    type: "media",
                    orderKey: "media"
                });
                seenOrderKeys["media"] = true;
            } else if (entry === "weather" && root.showWeather) {
                result.push({
                    type: "weather",
                    orderKey: "weather"
                });
                seenOrderKeys["weather"] = true;
            } else if (entry === "sports" && root.showSports) {
                result.push({
                    type: "sports",
                    orderKey: "sports"
                });
                seenOrderKeys["sports"] = true;
            } else if (entry === "livePreview" && root.showLivePreview) {
                result.push({
                    type: "livePreview",
                    orderKey: "livePreview"
                });
                seenOrderKeys["livePreview"] = true;
            } else if (entry === "phone" && root.showPhone) {
                result.push({
                    type: "phone",
                    orderKey: "phone"
                });
                seenOrderKeys["phone"] = true;
            } else if (entry === "runningApps") {
                // The legacy runningApps marker is ignored.
                // Unpinned apps will be handled by the smart append logic at the end,
                // grouping them correctly after the last explicit app icon.
            } else if (entry.startsWith("runningApp:")) {
                // Individual running app that was previously reordered
                var runningAppId = entry.substring(11);
                if (!seenOrderKeys[entry]) {
                    var runningAppData = runningAppMap[runningAppId];
                    if (runningAppData) {
                        result.push({
                            type: "app",
                            appId: runningAppId,
                            appData: runningAppData,
                            orderKey: entry
                        });
                        seenOrderKeys[entry] = true;
                        // Also mark the app: variant to prevent duplicates
                        seenOrderKeys["app:" + runningAppId] = true;
                    }
                    // If app is not running anymore, skip (cleanup)
                }
            } else if (entry.startsWith("app:")) {
                var appId = entry.substring(4);
                var appKey = "app:" + appId;
                if (!seenOrderKeys[appKey]) {
                    var appData = pinnedAppMap[appId] || runningAppMap[appId];
                    if (appData || allAppIds.indexOf(appId) !== -1) {
                        result.push({
                            type: "app",
                            appId: appId,
                            appData: appData || {
                                appId: appId,
                                pinned: true,
                                toplevels: []
                            },
                            orderKey: appKey
                        });
                        seenOrderKeys[appKey] = true;
                        // Also mark the runningApp variant to prevent duplicates
                        // (e.g. when an app goes from pinned→unpinned but stays running)
                        seenOrderKeys["runningApp:" + appId] = true;
                    }
                }
            } else if (entry.startsWith("file:")) {
                var path = entry.substring(5);
                var fileKey = "file:" + path;
                if (!seenOrderKeys[fileKey] && pinnedFileMap[path]) {
                    result.push({
                        type: "file",
                        path: path,
                        orderKey: fileKey
                    });
                    seenOrderKeys[fileKey] = true;
                }
            }
        }

        // Keep a group visible even if all of its app keys were removed from
        // dock.order by an older version or a manual config edit.
        if (root.enableAppGroups) {
            for (const group of root.appGroups) {
                if (seenGroupIds[group.id])
                    continue;
                result.push(root._makeAppGroupItem(group));
                seenGroupIds[group.id] = true;
                for (const memberId of group.apps) {
                    seenOrderKeys["app:" + memberId] = true;
                    seenOrderKeys["runningApp:" + memberId] = true;
                }
            }
        }

        // Append any running apps and pinned apps that weren't in the order at all
        var remainingApps = [];
        var remainingRas = Object.values(runningAppMap);
        for (var rj = 0; rj < remainingRas.length; rj++) {
            var rKey = "runningApp:" + remainingRas[rj].appId;
            if (!seenOrderKeys[rKey]) {
                remainingApps.push({
                    type: "app",
                    appId: remainingRas[rj].appId,
                    appData: remainingRas[rj],
                    orderKey: rKey
                });
                seenOrderKeys[rKey] = true;
                seenOrderKeys["app:" + remainingRas[rj].appId] = true;
            }
        }

        var remainingPinned = Object.values(pinnedAppMap);
        for (var pk = 0; pk < remainingPinned.length; pk++) {
            var pKey = "app:" + remainingPinned[pk].appId;
            if (!seenOrderKeys[pKey]) {
                remainingApps.push({
                    type: "app",
                    appId: remainingPinned[pk].appId,
                    appData: remainingPinned[pk],
                    orderKey: pKey
                });
                seenOrderKeys[pKey] = true;
                seenOrderKeys["runningApp:" + remainingPinned[pk].appId] = true;
            }
        }

        if (remainingApps.length > 0) {
            var targetIndex = -1;
            for (var idx = result.length - 1; idx >= 0; idx--) {
                if (result[idx].type === "app") {
                    targetIndex = idx + 1;
                    break;
                }
            }
            if (targetIndex === -1) {
                targetIndex = result.length;
                while (targetIndex > 0) {
                    var item = result[targetIndex - 1];
                    if (item.type === "action" && (item.actionId === "trash" || item.actionId === "overview" || item.actionId === "pin")) {
                        targetIndex--;
                    } else {
                        break;
                    }
                }
            }
            for (var m = 0; m < remainingApps.length; m++) {
                result.splice(targetIndex + m, 0, remainingApps[m]);
            }
        }

        // Append pinned files that aren't in the order at all (e.g. newly pinned folders)
        var remainingFiles = [];
        var pinnedFiles = Object.values(pinnedFileMap);
        for (var fk = 0; fk < pinnedFiles.length; fk++) {
            var fKey = "file:" + pinnedFiles[fk].path;
            if (!seenOrderKeys[fKey]) {
                remainingFiles.push({
                    type: "file",
                    path: pinnedFiles[fk].path,
                    orderKey: fKey
                });
                seenOrderKeys[fKey] = true;
            }
        }

        if (remainingFiles.length > 0) {
            var fileTargetIndex = -1;
            for (var fidx = result.length - 1; fidx >= 0; fidx--) {
                if (result[fidx].type === "file") {
                    fileTargetIndex = fidx + 1;
                    break;
                }
            }
            if (fileTargetIndex === -1) {
                fileTargetIndex = result.length;
                while (fileTargetIndex > 0) {
                    var fitem = result[fileTargetIndex - 1];
                    if (fitem.type === "action" && (fitem.actionId === "trash" || fitem.actionId === "overview" || fitem.actionId === "pin")) {
                        fileTargetIndex--;
                    } else {
                        break;
                    }
                }
            }
            for (var n = 0; n < remainingFiles.length; n++) {
                result.splice(fileTargetIndex + n, 0, remainingFiles[n]);
            }
        }

        // Existing users may have a dock.order saved before the sports item
        // existed. Keep the new shortcut discoverable without rewriting their
        // entire order list; a later drag persists its explicit position.
        if (root.showSports && !seenOrderKeys["sports"]) {
            const sportsItem = {
                type: "sports",
                orderKey: "sports"
            };
            let sportsTargetIndex = result.length;
            while (sportsTargetIndex > 0) {
                const item = result[sportsTargetIndex - 1];
                if (item.type === "action"
                        && (item.actionId === "trash"
                            || item.actionId === "overview"
                            || item.actionId === "pin")) {
                    sportsTargetIndex--;
                } else {
                    break;
                }
            }
            result.splice(sportsTargetIndex, 0, sportsItem);
            seenOrderKeys["sports"] = true;
        }

        // Existing users may have a dock.order saved before the phone item
        // existed. Keep the new shortcut discoverable without rewriting their
        // entire order list; a later drag persists its explicit position.
        if (root.showPhone && !seenOrderKeys["phone"]) {
            const phoneItem = {
                type: "phone",
                orderKey: "phone"
            };
            let phoneTargetIndex = result.length;
            while (phoneTargetIndex > 0) {
                const item = result[phoneTargetIndex - 1];
                if (item.type === "action"
                        && (item.actionId === "trash"
                            || item.actionId === "overview"
                            || item.actionId === "pin")) {
                    phoneTargetIndex--;
                } else {
                    break;
                }
            }
            result.splice(phoneTargetIndex, 0, phoneItem);
            seenOrderKeys["phone"] = true;
        }

        // Existing users may have a dock.order saved before the live preview
        // item existed. Add it to the derived model near sports/phone without
        // rewriting the persisted order list.
        if (root.showLivePreview && !seenOrderKeys["livePreview"]) {
            const livePreviewItem = {
                type: "livePreview",
                orderKey: "livePreview"
            };
            let livePreviewTargetIndex = result.length;
            const phoneIndex = result.findIndex(item => item.type === "phone");
            if (phoneIndex >= 0) {
                livePreviewTargetIndex = phoneIndex;
            } else {
                while (livePreviewTargetIndex > 0) {
                    const item = result[livePreviewTargetIndex - 1];
                    if (item.type === "action"
                            && (item.actionId === "trash"
                                || item.actionId === "overview"
                                || item.actionId === "pin")) {
                        livePreviewTargetIndex--;
                    } else {
                        break;
                    }
                }
            }
            result.splice(livePreviewTargetIndex, 0, livePreviewItem);
            seenOrderKeys["livePreview"] = true;
        }

        if (Config.options?.dock?.smartGrouping) {
            var mapped = result.map(function (el, i) {
                return {
                    index: i,
                    value: el,
                    cat: root.getItemCategory(el)
                };
            });
            mapped.sort(function (a, b) {
                if (a.cat !== b.cat)
                    return a.cat - b.cat;
                return a.index - b.index;
            });
            result = mapped.map(function (el) {
                return el.value;
            });
        }

        return root._coalesceLauncherItems(result);
    }

    // ── Separator helpers ──────────────────────────────────────────────────
    function isSpecialItem(item) {
        if (!item)
            return false;
        var t = item.type;
        return t === "media" || t === "weather" || t === "sports" || t === "livePreview" || t === "phone" || t === "action";
    }

    function getItemCategory(item) {
        if (!item)
            return 99;
        var t = item.type;

        if (t === "action" && item.actionId === "overview")
            return 1;
        if (t === "action" && item.actionId === "pin")
            return 2;
        if (t === "weather")
            return 3;
        if (t === "sports")
            return 4;
        if (t === "livePreview")
            return 5;
        if (t === "phone")
            return 25;
        if (t === "appGroup" && item.appIds?.length > 0)
            return root.getItemCategory({
                type: "app",
                appId: item.appIds[0]
            });

        var id = "";
        if (t === "app" && item.appId)
            id = item.appId.toLowerCase();

        if (id.match(/(firefox|chrome|chromium|edge|brave|librewolf|vivaldi|opera|waterfox|tor|safari|thorium|zen)/))
            return 10;
        if (t === "file" || id.match(/(dolphin|nautilus|thunar|pcmanfm|nemo|caja|kitty|alacritty|konsole|wezterm|foot|terminal|files)/))
            return 20;
        if (id.match(/(code|vscode|vscodium|idea|intellij|pycharm|webstorm|neovim|nvim|vim|emacs|sublime|notepadqq|kate|kwrite|gedit|geany|zed)/))
            return 30;
        if (id.match(/(discord|vesktop|slack|telegram|whatsapp|signal|teams|element|skype|mattermost)/))
            return 40;
        if (id.match(/(gimp|inkscape|krita|kdenlive|davinci|obs|blender|audacity|lmms|figma)/))
            return 50;
        if (t === "media" || id.match(/(spotify|youtube-music|vlc|mpv|spotify-launcher|amberol|elisa|lollypop|rhythmbox|audacious|cider|mpd)/))
            return 60;
        if (id.match(/(steam|heroic|lutris|epic|minigalaxy|prismlauncher|bottles)/))
            return 70;

        if (t === "action" && item.actionId === "trash")
            return 100;

        if (t === "app")
            return 80;
        return 90;
    }

    function mimeIconFromPath(path) {
        const p = (path ?? "").toString().toLowerCase();
        if (/\.(png|jpe?g|webp|gif|svg|bmp|ico)$/.test(p))
            return "image";
        if (/\.(mp3|flac|ogg|wav|aac|m4a)$/.test(p))
            return "music_note";
        if (/\.(mp4|mkv|webm|avi|mov)$/.test(p))
            return "movie";
        if (p.endsWith(".pdf"))
            return "picture_as_pdf";
        if (/\.(txt|md|rst|log)$/.test(p))
            return "description";
        if (/\.(zip|tar|gz|zst|rar|7z)$/.test(p))
            return "folder_zip";
        const last = p.split("/").filter(s => s).pop() || "";
        return last.includes(".") ? "insert_drive_file" : "folder";
    }

    // ── Layout ────────────────────────────────────────────────────────────
    Flickable {
        id: scrollArea
        anchors.fill: parent
        clip: false
        contentWidth: root.isVertical ? parent.width : unifiedRow.width
        contentHeight: root.isVertical ? unifiedColumn.height : parent.height
        interactive: root.isVertical ? contentHeight > height : contentWidth > width
        flickableDirection: root.isVertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick

        WheelHandler {
            onWheel: event => {
                let d = (event.angleDelta.y !== 0) ? event.angleDelta.y : event.angleDelta.x;
                if (root.isVertical)
                    scrollArea.contentY = Math.max(0, Math.min(scrollArea.contentHeight - scrollArea.height, scrollArea.contentY - d));
                else
                    scrollArea.contentX = Math.max(0, Math.min(scrollArea.contentWidth - scrollArea.width, scrollArea.contentX - d));
                event.accepted = true;
            }
        }

        // Island surfaces live in the same content coordinates as the flat
        // Row/Column, so they scroll together with their delegates.
        Item {
            id: islandLayer
            z: -1
            width: root.isVertical ? parent.width : unifiedRow.width
            height: root.isVertical ? unifiedColumn.height : parent.height

            Repeater {
                model: root.islandSegments

                delegate: DockIslandSurface {
                    required property var modelData

                    readonly property var activeRepeater: root._getActiveRepeater()
                    readonly property var firstWrapper: {
                        const repeater = activeRepeater;
                        if (!repeater)
                            return null;
                        repeater.count;
                        return root.getItemWrapper(modelData.startIndex);
                    }
                    readonly property var lastWrapper: {
                        const repeater = activeRepeater;
                        if (!repeater)
                            return null;
                        repeater.count;
                        return root.getItemWrapper(modelData.endIndex);
                    }
                    readonly property bool endpointGeometryReady: !!firstWrapper
                        && !!lastWrapper
                        && firstWrapper.bodyMainEnd > firstWrapper.bodyMainStart
                        && lastWrapper.bodyMainEnd > lastWrapper.bodyMainStart

                    active: root.islandsStyle && endpointGeometryReady
                    islandKind: modelData.kind
                    dockPosition: root.dockPos
                    cornerRadius: root.dockCornerRadius
                    x: root.isVertical ? 0 : (firstWrapper?.bodyMainStart ?? 0)
                    y: root.isVertical ? (firstWrapper?.bodyMainStart ?? 0) : 0
                    width: root.isVertical
                        ? root.buttonSlotSize
                        : Math.max(0, (lastWrapper?.bodyMainEnd ?? 0) - (firstWrapper?.bodyMainStart ?? 0))
                    height: root.isVertical
                        ? Math.max(0, (lastWrapper?.bodyMainEnd ?? 0) - (firstWrapper?.bodyMainStart ?? 0))
                        : root.buttonSlotHeight
                }
            }
        }

        // Transparent drag handles sit on the outer padding of each island.
        // Keeping the handle out of the icon hitboxes preserves app clicks,
        // previews and app-group creation while making the island itself movable.
        Item {
            id: islandInteractionLayer
            z: 2
            width: root.isVertical ? parent.width : unifiedRow.width
            height: root.isVertical ? unifiedColumn.height : parent.height

            Repeater {
                model: root.islandSegments

                delegate: Item {
                    required property var modelData

                    readonly property var activeRepeater: root._getActiveRepeater()
                    readonly property var firstWrapper: {
                        const repeater = activeRepeater;
                        if (!repeater)
                            return null;
                        repeater.count;
                        return root.getItemWrapper(modelData.startIndex);
                    }
                    readonly property var lastWrapper: {
                        const repeater = activeRepeater;
                        if (!repeater)
                            return null;
                        repeater.count;
                        return root.getItemWrapper(modelData.endIndex);
                    }
                    readonly property bool endpointGeometryReady: !!firstWrapper
                        && !!lastWrapper
                        && firstWrapper.bodyMainEnd > firstWrapper.bodyMainStart
                        && lastWrapper.bodyMainEnd > lastWrapper.bodyMainStart

                    enabled: root.islandsStyle && endpointGeometryReady
                    x: root.isVertical ? 0 : (firstWrapper?.bodyMainStart ?? 0)
                    y: root.isVertical ? (firstWrapper?.bodyMainStart ?? 0) : 0
                    width: root.isVertical
                        ? root.buttonSlotSize
                        : Math.max(0, (lastWrapper?.bodyMainEnd ?? 0) - (firstWrapper?.bodyMainStart ?? 0))
                    height: root.isVertical
                        ? Math.max(0, (lastWrapper?.bodyMainEnd ?? 0) - (firstWrapper?.bodyMainStart ?? 0))
                        : root.buttonSlotHeight

                    Item {
                        id: islandDragStrip
                        width: root.isVertical
                            ? Math.max(root.dotMargin, root.sepThickness * 2)
                            : parent.width
                        height: root.isVertical
                            ? parent.height
                            : Math.max(root.dotMarginV, root.sepThickness * 2)

                        anchors.top: !root.isVertical && root.dockPos === "bottom" ? parent.top : undefined
                        anchors.bottom: !root.isVertical && root.dockPos === "top" ? parent.bottom : undefined
                        anchors.left: root.isVertical && root.dockPos === "right" ? parent.left : undefined
                        anchors.right: root.isVertical && root.dockPos === "left" ? parent.right : undefined

                        HoverHandler {
                            cursorShape: islandDragHandler.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        }

                        DragHandler {
                            id: islandDragHandler
                            enabled: parent.parent.enabled
                                && !root.dragging
                                && !root.anyContextMenuOpen
                            target: null
                            acceptedButtons: Qt.LeftButton
                            grabPermissions: PointerHandler.CanTakeOverFromAnything
                            xAxis.enabled: !root.isVertical
                            yAxis.enabled: root.isVertical

                            onActiveChanged: {
                                if (active)
                                    root.startIslandDrag(modelData.id, centroid.scenePosition);
                                else
                                    root.endIslandDrag();
                            }

                            onCentroidChanged: {
                                if (active)
                                    root.moveIslandDrag(centroid.scenePosition);
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: unifiedRow
            visible: !root.isVertical
            spacing: (Config.options && Config.options.dock && Config.options.dock.iconSpacing !== undefined) ? Config.options.dock.iconSpacing : 0

            Repeater {
                id: itemRepeater
                model: root.flattenedItems
                delegate: unifiedItemDelegate
            }
        }

        Column {
            id: unifiedColumn
            visible: root.isVertical
            spacing: (Config.options && Config.options.dock && Config.options.dock.iconSpacing !== undefined) ? Config.options.dock.iconSpacing : 0

            Repeater {
                id: columnItemRepeater
                model: root.flattenedItems
                delegate: unifiedItemDelegate
            }
        }
    }

    // ── Unified item delegate ──────────────────────────────────────────────
    Component {
        id: unifiedItemDelegate

        Item {
            id: delegateWrapper
            required property var modelData
            required property int index
            readonly property int delegateIndex: index
            readonly property var itemData: modelData
            readonly property real itemWidth: {
                if (root.isVertical)
                    return root.buttonSlotSize;
                switch (itemData.type) {
                case "media":
                case "weather":
                    return root.buttonSlotSize * 3;
                case "sports":
                    return root.buttonSlotSize * root.sportsWidgetSlots;
                case "livePreview":
                    return root.buttonSlotSize * root.livePreviewWidgetSlots;
                default:
                    return root.buttonSlotSize;
                }
            }
            readonly property real itemHeight: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property bool magnifiable: root._isMagnifiableItem(delegateWrapper.itemData)
            readonly property var islandMeta: root._islandMetaForIndex(delegateIndex)
            readonly property string islandId: islandMeta?.id ?? ""
            readonly property bool isIslandStart: islandMeta?.startIndex === delegateIndex
            readonly property real targetLeadingIslandGap: root._leadingIslandGapForIndex(delegateIndex)
            property real animatedLeadingIslandGap: targetLeadingIslandGap
            readonly property real leadingIslandGap: animatedLeadingIslandGap
            readonly property real baseBodyMainExtent: root._baseItemMainExtentForIndex(delegateIndex)
            readonly property real baseMainExtent: root.baseMetrics.items[delegateIndex]?.baseExtent ?? (root.isVertical ? root.buttonSlotSize : itemWidth)
            readonly property real targetMagScale: root._targetMagScaleForIndex(delegateIndex)
            property real animatedMagScale: targetMagScale
            readonly property real layoutExtra: magnifiable && root.magnificationDynamicSpacing
                ? root.magnificationLayoutExtraForFactor((animatedMagScale - 1.0) / Math.max(0.001, root.magnificationScale - 1.0))
                : 0
            readonly property real bodyMainExtent: baseBodyMainExtent + layoutExtra
            readonly property real bodyMainStart: (root.isVertical ? y : x) + leadingIslandGap
            readonly property real bodyMainEnd: bodyMainStart + bodyMainExtent
            readonly property real _magnificationScale: animatedMagScale

            Behavior on animatedLeadingIslandGap {
                enabled: !root.dragging && !root.islandDragging
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Behavior on animatedMagScale {
                enabled: !root.dragging
                SpringAnimation {
                    spring: root.magnificationMotionProfile.spring
                    damping: root.magnificationMotionProfile.damping
                    mass: root.magnificationMotionProfile.mass
                    epsilon: root.magnificationMotionProfile.epsilon
                }
            }

            // Drag translation (adapted from dots-hyprland, variable-width support)
            readonly property bool isDragged: root.dragging && delegateIndex === root.dragSourceIndex
            readonly property real dragTranslate: {
                if (!root.dragging)
                    return 0;
                if (isDragged)
                    return root.dragCursorX - root.dragStartCursorX;
                var src = root.dragSourceIndex;
                var tgt = root._dragTargetIndex;
                var idx = delegateIndex;
                var sw = root.slotWidth;
                if (src < tgt && idx > src && idx <= tgt)
                    return -sw;
                if (src > tgt && idx >= tgt && idx < src)
                    return sw;
                return 0;
            }
            readonly property real itemMagScale: animatedMagScale
            z: isDragged ? 100 : (itemMagScale > 1.01 ? Math.round(itemMagScale * 50) : 0)
            opacity: isDragged ? 0.85 : 1
            scale: isDragged ? 1.05 : 1

            Behavior on opacity {
                enabled: !root._suppressTranslateAnim
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on scale {
                enabled: !root._suppressTranslateAnim
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            transform: Translate {
                x: root.isVertical ? 0 : delegateWrapper.dragTranslate
                y: root.isVertical ? delegateWrapper.dragTranslate : 0
                Behavior on x {
                    enabled: !delegateWrapper.isDragged && !root._suppressTranslateAnim
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    enabled: !delegateWrapper.isDragged && !root._suppressTranslateAnim
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            // ── Intelligent separators ──────────────────────────────────────
            readonly property bool _sepIsSpecial: root.isSpecialItem(delegateWrapper.itemData)
            readonly property bool _sepNextIsSpecial: {
                if (delegateIndex >= root.flattenedItems.length - 1)
                    return false;
                return root.isSpecialItem(root.flattenedItems[delegateIndex + 1]);
            }
            readonly property bool _sepDividersOn: root.effectiveShowDividers
            readonly property bool _sepShowBefore: {
                if (!_sepDividersOn || delegateIndex === 0)
                    return false;
                if (Config.options?.dock?.smartGrouping) {
                    return root.getItemCategory(root.flattenedItems[delegateIndex]) !== root.getItemCategory(root.flattenedItems[delegateIndex - 1]);
                }
                return _sepIsSpecial && delegateIndex > 0;
            }
            readonly property bool _sepShowAfter: {
                if (!_sepDividersOn || delegateIndex >= root.flattenedItems.length - 1)
                    return false;
                if (Config.options?.dock?.smartGrouping) {
                    return false; // we only draw before to avoid double lines
                }
                return _sepIsSpecial && !_sepNextIsSpecial;
            }
            // Reserve a real layout slot for each divider. This keeps the line
            // away from both the current icon and the preceding widget even
            // when iconSpacing is compact or negative.
            readonly property real _separatorSlot: Math.max(root.dotMargin, root.sepThickness * 2)
            readonly property real _separatorBeforeSpace: _sepShowBefore ? _separatorSlot : 0
            readonly property real _separatorAfterSpace: _sepShowAfter ? _separatorSlot : 0
            readonly property real _separatorLineMargin: (_separatorSlot - root.sepThickness) / 2

            width: root.isVertical ? itemHeight : leadingIslandGap + bodyMainExtent
            height: root.isVertical ? leadingIslandGap + bodyMainExtent : itemHeight

            // Horizontal mode: left vertical line
            Rectangle {
                visible: delegateWrapper._sepShowBefore && !root.isVertical
                anchors.left: parent.left
                anchors.leftMargin: delegateWrapper._separatorLineMargin
                anchors.verticalCenter: parent.verticalCenter
                width: root.sepThickness
                height: parent.height - root.dotMarginV * 2
                radius: Appearance.rounding.full
                color: Appearance.colors.colOutlineVariant
            }
            // Horizontal mode: right vertical line
            Rectangle {
                visible: delegateWrapper._sepShowAfter && !root.isVertical
                anchors.right: parent.right
                anchors.rightMargin: delegateWrapper._separatorLineMargin
                anchors.verticalCenter: parent.verticalCenter
                width: root.sepThickness
                height: parent.height - root.dotMarginV * 2
                radius: Appearance.rounding.full
                color: Appearance.colors.colOutlineVariant
            }
            // Vertical mode: top horizontal line
            Rectangle {
                visible: delegateWrapper._sepShowBefore && root.isVertical
                anchors.top: parent.top
                anchors.topMargin: delegateWrapper._separatorLineMargin
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - root.dotMargin * 2
                height: root.sepThickness
                radius: Appearance.rounding.full
                color: Appearance.colors.colOutlineVariant
            }
            // Vertical mode: bottom horizontal line
            Rectangle {
                visible: delegateWrapper._sepShowAfter && root.isVertical
                anchors.bottom: parent.bottom
                anchors.bottomMargin: delegateWrapper._separatorLineMargin
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - root.dotMargin * 2
                height: root.sepThickness
                radius: Appearance.rounding.full
                color: Appearance.colors.colOutlineVariant
            }

            Loader {
                id: contentLoader
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: root.isVertical ? 0 : delegateWrapper.leadingIslandGap / 2 + (delegateWrapper._separatorBeforeSpace - delegateWrapper._separatorAfterSpace) / 2
                anchors.verticalCenterOffset: root.isVertical ? delegateWrapper.leadingIslandGap / 2 + (delegateWrapper._separatorBeforeSpace - delegateWrapper._separatorAfterSpace) / 2 : 0

                // Expose delegate data so loaded components can access it via parent
                readonly property var _itemData: delegateWrapper.itemData
                readonly property int _index: delegateWrapper.index
                readonly property real _magnificationScale: delegateWrapper._magnificationScale
                readonly property string _islandId: delegateWrapper.islandId

                sourceComponent: {
                    switch (itemData.type) {
                    case "action":
                        return actionItemComponent;
                    case "appGroup":
                        return appGroupItemComponent;
                    case "app":
                        return appItemComponent;
                    case "file":
                        return fileItemComponent;
                    case "media":
                        return mediaItemComponent;
                    case "weather":
                        return weatherItemComponent;
                    case "sports":
                        return sportsItemComponent;
                    case "livePreview":
                        return livePreviewItemComponent;
                    case "phone":
                        return phoneItemComponent;
                    case "runningAppsGroup":
                        return runningAppsGroupComponent;
                    default:
                        return null;
                    }
                }
            }

            Rectangle {
                visible: root.isGroupDropTarget(delegateWrapper.delegateIndex)
                anchors.fill: parent
                z: 5
                radius: Appearance.rounding.normal
                color: root.groupDropIsBlocked(delegateWrapper.delegateIndex)
                    ? Appearance.colors.colErrorContainer
                    : Appearance.colors.colPrimaryContainer
                opacity: visible ? 0.28 : 0.0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                visible: root.isGroupDropTarget(delegateWrapper.delegateIndex)
                width: Math.max(Appearance.font.pixelSize.normal, root.buttonSlotSize * 0.3)
                height: width
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -height * 0.18
                anchors.rightMargin: -width * 0.18
                z: 6
                radius: Appearance.rounding.full
                color: root.groupDropIsBlocked(delegateWrapper.delegateIndex)
                    ? Appearance.colors.colError
                    : Appearance.colors.colPrimary

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.groupDropIsBlocked(delegateWrapper.delegateIndex)
                        ? "block"
                        : (root.groupDropWillCreate(delegateWrapper.delegateIndex) ? "create_new_folder" : "group_add")
                    iconSize: Appearance.font.pixelSize.small
                    color: root.groupDropIsBlocked(delegateWrapper.delegateIndex)
                        ? Appearance.colors.colOnError
                        : Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // ── Item type components ───────────────────────────────────────────────

    Component {
        id: appGroupItemComponent
        Item {
            id: appGroupItemRoot
            width: root.buttonSlotSize
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property var _itemData: parent._itemData
            readonly property int _index: parent._index

            DockAppGroupButton {
                anchors.centerIn: parent
                apps: appGroupItemRoot._itemData.apps ?? []
                dockContent: root
                groupId: appGroupItemRoot._itemData.groupId ?? ""
                delegateIndex: appGroupItemRoot._index
            }
        }
    }

    Component {
        id: actionItemComponent
        Item {
            id: actionItemRoot
            width: root.buttonSlotSize
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property var _itemData: parent._itemData
            readonly property int _index: parent._index
            DockActionButton {
                anchors.centerIn: parent
                property int _delegateIndex: actionItemRoot._index
                symbolName: {
                    switch (actionItemRoot._itemData.actionId) {
                    case "pin":
                        return "keep";
                    case "trash":
                        return "delete";
                    case "overview":
                        return "apps";
                    default:
                        return "drag_indicator";
                    }
                }
                toggledSymbolName: actionItemRoot._itemData.actionId === "pin" ? "bookmark" : ""
                toggled: actionItemRoot._itemData.actionId === "pin" && root.isPinned
                normalShape: actionItemRoot._itemData.actionId === "overview" ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Pill
                activeShape: actionItemRoot._itemData.actionId === "overview" ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie9Sided
                symbolSize: Math.round(Appearance.sizes.dockButtonSize * 0.5)
                dockContent: root
                delegateIndex: actionItemRoot._index
                onClicked: {
                    if (actionItemRoot._itemData.actionId === "pin")
                        root.togglePinRequested();
                    else if (actionItemRoot._itemData.actionId === "trash")
                        Quickshell.execDetached(["nautilus", "trash:///"]);
                    else if (actionItemRoot._itemData.actionId === "overview")
                        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
                }
                customImageSource: actionItemRoot._itemData.actionId === "trash" ? ("file://" + Directories.assetsPath + "/icons/" + (Appearance.m3colors.darkmode ? "macos-trash-dark.png" : "macos-trash.png")) : ""
                dragActive: false
                dragOver: false
                dragSymbol: ""
            }
        }
    }

    Component {
        id: appItemComponent
        Item {
            id: appItemRoot
            width: root.buttonSlotSize
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property var _itemData: parent._itemData
            readonly property int _index: parent._index
            readonly property string _appId: _itemData?.appId ?? ""
            readonly property bool _groupReturnRequested: root.shouldAnimateGroupAppReturn(_appId)
            readonly property bool _groupExitRequested: root.isGroupAppExiting(_appId)
            property real _groupTransitionOpacity: 1.0
            property real _groupTransitionScale: 1.0

            function playGroupReturnAnimation() {
                _groupTransitionOpacity = 0.0;
                _groupTransitionScale = 0.72;
                Qt.callLater(function () {
                    if (!appItemRoot)
                        return;
                    appItemRoot._groupTransitionOpacity = 1.0;
                    appItemRoot._groupTransitionScale = 1.0;
                });
            }

            function playGroupExitAnimation() {
                _groupTransitionOpacity = 0.0;
                _groupTransitionScale = 0.72;
            }

            Component.onCompleted: {
                if (_groupReturnRequested)
                    playGroupReturnAnimation();
                else if (_groupExitRequested)
                    playGroupExitAnimation();
            }

            Connections {
                target: root
                function onGroupMutationRevisionChanged() {
                    if (appItemRoot._groupExitRequested)
                        appItemRoot.playGroupExitAnimation();
                }
                function onGroupTransitionRevisionChanged() {
                    if (appItemRoot._groupReturnRequested)
                        appItemRoot.playGroupReturnAnimation();
                }
            }

            readonly property bool _isDragged: root.dragging && _index === root.dragSourceIndex
            opacity: (_isDragged ? 0.85 : 1.0) * _groupTransitionOpacity
            scale: (_isDragged ? 1.05 : 1.0) * _groupTransitionScale

            Behavior on opacity {
                enabled: !root._suppressTranslateAnim
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Behavior on scale {
                enabled: !root._suppressTranslateAnim
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            DockAppButton {
                anchors.centerIn: parent
                appToplevel: appItemRoot._itemData.appData
                dockContent: root
                delegateIndex: appItemRoot._index
            }
        }
    }

    Component {
        id: fileItemComponent
        Item {
            id: fileItemRoot
            width: root.buttonSlotSize
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property var _itemData: parent._itemData
            readonly property int _index: parent._index
            DockFileButton {
                anchors.centerIn: parent
                filePath: fileItemRoot._itemData.path
                dockContent: root
                delegateIndex: fileItemRoot._index
            }
        }
    }

    Component {
        id: mediaItemComponent
        Item {
            id: mediaItemRoot
            width: root.isVertical ? root.buttonSlotSize : root.buttonSlotSize * 3
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property int _index: parent._index
            Loader {
                anchors.fill: parent
                active: root.dockWidgetsActive
                sourceComponent: DockMediaWidget {
                    anchors.centerIn: parent
                    isVertical: root.isVertical
                    dockContent: root
                    delegateIndex: mediaItemRoot._index
                }
            }
        }
    }

    Component {
        id: weatherItemComponent
        Item {
            id: weatherItemRoot
            width: root.isVertical ? root.buttonSlotSize : root.buttonSlotSize * 3
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property int _index: parent._index
            DockWeatherWidget {
                anchors.centerIn: parent
                isVertical: root.isVertical
                dockContent: root
                delegateIndex: weatherItemRoot._index
            }
        }
    }

    Component {
        id: sportsItemComponent
        Item {
            id: sportsItemRoot
            width: root.isVertical ? root.buttonSlotSize : root.buttonSlotSize * 3
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property int _index: parent._index
            DockSportsWidget {
                anchors.centerIn: parent
                isVertical: root.isVertical
                dockContent: root
                delegateIndex: sportsItemRoot._index
            }
        }
    }

    Component {
        id: livePreviewItemComponent
        Item {
            id: livePreviewItemRoot
            width: root.isVertical ? root.buttonSlotSize : root.buttonSlotSize * root.livePreviewWidgetSlots
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property int _index: parent._index
            Loader {
                anchors.fill: parent
                active: root.dockWidgetsActive
                sourceComponent: DockLivePreviewWidget {
                    anchors.centerIn: parent
                    isVertical: root.isVertical
                    dockContent: root
                    dockRevealed: root.dockRevealed
                    dockWindowVisible: root.dockWindowVisible
                    delegateIndex: livePreviewItemRoot._index
                    onPickerRequested: {
                        // Picker wiring belongs to the following live-preview phase.
                    }
                }
            }
        }
    }

    Component {
        id: phoneItemComponent
        Item {
            id: phoneItemRoot
            width: root.buttonSlotSize
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property int _index: parent._index
            DockPhoneWidget {
                anchors.centerIn: parent
                isVertical: root.isVertical
                dockContent: root
                delegateIndex: phoneItemRoot._index
            }
        }
    }

    Component {
        id: runningAppsGroupComponent
        Item {
            id: runningAppsRoot
            width: runningAppsRow.implicitWidth + root.dotMargin * 2
            height: root.isVertical ? root.buttonSlotSize : root.buttonSlotHeight
            readonly property var _itemData: parent._itemData
            readonly property int _index: parent._index
            Row {
                id: runningAppsRow
                spacing: Config.options.dock.iconSpacing
                anchors.centerIn: parent
                Repeater {
                    model: runningAppsRoot._itemData.apps ?? []
                    delegate: DockAppButton {
                        required property var modelData
                        appToplevel: modelData
                        dockContent: root
                        delegateIndex: -1
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                preventStealing: true
                cursorShape: Qt.PointingHandCursor
                propagateComposedEvents: true
                property real pressCoord: 0
                property bool dragActive: false
                onPressed: event => {
                    pressCoord = root.isVertical ? event.y : event.x;
                    event.accepted = false;
                }
                onPositionChanged: event => {
                    if (!pressed)
                        return;
                    var cur = root.isVertical ? event.y : event.x;
                    var dist = Math.abs(cur - pressCoord);
                    if (!dragActive && dist > 5) {
                        dragActive = true;
                        root.startItemDrag(parent._index, this, event.x, event.y);
                    }
                    if (dragActive) {
                        root.moveItemDrag(this, event.x, event.y);
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
                onReleased: event => {
                    if (dragActive) {
                        dragActive = false;
                        root.endItemDrag();
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
                onCanceled: event => {
                    if (dragActive) {
                        dragActive = false;
                        root.cancelDrag();
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }
            }
        }
    }

    // ── Preview Popup ──────────────────────────────────────────────────────
    Loader {
        id: previewPopupLoader
        active: Config.options.dock.enablePreview ?? true
        sourceComponent: DockPreviewPopup {
            dockRoot: root
            dockWindow: root.QsWindow.window
            appTopLevel: root.lastHoveredButton?.appToplevel
        }
    }
}
