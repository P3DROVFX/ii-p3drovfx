pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.overview
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

/**
 * The overview for Hyprland's scrolling layout.
 *
 * Workspaces are rows stacked down the middle of the screen, the active one
 * centred; each row is a strip of the workspace's columns laid out where
 * Hyprland really has them, around a frame that stands for the monitor. Only
 * workspaces with windows are listed, plus the active one and a trailing empty
 * row to drop a window on — a new workspace, the way Niri does it.
 *
 * The widget fills its host and never follows the search surface's size. The
 * host says where the collapsed search ends (`topInset`) and the rows fade out
 * before reaching it, so a growing result list covers them instead of pushing
 * them around.
 */
Item {
    id: root

    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"
    required property int monitorIndex
    required property var panelWindow
    /** Where the collapsed search surface ends, in this item's coordinates. */
    property real topInset: 0
    /**
     * Whether the host wants the rows on screen (false while search results or a
     * panel own the surface). The rows play their own entrance and exit, so
     * hosts only show and hide the whole item.
     */
    property bool presented: true
    readonly property bool showing: root.presented && GlobalStates.overviewOpen
    onShowingChanged: root.playReveal(root.showing)

    function playReveal(show) {
        const active = root.rowIds.indexOf(root.activeWorkspaceId);
        for (let i = 0; i < rowRepeater.count; i++) {
            const row = rowRepeater.itemAt(i);
            if (!row)
                continue;
            const distance = active === -1 ? 0 : Math.abs(i - active);
            row.playReveal(show, 40 + Math.min(distance, 3) * 60);
        }
    }

    /** Room kept free at the bottom (a bottom bar's search, or just a margin). */
    property real bottomInset: Appearance.sizes.elevationMargin
    readonly property real fadeSize: 140

    // ── Monitor ─────────────────────────────────────────────────────────────
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    readonly property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id) ?? null
    readonly property bool rotated: (root.monitorData?.transform ?? 0) % 2 === 1
    readonly property real monitorScale: (root.monitorData?.scale ?? 0) > 0 ? root.monitorData.scale : 1
    // A frame stands for the whole monitor, bar included: it is where the
    // wallpaper lands when the background zooms out onto the active row.
    readonly property real screenWidth: Math.max(1, ((root.rotated ? root.monitorData?.height : root.monitorData?.width) ?? 1920) / root.monitorScale)
    readonly property real screenHeight: Math.max(1, ((root.rotated ? root.monitorData?.width : root.monitorData?.height) ?? 1080) / root.monitorScale)
    readonly property real originX: root.monitorData?.x ?? 0
    readonly property real originY: root.monitorData?.y ?? 0
    readonly property string screenName: root.panelWindow?.screen?.name ?? ""
    readonly property var backgroundController: GlobalStates.overviewBackgroundControllerFor(root.screenName)
    readonly property string wallpaperSource: root.backgroundController?.wallpaperPath ?? ""
    /**
     * While the background zooms onto (or away from) the active row, the row
     * itself is the wallpaper plane and the window captures; the overview's own
     * copy only appears once they have landed.
     */
    readonly property bool backgroundCarriesActiveRow: (root.backgroundController?.scrollingAimed ?? false)
        && !root.activeFullscreen
        && ((root.backgroundController?.active ?? false) || (root.backgroundController?.progress ?? 0) > 0.001)
        && !(root.backgroundController?.scrollingHandedOff ?? false)
    /**
     * A fullscreen window on the active workspace is drawn above the wallpaper
     * and the zoom's window captures (Background/Top layers), so neither can be
     * seen: the rows would fade into the live window behind them. The overview
     * then brings its own backdrop, the Gnome backing (blurred, dimmed wallpaper).
     */
    readonly property bool activeFullscreen: {
        const windows = HyprlandData.windowList;
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (w.monitor === root.monitor?.id && w.workspace?.id === root.activeWorkspaceId && ((w.fullscreen ?? 0) & 2))
                return true;
        }
        return false;
    }
    /**
     * Tiles start live capture and refresh frozen frames only once the zoom has
     * landed: starting every screencopy stream in the zoom's first frames is
     * what made the opening stutter.
     */
    readonly property bool capturesSettled: !root.backgroundCarriesActiveRow
    readonly property size wallpaperDecodeSize: Qt.size(Math.round(root.screenWidth * 0.6), Math.round(root.screenHeight * 0.6))
    /** Shared with the background controller, so the zoom lands on this exact shape. */
    readonly property real frameRadius: Appearance.rounding.normal + 4

    readonly property list<int> workspaceMap: Config.options.bar.workspaces.workspaceMap
    readonly property bool useWorkspaceMap: Config.options.bar.workspaces.useWorkspaceMap && Config.options.overview.useWorkspaceMap
    readonly property int hyprlandMonitorIndex: {
        const idx = HyprlandData.monitors.findIndex(mon => mon.name === root.monitor?.name);
        return idx !== -1 ? idx : 0;
    }
    /** Subtracted from workspace ids for their labels, so each monitor counts from 1. */
    readonly property int workspaceOffset: {
        if (!root.useWorkspaceMap)
            return 0;
        const map = root.workspaceMap;
        if (map.length > root.hyprlandMonitorIndex)
            return map[root.hyprlandMonitorIndex];
        return root.hyprlandMonitorIndex * (Config.options.bar.workspaces.shown || 10);
    }

    // ── Layout ──────────────────────────────────────────────────────────────
    readonly property real gutter: 112
    readonly property real rowGap: 28
    readonly property real regionTop: root.topInset
    readonly property real regionBottom: root.height - root.bottomInset
    readonly property real regionHeight: Math.max(1, root.regionBottom - root.regionTop)
    readonly property real viewCenterY: (root.regionTop + root.regionBottom) / 2
    readonly property real layoutScale: {
        if (Config.options.overview.enableManualScale ?? false)
            return Config.options.overview.scale * 1.25;
        const byHeight = root.regionHeight * 0.36 / root.screenHeight;
        const byWidth = (root.width - root.gutter * 2) * 0.5 / root.screenWidth;
        return Math.max(0.05, Math.min(byHeight, byWidth) * (Config.options.overview.autoScaleFactor ?? 1));
    }
    readonly property real frameWidth: Math.round(root.screenWidth * root.layoutScale)
    readonly property real frameHeight: Math.round(root.screenHeight * root.layoutScale)
    readonly property real pitch: root.frameHeight + root.rowGap

    /** A window's rectangle relative to its workspace's frame, scaled. */
    function tileRect(address) {
        const w = HyprlandData.windowByAddress[address];
        if (!w || !w.at || !w.size)
            return Qt.rect(0, 0, 0, 0);
        const s = root.layoutScale;
        return Qt.rect(Math.round((w.at[0] - root.originX) * s), Math.round((w.at[1] - root.originY) * s),
            Math.round(w.size[0] * s), Math.round(w.size[1] * s));
    }

    // ── Workspaces and windows ──────────────────────────────────────────────
    readonly property int activeWorkspaceId: root.monitor?.activeWorkspace?.id ?? -1

    readonly property var rowIds: {
        const monitorId = root.monitor?.id;
        const seen = {};
        const windows = HyprlandData.windowList;
        for (let i = 0; i < windows.length; i++) {
            const id = windows[i].workspace?.id ?? 0;
            if (windows[i].monitor === monitorId && id > 0)
                seen[id] = true;
        }
        if (root.activeWorkspaceId > 0)
            seen[root.activeWorkspaceId] = true;
        const ids = Object.keys(seen).map(Number).sort((a, b) => a - b);
        ids.push(ids.length > 0 ? ids[ids.length - 1] + 1 : root.workspaceOffset + 1);
        return ids;
    }

    /** A workspace's windows on this monitor, left to right, floating ones last. */
    function addressesFor(workspaceId) {
        const monitorId = root.monitor?.id;
        return HyprlandData.windowList
            .filter(w => w.workspace?.id === workspaceId && w.monitor === monitorId)
            .sort((a, b) => (a.floating - b.floating) || (a.at[0] - b.at[0]) || (a.at[1] - b.at[1]))
            .map(w => w.address);
    }

    /** The window the active workspace would give focus back to. */
    readonly property string focusedAddress: {
        let best = null;
        const windows = HyprlandData.windowList;
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (w.workspace?.id !== root.activeWorkspaceId || w.monitor !== root.monitor?.id)
                continue;
            if (!best || w.focusHistoryID < best.focusHistoryID)
                best = w;
        }
        return best?.address ?? "";
    }

    // ── Vertical scroll, in rows ────────────────────────────────────────────
    property real scrollSlot: 0
    readonly property real scrollMax: Math.max(0, root.rowIds.length - 1)
    onScrollMaxChanged: {
        if (root.scrollSlot > root.scrollMax)
            root.scrollToSlot(root.scrollMax, true);
    }

    NumberAnimation {
        id: scrollAnimation
        target: root
        property: "scrollSlot"
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
    }

    function scrollToSlot(slot, animate) {
        const target = Math.max(0, Math.min(root.scrollMax, slot));
        scrollAnimation.stop();
        if (!animate || root.animationsDisabled) {
            root.scrollSlot = target;
            return;
        }
        scrollAnimation.from = root.scrollSlot;
        scrollAnimation.to = target;
        scrollAnimation.start();
    }

    function scrollToWorkspace(workspaceId, animate) {
        const slot = (root.rowIds ?? []).indexOf(workspaceId);
        if (slot !== -1)
            root.scrollToSlot(slot, animate);
    }

    function rowTop(slot) {
        return root.viewCenterY - root.frameHeight / 2 + (slot - root.scrollSlot) * root.pitch;
    }

    function rowAt(y) {
        const slot = Math.floor((y - root.rowTop(0)) / root.pitch);
        if (slot < 0 || slot >= rowRepeater.count)
            return null;
        return rowRepeater.itemAt(slot);
    }

    Timer {
        id: snapTimer
        interval: 160
        onTriggered: root.scrollToSlot(Math.round(root.scrollSlot), true)
    }

    function handleWheel(wheel) {
        const horizontal = (wheel.modifiers & Qt.ShiftModifier) || Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y);
        const angle = horizontal ? (wheel.angleDelta.x || wheel.angleDelta.y) : wheel.angleDelta.y;
        const pixel = horizontal ? (wheel.pixelDelta.x || wheel.pixelDelta.y) : wheel.pixelDelta.y;
        const notch = Math.abs(angle) >= 120 && pixel === 0;
        if (horizontal) {
            const row = root.rowAt(wheel.y);
            if (!row)
                return;
            if (notch)
                row.panBy(Math.sign(angle) * root.frameWidth * 0.4, false);
            else
                row.panBy(pixel !== 0 ? pixel : angle / 8, true);
            return;
        }
        if (notch) {
            snapTimer.stop();
            const base = scrollAnimation.running ? scrollAnimation.to : Math.round(root.scrollSlot);
            root.scrollToSlot(base - Math.sign(angle) * Math.max(1, Math.round(Math.abs(angle) / 120)), true);
            return;
        }
        scrollAnimation.stop();
        const delta = (pixel !== 0 ? pixel : angle / 8) / root.pitch;
        root.scrollSlot = Math.max(-0.35, Math.min(root.scrollMax + 0.35, root.scrollSlot - delta));
        snapTimer.restart();
    }

    // ── Selection (pointer and keyboard share it) ───────────────────────────
    property string selectedAddress: ""
    property int selectedWorkspace: -1
    property bool keyboardSelecting: false

    function pointAt(address, workspaceId) {
        if (root.dragging)
            return;
        root.keyboardSelecting = false;
        root.selectedAddress = address;
        root.selectedWorkspace = workspaceId;
    }

    function pointAway(address) {
        if (root.keyboardSelecting || root.selectedAddress !== address)
            return;
        root.selectedAddress = "";
        root.selectedWorkspace = -1;
    }

    function select(workspaceId, address) {
        root.keyboardSelecting = true;
        root.selectedWorkspace = workspaceId;
        root.selectedAddress = address;
        root.scrollToWorkspace(workspaceId, true);
        const row = rowRepeater.itemAt(root.rowIds.indexOf(workspaceId));
        if (row && address !== "")
            row.reveal(root.tileRect(address));
    }

    function nearestIn(workspaceId, centerX) {
        const list = root.addressesFor(workspaceId);
        let best = "";
        let bestDistance = Infinity;
        for (let i = 0; i < list.length; i++) {
            const r = root.tileRect(list[i]);
            const distance = Math.abs(r.x + r.width / 2 - centerX);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = list[i];
            }
        }
        return best;
    }

    /** Arrow keys and Enter from the search field while its query is empty. */
    function handleNavigationKey(key) {
        if (root.rowIds.length === 0)
            return false;
        if (root.selectedWorkspace < 0 || root.rowIds.indexOf(root.selectedWorkspace) === -1) {
            if (key === "enter")
                return false;
            const start = root.activeWorkspaceId > 0 ? root.activeWorkspaceId : root.rowIds[0];
            root.select(start, root.focusedAddress !== "" ? root.focusedAddress : (root.addressesFor(start)[0] ?? ""));
            return true;
        }
        if (key === "enter") {
            if (root.selectedAddress !== "")
                root.focusWindow(root.selectedAddress);
            else
                root.focusWorkspace(root.selectedWorkspace);
            return true;
        }
        if (key === "left" || key === "right") {
            const list = root.addressesFor(root.selectedWorkspace);
            if (list.length === 0)
                return true;
            const index = list.indexOf(root.selectedAddress);
            const next = index === -1 ? 0 : Math.max(0, Math.min(list.length - 1, index + (key === "left" ? -1 : 1)));
            root.select(root.selectedWorkspace, list[next]);
            return true;
        }
        if (key === "up" || key === "down") {
            const rowIndex = root.rowIds.indexOf(root.selectedWorkspace);
            const nextRow = Math.max(0, Math.min(root.rowIds.length - 1, rowIndex + (key === "up" ? -1 : 1)));
            const workspaceId = root.rowIds[nextRow];
            const current = root.selectedAddress !== "" ? root.tileRect(root.selectedAddress) : Qt.rect(0, 0, root.frameWidth, 0);
            root.select(workspaceId, root.nearestIn(workspaceId, current.x + current.width / 2));
            return true;
        }
        return false;
    }

    readonly property bool navigable: root.visible && GlobalStates.overviewOpen && Hyprland.focusedMonitor === root.monitor
    onNavigableChanged: {
        if (root.navigable)
            GlobalStates.scrollingOverviewNavigator = root;
        else if (GlobalStates.scrollingOverviewNavigator === root)
            GlobalStates.scrollingOverviewNavigator = null;
    }
    Component.onDestruction: {
        if (GlobalStates.scrollingOverviewNavigator === root)
            GlobalStates.scrollingOverviewNavigator = null;
    }

    /**
     * The active row's frame, for the background to zoom onto. Measured
     * without the host's entrance transform: the zoom must aim at where the
     * row settles, not at where it is while it rises into place.
     */
    function publishTarget(rect) {
        if (root.screenName !== "")
            GlobalStates.setScrollingOverviewTarget(root.screenName, rect);
    }

    // ── Actions ─────────────────────────────────────────────────────────────
    /**
     * Closing waits for Hyprland to report the new workspace: the background
     * zooms out of the active row with captures of the active workspace, and
     * closing first would zoom out of the old one and then cut to the new.
     */
    property int pendingWorkspace: -1

    function closeInto(workspaceId) {
        if (workspaceId === root.activeWorkspaceId || workspaceId <= 0) {
            GlobalStates.overviewOpen = false;
            return;
        }
        root.pendingWorkspace = workspaceId;
        pendingCloseFallback.restart();
    }

    function finishPendingClose() {
        pendingCloseFallback.stop();
        root.pendingWorkspace = -1;
        GlobalStates.overviewOpen = false;
    }

    Timer {
        id: pendingCloseSettle
        // The transition layer needs a compositor frame of the new workspace's captures.
        interval: 48
        onTriggered: root.finishPendingClose()
    }
    Timer {
        id: pendingCloseFallback
        interval: 400
        onTriggered: root.finishPendingClose()
    }

    function focusWindow(address) {
        const workspaceId = HyprlandData.windowByAddress[address]?.workspace?.id ?? -1;
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`);
        root.closeInto(workspaceId);
    }

    function focusWorkspace(workspaceId) {
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${workspaceId} })`);
        root.closeInto(workspaceId);
    }

    function closeWindow(address) {
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${address}" })`);
    }

    // ── Drag and drop ───────────────────────────────────────────────────────
    property bool dragging: false
    property string dragAddress: ""
    property int dragWorkspace: -1
    property string dropType: ""
    property int dropWorkspace: -1
    property string dropAddress: ""

    function beginDrag(tile, grabPoint) {
        root.dragAddress = tile.address;
        root.dragWorkspace = tile.workspaceId;
        dragGhost.toplevel = tile.toplevel;
        dragGhost.iconSource = tile.iconSource;
        // Smaller than the tile, so the target it hovers stays readable.
        const shrink = Math.min(0.6, 240 / Math.max(1, tile.width));
        dragGhost.width = Math.round(tile.width * shrink);
        dragGhost.height = Math.round(tile.height * shrink);
        dragGhost.grabPoint = Qt.point(grabPoint.x * shrink, grabPoint.y * shrink);
        const pointer = tile.mapToItem(root, grabPoint.x, grabPoint.y);
        dragGhost.x = pointer.x - dragGhost.grabPoint.x;
        dragGhost.y = pointer.y - dragGhost.grabPoint.y;
        dragGhost.pointerY = pointer.y;
        root.clearDropTargetAll();
        root.dragging = true;
    }

    function moveDrag(point) {
        dragGhost.x = point.x - dragGhost.grabPoint.x;
        dragGhost.y = point.y - dragGhost.grabPoint.y;
        dragGhost.pointerY = point.y;
    }

    function setDropTarget(type, workspaceId, address) {
        if (!root.dragging)
            return;
        root.dropType = type;
        root.dropWorkspace = workspaceId;
        root.dropAddress = address;
    }

    function clearDropTarget(type, address) {
        if (root.dropType === type && root.dropAddress === address) {
            root.dropType = "";
            root.dropWorkspace = -1;
            root.dropAddress = "";
        }
    }

    function clearDropTargetAll() {
        root.dropType = "";
        root.dropWorkspace = -1;
        root.dropAddress = "";
    }

    function endDrag() {
        const source = root.dragAddress;
        const fromWorkspace = root.dragWorkspace;
        const type = root.dropType;
        const targetWorkspace = root.dropWorkspace;
        const targetAddress = root.dropAddress;
        root.cancelDrag();
        if (source === "")
            return;
        if (type === "window" && targetAddress !== "" && targetAddress !== source) {
            if (targetWorkspace !== fromWorkspace)
                Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${targetWorkspace}, follow = false, window = "address:${source}" })`);
            Hyprland.dispatch(`hl.dsp.window.swap({ target = "address:${targetAddress}", window = "address:${source}" })`);
        } else if (type === "workspace" && targetWorkspace > 0 && targetWorkspace !== fromWorkspace) {
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${targetWorkspace}, follow = false, window = "address:${source}" })`);
        } else {
            return;
        }
        refreshAfterDrop.restart();
    }

    function cancelDrag() {
        root.dragging = false;
        root.dragAddress = "";
        root.dragWorkspace = -1;
        dragGhost.toplevel = null;
        root.clearDropTargetAll();
    }

    Timer {
        id: refreshAfterDrop
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        onTriggered: HyprlandData.updateWindowList()
    }

    // Holding a window near the faded ends scrolls towards them.
    Timer {
        interval: 16
        repeat: true
        running: root.dragging && (dragGhost.pointerY < root.regionTop + 72 || dragGhost.pointerY > root.regionBottom - 72)
        onTriggered: {
            const up = dragGhost.pointerY < root.regionTop + 72;
            scrollAnimation.stop();
            root.scrollSlot = Math.max(0, Math.min(root.scrollMax, root.scrollSlot + (up ? -0.03 : 0.03)));
            snapTimer.restart();
        }
    }

    // ── Opening ─────────────────────────────────────────────────────────────
    function resetView() {
        root.cancelDrag();
        root.selectedAddress = "";
        root.selectedWorkspace = -1;
        root.keyboardSelecting = false;
        for (let i = 0; i < rowRepeater.count; i++)
            rowRepeater.itemAt(i)?.panBy(-(rowRepeater.itemAt(i)?.pan ?? 0), true);
        root.scrollToWorkspace(root.activeWorkspaceId, false);
    }

    Component.onCompleted: {
        root.resetView();
        if (root.navigable)
            GlobalStates.scrollingOverviewNavigator = root;
    }
    onActiveWorkspaceIdChanged: {
        if (root.pendingWorkspace !== -1) {
            // Leaving from the row that was picked, where it is on screen.
            if (root.activeWorkspaceId === root.pendingWorkspace)
                pendingCloseSettle.restart();
            return;
        }
        if (GlobalStates.overviewOpen)
            root.scrollToWorkspace(root.activeWorkspaceId, true);
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) {
                root.resetView();
            } else {
                root.cancelDrag();
                pendingCloseSettle.stop();
                pendingCloseFallback.stop();
                root.pendingWorkspace = -1;
            }
        }
    }

    // ── Scene ───────────────────────────────────────────────────────────────
    Item {
        id: backdrop
        anchors.fill: parent
        property real reveal: root.activeFullscreen && root.showing ? 1 : 0
        opacity: backdrop.reveal
        visible: opacity > 0
        Behavior on reveal {
            enabled: !root.animationsDisabled
            animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
        }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
        }
        Image {
            id: backdropWallpaper
            anchors.fill: parent
            visible: false
            source: backdrop.visible ? root.wallpaperSource : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: root.wallpaperDecodeSize
            asynchronous: true
            cache: true
        }
        MultiEffect {
            anchors.fill: parent
            source: backdropWallpaper
            visible: backdropWallpaper.status === Image.Ready
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            autoPaddingEnabled: false
        }
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.24
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: GlobalStates.overviewOpen = false
        onWheel: wheel => root.handleWheel(wheel)
    }

    Item {
        id: rows
        anchors.fill: parent

        // Rows fade out before they reach the search, and towards the bottom edge.
        layer.enabled: true
        layer.effect: EdgeFadeMask {
            readonly property real extent: Math.max(1, rows.height)
            startClear: Math.max(0, Math.min(1, root.regionTop / extent))
            startSolid: Math.max(startClear, Math.min(1, (root.regionTop + root.fadeSize) / extent))
            endClear: Math.max(startSolid, Math.min(1, root.regionBottom / extent))
            endSolid: Math.max(startSolid, Math.min(endClear, (root.regionBottom - root.fadeSize) / extent))
        }

        Repeater {
            id: rowRepeater
            model: ScriptModel {
                values: root.rowIds
            }
            delegate: ScrollingWorkspaceRow {
                id: row
                required property int modelData
                required property int index
                overview: root
                workspaceId: modelData
                addresses: root.addressesFor(modelData)
                slot: index
                width: rows.width

                // Rows slide when one appears or goes; the scroll itself is not animated here.
                property real slotPosition: index
                property bool slotSettled: false
                Behavior on slotPosition {
                    enabled: row.slotSettled && !root.animationsDisabled
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
                onIndexChanged: row.slotPosition = index
                // A row that appears while the overview is up just arrives.
                Component.onCompleted: {
                    Qt.callLater(() => row.slotSettled = true);
                    if (root.showing)
                        row.playReveal(true, 60);
                }

                y: root.rowTop(row.slotPosition)
                shown: y + height > root.regionTop - root.pitch * 0.25 && y < root.regionBottom + root.pitch * 0.25
                visible: row.shown
            }
        }
    }

    // What follows the pointer while a window is dragged.
    Item {
        id: dragGhost
        property var toplevel: null
        property string iconSource: ""
        property point grabPoint: Qt.point(0, 0)
        property real pointerY: 0
        visible: root.dragging
        z: 100

        Drag.active: root.dragging
        Drag.hotSpot.x: dragGhost.grabPoint.x
        Drag.hotSpot.y: dragGhost.grabPoint.y

        StyledRectangularShadow {
            target: ghostSurface
            radius: Appearance.rounding.normal
            blur: 32
            opacity: 0.5
            offset: Qt.vector2d(0, 8)
        }

        Item {
            id: ghostSurface
            anchors.fill: parent
            opacity: 0.92
            layer.enabled: true
            layer.effect: OverviewRoundedMask {
                cornerRadius: Math.min(Appearance.rounding.normal, dragGhost.width / 4, dragGhost.height / 4)
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer2
            }
            IconImage {
                anchors.centerIn: parent
                implicitSize: Math.round(Math.min(dragGhost.width, dragGhost.height) * 0.32)
                source: dragGhost.iconSource
                visible: !ghostPreview.hasContent
            }
            ScreencopyView {
                id: ghostPreview
                anchors.fill: parent
                captureSource: (root.dragging && Config.options.overview.showWindowPreviews) ? dragGhost.toplevel : null
                live: root.dragging
            }
        }
    }
}
