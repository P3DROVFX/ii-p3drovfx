pragma ComponentBehavior: Bound

// OverviewWindowTransition.qml
// ----------------------------
// Renders scaled ScreencopyView of windows on the active workspace
// in sync with the wallpaper zoom animation (GNOME-like overview effect).
//
// Architecture:
//   • One PanelWindow per screen (WlrLayer.Top, no_anim via rules)
//   • When overview opens: shows window captures and follows the per-monitor
//     OverviewBackgroundController progress/transform when the selected preset
//     supports window transitions.
//   • When workspace switches (while overview is open): slides captures out and
//     brings in captures of the next workspace — matching the workspace slide
//     animation direction.
//   • On overview close: restores the captured real windows and keeps this
//     layer mapped through the asynchronous handoff, then hides.
//
// Flicker prevention:
//   • Each tile owns one Toplevel screencopy. The configured live flag is
//     passed through directly; frozen previews are captured once and held.
//   • captureSource is set BEFORE setting visible=true (QML binding order).
//   • The controller's progress is the only transition clock.

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.overview
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: transitionScope
    // Every motion in the overview and its panels answers to one switch:
    // Settings -> Overview -> Animation style -> None.
    readonly property bool animationsDisabled: Config.options.overview.animationStyle === "none"

    readonly property bool featureEnabled:
        !GlobalStates.overviewUsesAppDrawer &&
        Config.options.background.zoomOutEnabled &&
        Config.options.background.windowZoomOnOverview

    // Hyprland window rules are cumulative. The old handoff created one
    // anonymous no_anim rule on open and a different opacity rule on close,
    // leaving no_anim active for every future window. Keep one named rule in
    // Hyprland's Lua VM and toggle that same handle instead.
    property bool windowHandoffDesiredActive: false
    property bool windowHandoffCommandQueued: false

    function windowHandoffScript(active) {
        const globalRef = "_G.__ii_overview_window_handoff_rule";
        let script = "local rule = " + globalRef + "; ";
        if (active) {
            script += transitionScope.restoreRuleOffScript + "; ";
            script += "local ok = false; if rule ~= nil then ok = pcall(function() rule:set_enabled(true) end) end; ";
            script += "if not ok then local createdOk, created = pcall(function() return hl.window_rule({ name = 'quickshell-overview-window-handoff', enabled = true, match = { class = '.*' }, opacity = '0.0 0.0', no_anim = true }) end); if createdOk and created ~= nil then " + globalRef + " = created else error(tostring(created)) end end";
        } else {
            // Restoring: a second named rule with only no_anim is on while the
            // hiding rule goes away, so the windows' alpha returns at once.
            // Without it Hyprland faded it in over fadeSwitch (global, 800 ms)
            // and the captures left while the windows were still see-through.
            script += "local warp = " + transitionScope.restoreRuleRef + "; local warpOk = false; ";
            script += "if warp ~= nil then warpOk = pcall(function() warp:set_enabled(true) end) end; ";
            script += "if not warpOk then local createdOk, created = pcall(function() return hl.window_rule({ name = 'quickshell-overview-window-restore', enabled = true, match = { class = '.*' }, no_anim = true }) end); if createdOk and created ~= nil then " + transitionScope.restoreRuleRef + " = created end end; ";
            script += "if rule ~= nil then local ok = pcall(function() rule:set_enabled(false) end); if not ok then " + globalRef + " = nil end end";
        }
        return script;
    }

    readonly property string restoreRuleRef: "_G.__ii_overview_window_restore_rule"
    readonly property string restoreRuleOffScript: "local warp = " + transitionScope.restoreRuleRef
        + "; if warp ~= nil then pcall(function() warp:set_enabled(false) end) end"
    // The no_anim restore rule only has to outlive the alpha change.
    Timer {
        id: restoreRuleOffTimer
        interval: 150
        onTriggered: {
            if (!transitionScope.windowHandoffDesiredActive)
                Quickshell.execDetached(["hyprctl", "eval", transitionScope.restoreRuleOffScript]);
        }
    }
    onWindowHandoffAppliedChanged: {
        if (transitionScope.windowHandoffApplied && !transitionScope.windowHandoffDesiredActive)
            restoreRuleOffTimer.restart();
    }

    function runWindowHandoffCommand() {
        windowHandoffProcess.command = ["hyprctl", "eval", transitionScope.windowHandoffScript(transitionScope.windowHandoffDesiredActive)];
        windowHandoffProcess.running = true;
    }

    // True once Hyprland has taken the last requested state: the open waits on
    // it to start the zoom, the close to drop the captures.
    property bool windowHandoffApplied: false

    function setWindowHandoffActive(active) {
        transitionScope.windowHandoffDesiredActive = active;
        transitionScope.windowHandoffApplied = false;
        if (windowHandoffProcess.running) {
            transitionScope.windowHandoffCommandQueued = true;
            return;
        }
        transitionScope.runWindowHandoffCommand();
    }

    function forceWindowHandoffInactive() {
        transitionScope.windowHandoffDesiredActive = false;
        transitionScope.windowHandoffCommandQueued = false;
        // Do not let an in-flight enable finish after the teardown cleanup.
        if (windowHandoffProcess.running)
            windowHandoffProcess.running = false;
        Quickshell.execDetached(["hyprctl", "eval", transitionScope.windowHandoffScript(false) + "; " + transitionScope.restoreRuleOffScript]);
    }

    Process {
        id: windowHandoffProcess
        onExited: {
            if (!transitionScope.windowHandoffCommandQueued) {
                transitionScope.windowHandoffApplied = true;
                return;
            }
            transitionScope.windowHandoffCommandQueued = false;
            transitionScope.runWindowHandoffCommand();
        }
    }

    Component.onCompleted: {
        // Recover if Quickshell was restarted while the overview handoff rule
        // was active in the still-running compositor.
        if (!GlobalStates.classicOverviewOpen)
            transitionScope.setWindowHandoffActive(false);
    }
    Component.onDestruction: transitionScope.forceWindowHandoffInactive()

    IpcHandler { // DRAGTEST
        target: "realGnomeDragTest" // DRAGTEST
        function shift(n: int): void { GlobalStates.realGnomeDragShift = n; } // DRAGTEST
        function commit(ws: int): void { GlobalStates.realGnomeDragCommitWs = ws; Hyprland.dispatch(`hl.dsp.focus({ workspace = ${ws} })`); } // DRAGTEST
    } // DRAGTEST

    Variants {
        id: transitionVariants
        model: Quickshell.screens

        PanelWindow {
            id: tRoot
            required property var modelData

            // ── Layer plumbing ──────────────────────────────────────────────
            screen: modelData
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:overviewWindowTransition"
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }

            // ── Monitor / workspace state ───────────────────────────────────
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            // Do not compare nullable Hyprland monitor objects here. During
            // screen hotplug/reload `monitorFor()` can be null, and
            // `undefined == undefined` would activate every transition layer.
            readonly property string screenName: modelData ? modelData.name : ""
            readonly property string focusedMonitorName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
            readonly property bool monitorFocused: Quickshell.screens.length <= 1
                || (screenName !== "" && focusedMonitorName !== "" && screenName === focusedMonitorName)
            readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 0

            readonly property bool barVertical: BarPlacement.vertical
            readonly property bool barBottom: BarPlacement.bottom
            // Keep the transition's transform origin identical to the bar's
            // compositor reservation.  Appearance.sizes.barHeight includes
            // two floating gaps and therefore cannot be used as one edge's
            // inset when the bar is horizontal.
            readonly property real barSize: barVertical
                ? Appearance.sizes.baseVerticalBarWidth + (BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                : Appearance.sizes.baseBarHeight + (BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
            readonly property int gap: Appearance.gapsOut

            readonly property real padLeft: barVertical && !barBottom ? barSize : gap
            readonly property real padRight: barVertical && barBottom ? barSize : gap
            readonly property real padTop: !barVertical && !barBottom ? barSize : gap
            readonly property real padBottom: !barVertical && barBottom ? barSize : gap

            readonly property real scaleOriginX: padLeft + (tRoot.screen.width - padLeft - padRight) / 2
            readonly property real scaleOriginY: padTop + (tRoot.screen.height - padTop - padBottom) / 2
            readonly property var overviewController: GlobalStates.overviewBackgroundControllerFor(tRoot.screen ? tRoot.screen.name : "")
            readonly property var monitorData: (HyprlandData.monitors ?? []).find(candidate => Number(candidate?.id) === Number(tRoot.monitor?.id)) ?? null
            readonly property string visibleSpecialWorkspaceName: {
                const name = String(tRoot.monitorData?.specialWorkspace?.name ?? "");
                return name.toLowerCase().indexOf("special:") === 0 ? name.slice(8) : name;
            }
            // A scratchpad is a special workspace drawn over the monitor's
            // normal workspace. Keep it in the same snapshot set so Settings
            // and scratchpad windows use the exact same path as regular apps.
            readonly property var visibleWorkspaceIds: {
                const ids = [];
                const normalId = Number(tRoot.displayedWsId);
                if (isFinite(normalId) && normalId > 0)
                    ids.push(normalId);

                const special = tRoot.monitorData?.specialWorkspace;
                const specialId = Number(special?.id ?? 0);
                if (special?.name && specialId !== 0 && isFinite(specialId) && ids.indexOf(specialId) < 0)
                    ids.push(specialId);
                return ids;
            }
            readonly property bool isGnomeLike: overviewController
                ? overviewController.isGnomeLike
                : (Config.options.background.overviewBackgroundStyle === "gnome"
                    || Config.options.background.overviewBackgroundStyle === "real-gnome"
                    || (Config.options.background.overviewBackgroundStyle === ""
                        && Config.options.background.zoomOutStyle === 0))
            // ── Real Gnome ──────────────────────────────────────────────────
            // GNOME Shell's window picker on top of the Gnome-like zoom: the
            // windows spread into a non-overlapping grid inside the plane,
            // the neighbouring workspaces wait at its edges and the slide is
            // clipped to the plane.
            readonly property bool isRealGnome: tRoot.isGnomeLike && !!overviewController && overviewController.isRealGnome
            // Real position -> picker slot, on the same clock as the zoom.
            readonly property real pickerProgress: tRoot.isRealGnome && overviewController
                ? Math.max(0, Math.min(1, overviewController.progress)) : 0
            readonly property real pickerFinalScale: overviewController ? overviewController.realGnomeScale : 0.85
            readonly property real pickerSpacing: 28
            property var slot0Layout: ({})
            property var slot1Layout: ({})
            // While a search owns the overview the displayed workspace's windows
            // slide out of its plane, away from the search (down with the bar on
            // top, up with it at the bottom), clipped by the plane's edge; the plane
            // and its neighbours stay. The island keeps its query in LauncherSearch,
            // the overview in GlobalStates.
            readonly property bool searchOwnsOverview: GlobalStates.activeSearchQuery !== "" || LauncherSearch.query !== ""
                || GlobalStates.searchPanelActive
            property real searchSlide: tRoot.isRealGnome && tRoot.searchOwnsOverview ? 1.0 : 0.0
            Behavior on searchSlide {
                enabled: !transitionScope.animationsDisabled
                NumberAnimation {
                    duration: Math.round(Math.max(1, Math.min(10, Number(Config.options.appearance.appLaunchAnimation.speed) || 4))
                        * 100 * Appearance.animMultiplier)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                }
            }
            readonly property real searchSlideOffset: tRoot.searchSlide
                * (tRoot.barBottom && !tRoot.barVertical ? -1 : 1)
                * (tRoot.height * tRoot.captureScale + tRoot.pickerSpacing)
            readonly property bool sliding: tRoot.transitionProgress < 1.0
            readonly property bool pickerSettled: tRoot.isRealGnome && tRoot.pickerProgress >= 0.999 && !tRoot.sliding
            /**
             * Real Gnome's workspace strip. Every workspace sits one step (plane
             * width + gap) from the next, and `stripCenter` is the workspace the
             * plane shows - fractional while a switch slides. The window slots
             * and the neighbouring cards are both placed from it, so the strip
             * moves as one piece, and a switch arriving mid-slide continues
             * from wherever the strip is.
             */
            property int slideFromWs: 0
            property int slideToWs: 0
            property real slideFromCenter: 0
            readonly property real stripCenter: tRoot.sliding && tRoot.slideToWs > 0
                ? tRoot.slideFromCenter + (tRoot.slideToWs - tRoot.slideFromCenter) * tRoot.transitionProgress
                : tRoot.displayedWsId + tRoot.dragCenterOffset

            // ── Drag preview ────────────────────────────────────────────────
            // A window held at the plane's edge previews the neighbouring
            // workspace by moving the strip only (RealGnomeWindowPicker); the
            // drop switches for real, and the switch then starts from where the
            // strip already is, so nothing slides twice.
            property real dragCenterOffset: 0
            property bool dragOffsetAnimated: true
            property int pendingDragShift: 0
            Behavior on dragCenterOffset {
                enabled: tRoot.dragOffsetAnimated && !transitionScope.animationsDisabled
                NumberAnimation {
                    duration: Math.round(Math.max(1, Math.min(10, Number(Config.options.appearance.appLaunchAnimation.speed) || 4))
                        * 100 * Appearance.animMultiplier)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
                }
            }
            function applyDragShift() {
                const shift = GlobalStates.realGnomeDragShift;
                if (!tRoot.isRealGnome || !tRoot.monitorFocused || tRoot.sliding)
                    return;
                if (shift !== 0) {
                    tRoot.pendingDragShift = shift;
                    tRoot.beginPlaneHandover();
                    if (tRoot.planeHandedOver)
                        tRoot.dragCenterOffset = shift;
                } else if (GlobalStates.realGnomeDragCommitWs <= 0) {
                    tRoot.pendingDragShift = 0;
                    tRoot.dragCenterOffset = 0;
                    dragSettleTimer.restart();
                }
            }
            onPlaneHandedOverChanged: {
                if (tRoot.planeHandedOver && tRoot.pendingDragShift !== 0 && !tRoot.sliding)
                    tRoot.dragCenterOffset = tRoot.pendingDragShift;
            }
            // Back at the middle with nothing dropped: the plane takes over again.
            Timer {
                id: dragSettleTimer
                interval: Math.round(Math.max(1, Math.min(10, Number(Config.options.appearance.appLaunchAnimation.speed) || 4))
                    * 100 * Appearance.animMultiplier) + 40
                onTriggered: {
                    if (GlobalStates.realGnomeDragShift === 0 && !tRoot.sliding && tRoot.dragCenterOffset === 0)
                        tRoot.returnPlane();
                }
            }
            // A drop whose switch never arrives slides the strip back.
            Timer {
                id: dragCommitFallbackTimer
                interval: 600
                onTriggered: {
                    if (GlobalStates.realGnomeDragCommitWs <= 0)
                        return;
                    GlobalStates.realGnomeDragCommitWs = 0;
                    GlobalStates.realGnomeDragShift = 0;
                    tRoot.applyDragShift();
                }
            }
            Connections {
                target: GlobalStates
                function onRealGnomeDragShiftChanged() { tRoot.applyDragShift(); }
                function onRealGnomeDragCommitWsChanged() {
                    if (GlobalStates.realGnomeDragCommitWs > 0 && tRoot.monitorFocused)
                        dragCommitFallbackTimer.restart();
                }
            }
            readonly property int workspacesPerGroup: Math.max(1, (Config.options.overview.rows ?? 2) * (Config.options.overview.columns ?? 5))
            // The workspaces on the strip: two either side of an anchor that
            // follows the displayed workspace only once a slide has settled,
            // plus its direct neighbours and everything a slide passes.
            // Resident while the style is on, and wide enough that a switch
            // never builds a card mid-slide: building one (captures, wallpaper
            // decode) stalled the first frames of the slide, and building them
            // on every open stalled its first ~200 ms. Their captures still drop
            // while the layer is hidden.
            property int stripAnchorWs: 0

            /**
             * While a workspace slides, the strip's cards carry every workspace -
             * the displayed one included, with the plane's exact wallpaper - and
             * the background's plane steps aside, so the wallpaper moves with its
             * windows instead of standing still in the middle. At rest only the
             * parts beside the plane are shown. The handover always overlaps:
             * the card is on screen before the plane hides and stays until it is
             * back, so the two surfaces never leave a frame without either.
             */
            property bool stripFullMode: false
            property bool planeHandedOver: false
            readonly property var planeWallpaper: GlobalStates.realGnomePlaneWallpapers[tRoot.screenName] ?? null
            Timer {
                id: planeHideTimer
                interval: 40
                onTriggered: {
                    if (!tRoot.stripFullMode)
                        return;
                    GlobalStates.realGnomePlaneHiddenScreen = tRoot.screenName;
                    tRoot.planeHandedOver = true;
                }
            }
            Timer {
                id: planeReturnTimer
                interval: 60
                onTriggered: {
                    if (!tRoot.sliding)
                        tRoot.stripFullMode = false;
                }
            }
            function beginPlaneHandover() {
                planeReturnTimer.stop();
                if (tRoot.planeHandedOver)
                    return;
                tRoot.stripFullMode = true;
                planeHideTimer.restart();
            }
            function returnPlane() {
                planeHideTimer.stop();
                tRoot.planeHandedOver = false;
                if (GlobalStates.realGnomePlaneHiddenScreen === tRoot.screenName)
                    GlobalStates.realGnomePlaneHiddenScreen = "";
                if (tRoot.stripFullMode)
                    planeReturnTimer.restart();
            }
            function resetPlaneHandover() {
                tRoot.dragOffsetAnimated = false;
                tRoot.dragCenterOffset = 0;
                tRoot.dragOffsetAnimated = true;
                tRoot.pendingDragShift = 0;
                planeHideTimer.stop();
                planeReturnTimer.stop();
                tRoot.planeHandedOver = false;
                tRoot.stripFullMode = false;
                if (GlobalStates.realGnomePlaneHiddenScreen === tRoot.screenName)
                    GlobalStates.realGnomePlaneHiddenScreen = "";
            }
            Timer {
                id: stripAnchorTimer
                interval: 220
                onTriggered: {
                    if (!tRoot.sliding)
                        tRoot.stripAnchorWs = tRoot.displayedWsId;
                }
            }
            readonly property var stripWorkspaces: {
                if (!tRoot.isRealGnome || !tRoot.monitorFocused || tRoot.displayedWsId <= 0)
                    return [];
                const id = tRoot.displayedWsId;
                const anchor = tRoot.stripAnchorWs > 0 ? tRoot.stripAnchorWs : id;
                const groupStart = Math.floor((anchor - 1) / tRoot.workspacesPerGroup) * tRoot.workspacesPerGroup + 1;
                const groupEnd = groupStart + tRoot.workspacesPerGroup - 1;
                const previewed = id + Math.round(tRoot.pendingDragShift);
                let lo = Math.max(1, Math.min(Math.max(groupStart, anchor - 2), id - 1, previewed - 1));
                let hi = Math.max(Math.min(groupEnd, anchor + 2), id + 1, previewed + 1);
                if (tRoot.sliding && tRoot.slideToWs > 0) {
                    lo = Math.max(1, Math.min(lo, tRoot.slideFromWs, Math.floor(tRoot.slideFromCenter) - 1));
                    hi = Math.max(hi, tRoot.slideFromWs, Math.ceil(tRoot.slideFromCenter) + 1);
                }
                const ids = [];
                for (let ws = lo; ws <= hi && ids.length < 24; ws++)
                    ids.push(ws);
                return ids;
            }

            /**
             * GNOME's window picker layout, in the slot's unscaled coordinates.
             *
             * Windows are taken top to bottom, split into rows of similar total
             * width and scaled together as large as the plane allows (never above
             * their real size); each row is centred, each window centred in its
             * row. Every row count is tried and the one with the largest scale
             * wins, fewer rows on a tie.
             */
            function computePickerLayout(list) {
                const result = {};
                const items = [];
                for (const toplevel of list) {
                    const win = tRoot.clientForToplevel(toplevel);
                    const key = tRoot.normalizedAddress(toplevel?.HyprlandToplevel?.address);
                    if (!win || key === "")
                        continue;
                    const w = Number(win.size?.[0] ?? 0);
                    const h = Number(win.size?.[1] ?? 0);
                    if (w <= 0 || h <= 0)
                        continue;
                    items.push({
                        key: key,
                        x: Math.max((win.at?.[0] ?? 0) - (tRoot.monitorData?.x ?? 0), 0),
                        y: Math.max((win.at?.[1] ?? 0) - (tRoot.monitorData?.y ?? 0), 0),
                        w: w,
                        h: h
                    });
                }
                if (items.length === 0)
                    return result;

                const finalScale = Math.max(0.1, tRoot.pickerFinalScale);
                // Spacing and padding are on-screen sizes at full open.
                const spacing = tRoot.pickerSpacing / finalScale;
                const pad = 40 / finalScale;
                const labelRoom = 30 / finalScale;
                const areaX = pad;
                const areaY = pad;
                const areaW = Math.max(1, tRoot.screen.width - pad * 2);
                const areaH = Math.max(1, tRoot.screen.height - pad * 2 - labelRoom);

                items.sort((a, b) => ((a.y + a.h / 2) - (b.y + b.h / 2)) || (a.x - b.x));
                const totalWidth = items.reduce((sum, item) => sum + item.w, 0);
                let best = null;
                for (let rowCount = 1; rowCount <= items.length; rowCount++) {
                    const rows = [];
                    const target = totalWidth / rowCount;
                    let row = [];
                    let acc = 0;
                    for (const item of items) {
                        row.push(item);
                        acc += item.w;
                        if (acc >= target && rows.length < rowCount - 1) {
                            rows.push(row);
                            row = [];
                            acc = 0;
                        }
                    }
                    if (row.length > 0)
                        rows.push(row);
                    let scale = 1.0;
                    let heights = 0;
                    for (const r of rows) {
                        r.sort((a, b) => a.x - b.x);
                        const widths = r.reduce((sum, item) => sum + item.w, 0);
                        scale = Math.min(scale, (areaW - spacing * (r.length - 1)) / widths);
                        heights += r.reduce((m, item) => Math.max(m, item.h), 0);
                    }
                    scale = Math.min(scale, (areaH - spacing * (rows.length - 1)) / heights);
                    if (!best || scale > best.scale + 0.0001)
                        best = { rows: rows, scale: Math.max(0.01, scale) };
                }

                const scale = best.scale;
                const rowHeights = best.rows.map(r => r.reduce((m, item) => Math.max(m, item.h), 0) * scale);
                const blockHeight = rowHeights.reduce((sum, h) => sum + h, 0) + spacing * (best.rows.length - 1);
                let y = areaY + (areaH - blockHeight) / 2;
                best.rows.forEach((r, index) => {
                    const rowWidth = r.reduce((sum, item) => sum + item.w * scale, 0) + spacing * (r.length - 1);
                    let x = areaX + (areaW - rowWidth) / 2;
                    for (const item of r) {
                        const w = item.w * scale;
                        const h = item.h * scale;
                        result[item.key] = Qt.rect(x, y + (rowHeights[index] - h) / 2, w, h);
                        x += w + spacing;
                    }
                    y += rowHeights[index] + spacing;
                });
                return result;
            }

            function relayoutPicker() {
                if (!tRoot.isRealGnome)
                    return;
                const layout = tRoot.computePickerLayout(tRoot.frozenToplevels);
                if (tRoot.currentSlot === 0)
                    tRoot.slot0Layout = layout;
                else
                    tRoot.slot1Layout = layout;
                pickerPublishTimer.restart();
            }

            function toplevelsOnWorkspace(workspaceId) {
                if (workspaceId <= 0)
                    return [];
                const clients = HyprlandData.windowByAddress ?? ({});
                const monitorId = Number(tRoot.monitor?.id);
                return (ToplevelManager.toplevels.values ?? []).filter(toplevel => {
                    const win = tRoot.clientForToplevel(toplevel, clients);
                    return win && Number(win.workspace?.id) === workspaceId
                        && (!isFinite(monitorId) || Number(win.monitor) === monitorId || Number(win.monitor) < 0);
                });
            }

            // The overview's input layer reads each window's slot at full
            // open (screen coordinates) for hover, click and close.
            Timer {
                id: pickerPublishTimer
                interval: 16
                onTriggered: tRoot.publishPickerSlots()
            }
            function publishPickerSlots() {
                if (tRoot.screenName === "")
                    return;
                if (!tRoot.isRealGnome || !tRoot.monitorFocused || !tRoot.shouldBeActive || tRoot.sliding || !overviewController) {
                    if ((GlobalStates.realGnomePickerSlots[tRoot.screenName] ?? []).length > 0)
                        GlobalStates.setRealGnomePickerSlots(tRoot.screenName, []);
                    return;
                }
                const layout = tRoot.currentSlot === 0 ? tRoot.slot0Layout : tRoot.slot1Layout;
                const s = tRoot.pickerFinalScale;
                const ox = overviewController.scaleOriginX;
                const oy = overviewController.scaleOriginY;
                const slots = [];
                for (const key in layout) {
                    const r = layout[key];
                    const win = HyprlandData.windowByAddress?.[key];
                    slots.push({
                        address: key,
                        title: String(win?.title ?? ""),
                        appClass: String(win?.class ?? ""),
                        x: ox + s * (r.x - ox),
                        y: oy + s * (r.y - oy),
                        width: r.width * s,
                        height: r.height * s
                    });
                }
                GlobalStates.setRealGnomePickerSlots(tRoot.screenName, slots);
            }
            onSlidingChanged: {
                pickerPublishTimer.restart();
                if (!tRoot.sliding)
                    stripAnchorTimer.restart();
            }
            onPickerFinalScaleChanged: tRoot.relayoutPicker()
            onIsRealGnomeChanged: {
                tRoot.resetPlaneHandover();
                tRoot.relayoutPicker();
                pickerPublishTimer.restart();
            }
            Connections {
                target: tRoot.overviewController
                ignoreUnknownSignals: true
                function onScaleOriginXChanged() { pickerPublishTimer.restart(); }
                function onScaleOriginYChanged() { pickerPublishTimer.restart(); }
            }

            readonly property bool useWallpaperBackdrop:
                tRoot.shouldBeActive &&
                !tRoot.isGnomeLike &&
                overviewController &&
                overviewController.windowTransitionMode === "scale-with-background" &&
                overviewController.wallpaperPath !== "" &&
                !overviewController.wallpaperSafetyTriggered

            // ── Window freezing logic for anti-flicker reload ───────────────
            property list<var> frozenToplevels: []
            property bool incomingModelReady: true
            // Hyprland can publish several related list/map changes in the
            // same frame. Coalesce them so the expensive workspace filter is
            // evaluated once instead of once per signal.
            property int windowDataRevision: 0

            Timer {
                id: toplevelUpdateTimer
                interval: 16
                repeat: false
                onTriggered: tRoot.refreshToplevels()
            }

            function normalizedAddress(value) {
                const raw = String(value ?? "").trim();
                if (raw === "")
                    return "";
                return raw.toLowerCase().indexOf("0x") === 0 ? "0x" + raw.slice(2) : "0x" + raw;
            }

            function clientForToplevel(toplevel, clients) {
                const raw = String(toplevel?.HyprlandToplevel?.address ?? "").trim();
                if (raw === "")
                    return null;
                const normalized = tRoot.normalizedAddress(raw);
                const clientMap = clients ?? HyprlandData.windowByAddress ?? ({});
                // Quickshell versions differ on whether the address already
                // carries the 0x prefix. Accept both forms without ever
                // producing the invalid 0x0x... key.
                return clientMap[normalized] ?? clientMap[raw] ?? null;
            }

            function scheduleToplevelUpdate() {
                if (!toplevelUpdateTimer.running)
                    toplevelUpdateTimer.start();
            }

            function refreshToplevels() {
                if (tRoot.exitAnimating) {
                    // Freeze completely during exit transition to protect previews from being destroyed by hyprctl reload!
                    return;
                }
                if (!tRoot.shouldBeActive) {
                    tRoot.frozenToplevels = [];
                    tRoot.incomingModelReady = false;
                    return;
                }
                const monitorId = Number(tRoot.monitor?.id);
                const workspaceIds = tRoot.visibleWorkspaceIds;
                if (!isFinite(monitorId) || workspaceIds.length === 0) {
                    tRoot.frozenToplevels = [];
                    tRoot.incomingModelReady = true;
                    tRoot.windowDataRevision++;
                    return;
                }
                const clients = HyprlandData.windowByAddress ?? ({});
                const res = (ToplevelManager.toplevels.values ?? []).filter(toplevel => {
                    const win = tRoot.clientForToplevel(toplevel, clients);
                    if (!win)
                        return false;
                    const workspaceId = Number(win.workspace?.id);
                    const clientMonitorId = Number(win.monitor);
                    const workspaceName = String(win.workspace?.name ?? "");
                    const specialName = tRoot.visibleSpecialWorkspaceName;
                    const isVisibleSpecial = specialName !== ""
                        && (workspaceName === specialName
                            || workspaceName === "special:" + specialName
                            || workspaceName === tRoot.monitorData?.specialWorkspace?.name);
                    return ((isFinite(workspaceId) && workspaceIds.indexOf(workspaceId) >= 0) || isVisibleSpecial)
                        && isFinite(clientMonitorId) && clientMonitorId === monitorId;
                });
                tRoot.frozenToplevels = res;
                // The list is now committed to the incoming Repeater. The
                // slide timer still waits for each visible tile's first frame.
                tRoot.incomingModelReady = true;
                tRoot.windowDataRevision++;
                if (tRoot.isRealGnome)
                    tRoot.relayoutPicker();
            }

            onShouldBeActiveChanged: {
                // Populate the first frame synchronously so mapping the handoff
                // layer never exposes an empty transition surface. Later
                // Hyprland churn is safe to coalesce on the short timer.
                if (tRoot.shouldBeActive)
                    refreshToplevels();
                else
                    scheduleToplevelUpdate();
            }
            onDisplayedWsIdChanged: {
                scheduleToplevelUpdate();
                if (!tRoot.sliding)
                    stripAnchorTimer.restart();
            }
            onMonitorDataChanged: scheduleToplevelUpdate()
            onVisibleWorkspaceIdsChanged: scheduleToplevelUpdate()
            
            Connections {
                target: ToplevelManager.toplevels
                function onValuesChanged() {
                    tRoot.scheduleToplevelUpdate();
                }
            }

            Connections {
                target: HyprlandData
                ignoreUnknownSignals: true
                function onWindowByAddressChanged() {
                    tRoot.scheduleToplevelUpdate();
                }
            }

            Component.onCompleted: {
                scheduleToplevelUpdate();
                if (tRoot.isGnomeLike && tRoot.monitorFocused && GlobalStates.classicOverviewOpen && transitionScope.featureEnabled) {
                    tRoot.isOverviewActive = true;
                    tRoot.beginOpenHandoff();
                }
            }

            // ── Visibility / readiness ──────────────────────────────────────
            // Gnome-like intentionally keeps the original transition state:
            // the layer is mapped by the overview signal, not by the shared
            // preset controller. This prevents a stale capture from staying
            // mapped when the overview surface is already open.
            property bool exitAnimating: false
            property bool isOverviewActive: false

            onExitAnimatingChanged: {
                if (!tRoot.exitAnimating)
                    tRoot.windowDataRevision++;
            }

            onMonitorFocusedChanged: {
                tRoot.resetPlaneHandover();
                if (!tRoot.monitorFocused) {
                    // A transition belongs to the monitor under the pointer.
                    // Tear down its visual state as soon as focus leaves so a
                    // second layer cannot remain mapped on another output.
                    slideStartTimer.stop();
                    exitAnimTimer.stop();
                    if (Quickshell.screens.length === 0 || tRoot.screen !== Quickshell.screens[0]) {
                        openDelayTimer.stop();
                        restoreWindowsTimer.stop();
                    }
                    if (GlobalStates.overviewZoomHeld)
                        GlobalStates.overviewZoomHeld = false;
                    tRoot.exitAnimating = false;
                    tRoot.isOverviewActive = false;
                    tRoot.slideAnimEnabled = false;
                    tRoot.transitionProgress = 1.0;
                    tRoot.outgoingToplevels = [];
                    if (tRoot.activeWsId > 0)
                        tRoot.displayedWsId = tRoot.activeWsId;
                    return;
                }

                if (!GlobalStates.classicOverviewOpen || !transitionScope.featureEnabled)
                    return;

                tRoot.exitAnimating = false;
                tRoot.isOverviewActive = tRoot.isGnomeLike;
                exitAnimTimer.stop();
                restoreWindowsTimer.stop();
                slideStartTimer.stop();
                tRoot.slideAnimEnabled = false;
                tRoot.transitionProgress = 1.0;
                tRoot.outgoingToplevels = [];
                tRoot.displayedWsId = tRoot.activeWsId;
                if (tRoot.isGnomeLike && Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0])
                    tRoot.beginOpenHandoff();
                Qt.callLater(tRoot.scheduleToplevelUpdate);
            }

            // ── Window handoff, driven by events ────────────────────────────
            // Opening: the zoom is held at 0 while the captures get their first
            // frame and Hyprland hides the real windows under them; at 0 the
            // captures cover the windows exactly, so the swap is invisible, and
            // the zoom starts from a settled frame. Before, the zoom ran on its
            // own clock: the windows were hidden 60 ms in (90 ms after an idle
            // pause, when the first capture took 78 ms), so the real window
            // stood still over a zoom already half done, then jumped to the
            // shrunken capture - the stall and the one-frame flicker.
            // Closing: the real windows return when the zoom is exactly back at
            // 0, and the captures leave once Hyprland has shown them. The timers
            // below are only fallbacks.
            readonly property bool isHandoffScreen: Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0]
            property bool openHandoffRequested: false
            property bool closeHandoffPending: false
            readonly property int closeDuration: tRoot.isRealGnome && tRoot.overviewController
                ? tRoot.overviewController.realGnomeCloseDuration
                : Appearance.animation.elementMove.duration

            function beginOpenHandoff() {
                tRoot.openHandoffRequested = false;
                if (tRoot.monitorFocused && !transitionScope.animationsDisabled)
                    GlobalStates.overviewZoomHeld = true;
                openDelayTimer.restart();
                Qt.callLater(tRoot.requestOpenHandoff);
            }
            function requestOpenHandoff() {
                if (tRoot.openHandoffRequested || !tRoot.isGnomeLike || !tRoot.isOverviewActive
                        || !GlobalStates.classicOverviewOpen || !transitionScope.featureEnabled || !tRoot.incomingCapturesReady)
                    return;
                tRoot.openHandoffRequested = true;
                if (tRoot.isHandoffScreen)
                    transitionScope.setWindowHandoffActive(true);
                else
                    tRoot.releaseOpenHold();
            }
            function releaseOpenHold() {
                if (tRoot.monitorFocused && GlobalStates.overviewZoomHeld)
                    GlobalStates.overviewZoomHeld = false;
            }
            function restoreRealWindows() {
                tRoot.closeHandoffPending = false;
                restoreWindowsTimer.stop();
                if (tRoot.isGnomeLike && tRoot.isHandoffScreen)
                    transitionScope.setWindowHandoffActive(false);
            }
            function finishExit() {
                exitAnimTimer.stop();
                exitSettleTimer.stop();
                tRoot.exitAnimating = false;
                tRoot.isOverviewActive = false;
                tRoot.frozenToplevels = [];
                tRoot.outgoingToplevels = [];
            }
            onIncomingCapturesReadyChanged: {
                if (tRoot.incomingCapturesReady)
                    tRoot.requestOpenHandoff();
            }
            Connections {
                target: transitionScope
                function onWindowHandoffAppliedChanged() {
                    if (!transitionScope.windowHandoffApplied)
                        return;
                    if (transitionScope.windowHandoffDesiredActive)
                        tRoot.releaseOpenHold();
                    else if (tRoot.exitAnimating)
                        exitSettleTimer.restart();
                }
            }
            Connections {
                target: tRoot.overviewController
                ignoreUnknownSignals: true
                function onProgressChanged() {
                    if (tRoot.closeHandoffPending && !GlobalStates.classicOverviewOpen
                            && tRoot.overviewController.progress === 0)
                        tRoot.restoreRealWindows();
                }
            }

            Timer {
                id: openDelayTimer
                // Fallback: never hold the zoom longer than this.
                interval: 220
                onTriggered: {
                    if (tRoot.isGnomeLike && tRoot.isHandoffScreen && !tRoot.openHandoffRequested
                            && GlobalStates.classicOverviewOpen) {
                        tRoot.openHandoffRequested = true;
                        transitionScope.setWindowHandoffActive(true);
                    }
                    tRoot.releaseOpenHold();
                }
            }

            Timer {
                id: restoreWindowsTimer
                // Fallback for a close whose progress never lands on 0.
                interval: tRoot.closeDuration + 150
                onTriggered: tRoot.restoreRealWindows()
            }

            Timer {
                id: exitSettleTimer
                // Hyprland draws the restored windows on its next frames.
                interval: 48
                onTriggered: tRoot.finishExit()
            }

            onIsGnomeLikeChanged: {
                if (Quickshell.screens.length === 0 || tRoot.screen !== Quickshell.screens[0])
                    return;
                if (!tRoot.isGnomeLike) {
                    openDelayTimer.stop();
                    restoreWindowsTimer.stop();
                    tRoot.releaseOpenHold();
                    transitionScope.setWindowHandoffActive(false);
                } else if (GlobalStates.classicOverviewOpen && transitionScope.featureEnabled) {
                    tRoot.exitAnimating = false;
                    tRoot.isOverviewActive = tRoot.monitorFocused;
                    exitAnimTimer.stop();
                    restoreWindowsTimer.stop();
                    tRoot.beginOpenHandoff();
                }
            }

            Timer {
                id: exitAnimTimer
                // Fallback: keep the capture mapped through the Hyprland handoff.
                interval: tRoot.closeDuration + 600
                onTriggered: tRoot.finishExit()
            }

            // Gnome follows the legacy global state; modern presets use the
            // semantic controller only when their preset explicitly supports a
            // window transition.
            readonly property bool shouldBeActive:
                transitionScope.featureEnabled &&
                tRoot.monitorFocused &&
                (tRoot.isGnomeLike
                    ? tRoot.isOverviewActive
                    : (overviewController && overviewController.windowTransitionMode !== "none"
                        && (overviewController.active || overviewController.progress > 0.001)))

            readonly property real captureScale: tRoot.isGnomeLike
                ? (overviewController ? overviewController.scale : GlobalStates.overviewZoomScale)
                : (overviewController && overviewController.windowTransitionMode === "scale-with-background"
                    ? overviewController.scale
                    : (overviewController ? 0.98 + 0.02 * overviewController.progress : 1.0))
            // The per-monitor controller owns the usable viewport geometry.
            // The legacy global origin is only a fallback for the brief
            // startup window before that controller is registered; otherwise
            // a top/bottom bar would be ignored by the window captures.
            readonly property real captureOriginX: overviewController ? overviewController.scaleOriginX : tRoot.scaleOriginX
            readonly property real captureOriginY: overviewController ? overviewController.scaleOriginY : tRoot.scaleOriginY
            readonly property real captureTranslateX: !tRoot.isGnomeLike && overviewController && overviewController.windowTransitionMode === "scale-with-background" ? overviewController.translateX : 0
            readonly property real captureTranslateY: !tRoot.isGnomeLike && overviewController && overviewController.windowTransitionMode === "scale-with-background" ? overviewController.translateY : 0
            // With the scrolling layout the captures zoom onto the active row
            // with the wallpaper, then hand over to the overview's own tiles.
            readonly property real captureOpacity: (overviewController && overviewController.scrollingHandedOff)
                ? 0.0
                : (tRoot.isGnomeLike ? 1.0 : (overviewController ? overviewController.progress : 0.0))

            // Mapping a fresh layer surface stalled the GUI thread for
            // 100-200 ms on the first frame of every open (EGL surface and
            // scene graph setup), eating the start of the zoom. Keep the
            // surface mapped while a preset can use it; it holds no input and
            // draws nothing until the transition is active.
            readonly property bool transitionAvailable: transitionScope.featureEnabled
                && (tRoot.isGnomeLike || (overviewController && overviewController.windowTransitionMode !== "none"))
            visible: transitionAvailable
            mask: Region {}

            // ── Workspace switch animation ──────────────────────────────────
            // We detect workspace switches while overview is open and animate
            // the transition between the outgoing and incoming workspaces.
            property int displayedWsId: activeWsId   // lags one frame on switch
            readonly property bool isVertical: Config.options.background.parallax.vertical

            property list<var> outgoingToplevels: []
            // Two capture slots trade the incoming/outgoing roles on every
            // switch. The slot that was on screen keeps its tiles (and their
            // ScreencopyView frames) as the outgoing side; rebuilding them
            // under a second Repeater blanked the outgoing windows for the
            // first frames of the slide.
            property int currentSlot: 0
            property list<var> slot0Toplevels: []
            property list<var> slot1Toplevels: []
            onFrozenToplevelsChanged: {
                if (tRoot.currentSlot === 0)
                    tRoot.slot0Toplevels = tRoot.frozenToplevels;
                else
                    tRoot.slot1Toplevels = tRoot.frozenToplevels;
            }
            onOutgoingToplevelsChanged: {
                if (tRoot.currentSlot === 0)
                    tRoot.slot1Toplevels = tRoot.outgoingToplevels;
                else
                    tRoot.slot0Toplevels = tRoot.outgoingToplevels;
            }

            property real transitionProgress: 1.0
            property int transitionDirection: 1 // 1: next, -1: prev
            property bool slideAnimEnabled: false
            property int slideWaitTicks: 0
            readonly property int maxSlideWaitTicks: 10
            // Move the capture container past the complete viewport. A
            // fractional distance leaves the outermost window visible at the
            // edge, which is especially obvious on ultrawide monitors. The
            // extra elevation margin clears the rounded mask and shadow too.
            // Real Gnome slides the plane's own width plus the gap, so the
            // incoming workspace starts exactly where its peek was.
            readonly property real workspaceSlideDistance: tRoot.isRealGnome
                ? (tRoot.isVertical ? tRoot.height : tRoot.width) * tRoot.captureScale + tRoot.pickerSpacing * 2
                : (tRoot.isVertical ? tRoot.height : tRoot.width)
                    + Appearance.sizes.elevationMargin * 2

            readonly property bool incomingCapturesReady: {
                if (!tRoot.incomingModelReady)
                    return false;
                const repeater = tRoot.currentSlot === 0 ? slot0Repeater : slot1Repeater;
                const expected = tRoot.currentSlot === 0 ? tRoot.slot0Toplevels.length : tRoot.slot1Toplevels.length;
                if (repeater.count !== expected)
                    return false;
                for (let i = 0; i < repeater.count; i++) {
                    const item = repeater.itemAt(i);
                    if (item && !item.captureReady)
                        return false;
                }
                return true;
            }

            Timer {
                id: slideStartTimer
                // Give newly-created incoming tiles a compositor frame before
                // they start moving. This removes the blank/blocked first
                // frames when a workspace switch happens during overview.
                interval: 8
                repeat: false
                onTriggered: {
                    if (!GlobalStates.classicOverviewOpen || !tRoot.shouldBeActive || tRoot.transitionProgress !== 0.0)
                        return;
                    const waiting = !tRoot.incomingCapturesReady || (tRoot.isRealGnome && !tRoot.planeHandedOver);
                    if (waiting && ++tRoot.slideWaitTicks < tRoot.maxSlideWaitTicks) {
                        restart();
                        return;
                    }
                    tRoot.slideAnimEnabled = true;
                    if (transitionScope.animationsDisabled)
                        tRoot.transitionProgress = 1.0;
                    else
                        slideAnim.restart();
                }
            }

            onSlideAnimEnabledChanged: {
                if (!tRoot.slideAnimEnabled)
                    slideAnim.stop();
            }

            // Same timing as Hyprland's own window motion (Settings ->
            // Windows -> app animation: iiAppOpen, speed in tenths of a
            // second), so the slide matches the compositor instead of the
            // abrupt emphasizedDecel start. Explicit animation, not a
            // Behavior: a disabled Behavior keeps a running animation alive
            // and it overwrote the reset of a quick second switch.
            NumberAnimation {
                id: slideAnim
                target: tRoot
                property: "transitionProgress"
                from: 0.0
                to: 1.0
                duration: Math.round(Math.max(1, Math.min(10, Number(Config.options.appearance.appLaunchAnimation.speed) || 4))
                    * 100 * Appearance.animMultiplier)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
            }

            onTransitionProgressChanged: {
                if (transitionProgress === 1.0) {
                    outgoingToplevels = []
                    if (tRoot.isRealGnome) {
                        tRoot.relayoutPicker()
                        tRoot.returnPlane()
                    }
                }
            }

            onActiveWsIdChanged: {
                if (activeWsId <= 0) {
                    // Hyprland can briefly report no active workspace while
                    // settling a switch. Keep the last valid outgoing set and
                    // let the next real id drive the slide; clearing it here
                    // exposed the wallpaper for a frame and forced a jump.
                    return
                }
                if (!tRoot.monitorFocused) {
                    // Keep an unfocused instance in sync without allowing it
                    // to start a visible slide. The focus handler performs a
                    // clean resync when this monitor becomes active again.
                    if (!GlobalStates.classicOverviewOpen || tRoot.displayedWsId <= 0)
                        tRoot.displayedWsId = activeWsId;
                    return;
                }
                if (displayedWsId <= 0) {
                    // Recovering from that same transient monitor state is a
                    // resync, not a visible workspace navigation.
                    displayedWsId = activeWsId
                    outgoingToplevels = []
                    slideAnimEnabled = false
                    slideStartTimer.stop()
                    transitionProgress = 1.0
                    return
                }
                if (!GlobalStates.classicOverviewOpen || (overviewController && overviewController.scrollingLayout)) {
                    // Not in overview — just sync, no animation needed. The
                    // scrolling overview hides these captures while it is open
                    // and zooms out of the new workspace's row on close, so a
                    // switch there only has to swap which windows are captured.
                    slideStartTimer.stop()
                    displayedWsId = activeWsId
                    outgoingToplevels = []
                    return
                }
                
                // Workspace changed while overview open: determine direction
                const direction = activeWsId > displayedWsId ? 1 : -1

                // 1. The slot on screen becomes the outgoing side as-is:
                // drop a half-finished outgoing slot, flip the roles, then
                // hand the same list back so its tiles are kept.
                const previous = frozenToplevels
                // Real Gnome: the strip continues from where it is now.
                const center = tRoot.stripCenter
                if (tRoot.isRealGnome)
                    tRoot.beginPlaneHandover()
                slideFromCenter = center
                // A dropped drag lands here: the strip is already on this
                // workspace, so the preview offset folds into the switch.
                if (tRoot.isRealGnome && (GlobalStates.realGnomeDragCommitWs === activeWsId || tRoot.dragCenterOffset !== 0)) {
                    dragCommitFallbackTimer.stop()
                    tRoot.dragOffsetAnimated = false
                    tRoot.dragCenterOffset = 0
                    tRoot.dragOffsetAnimated = true
                    tRoot.pendingDragShift = 0
                    GlobalStates.realGnomeDragCommitWs = 0
                    if (GlobalStates.realGnomeDragShift !== 0)
                        GlobalStates.realGnomeDragShift = 0
                }
                slideFromWs = displayedWsId
                slideToWs = activeWsId
                slideAnimEnabled = false
                outgoingToplevels = []
                // Progress goes to 0 before the flip: flipped first, the slot on
                // screen would be "outgoing at progress 1" - hidden - and a hidden
                // tile drops its ScreencopyView source, blanking it for a frame.
                transitionDirection = direction
                transitionProgress = 0.0
                currentSlot = 1 - currentSlot
                outgoingToplevels = previous

                // 2. Wait for the incoming captures with the animation disabled
                slideWaitTicks = 0
                incomingModelReady = false

                // 3. Fill the incoming slot now; the 16 ms coalescing timer
                // only delayed the first capture frame.
                displayedWsId = activeWsId
                toplevelUpdateTimer.stop()
                refreshToplevels()

                // 4. Start only after the incoming capture has had time to
                // submit its first frame to the compositor.
                slideStartTimer.restart()
            }

            // ── Overview open/close reactions ───────────────────────────────
            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (!transitionScope.featureEnabled)
                        return;
                    if (GlobalStates.classicOverviewOpen) {
                        if (tRoot.isGnomeLike) {
                            // Start the legacy handoff only after the capture
                            // layer has had a frame to render.
                            if (Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0])
                                tRoot.beginOpenHandoff();
                            tRoot.exitAnimating = false;
                            tRoot.isOverviewActive = tRoot.monitorFocused;
                            exitAnimTimer.stop();
                            restoreWindowsTimer.stop();
                        }
                        // Reset slide to center on fresh open
                        tRoot.slideAnimEnabled = false
                        slideStartTimer.stop()
                        tRoot.transitionDirection = 1
                        tRoot.transitionProgress = 1.0
                        tRoot.slideWaitTicks = 0
                        tRoot.incomingModelReady = true
                        tRoot.outgoingToplevels = []
                        tRoot.displayedWsId = tRoot.activeWsId
                        if (tRoot.monitorFocused)
                            Qt.callLater(tRoot.scheduleToplevelUpdate);
                    } else {
                        slideStartTimer.stop()
                        tRoot.resetPlaneHandover()
                        if (tRoot.isGnomeLike) {
                            openDelayTimer.stop();
                            tRoot.releaseOpenHold();
                            if (tRoot.isHandoffScreen) {
                                tRoot.closeHandoffPending = true;
                                restoreWindowsTimer.restart();
                                // Closed before the zoom moved: nothing to wait for.
                                if (tRoot.overviewController && tRoot.overviewController.progress === 0)
                                    Qt.callLater(tRoot.restoreRealWindows);
                            }
                            tRoot.exitAnimating = tRoot.monitorFocused;
                            if (tRoot.monitorFocused)
                                exitAnimTimer.restart();
                            else
                                exitAnimTimer.stop();
                        }
                        tRoot.outgoingToplevels = []
                    }
                }
            }

            Connections {
                target: transitionScope
                function onFeatureEnabledChanged() {
                    if (!transitionScope.featureEnabled) {
                        tRoot.releaseOpenHold();
                        openDelayTimer.stop();
                        restoreWindowsTimer.stop();
                        exitAnimTimer.stop();
                        slideStartTimer.stop();
                        tRoot.exitAnimating = false;
                        tRoot.isOverviewActive = false;
                        if (Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0])
                            transitionScope.setWindowHandoffActive(false);
                        tRoot.frozenToplevels = [];
                        tRoot.outgoingToplevels = [];
                    }
                }
            }

            // ── Scale transform — synced to the monitor controller ──────────
            Item {
                id: scaleContainer
                anchors.fill: parent
                visible: tRoot.shouldBeActive
                opacity: tRoot.shouldBeActive ? 1.0 : 0.0
                // Performance: removed clip to avoid scissor overhead during scale
                // Window captures are already positioned within screen bounds
                // clip: true

                // The Overview surface is transparent. The GNOME handoff hides
                // real clients after the individual Toplevel captures are
                // ready, keeping the transition layer gap-free.
                Rectangle {
                    id: backdropFallback
                    anchors.fill: parent
                    color: Appearance.colors.colLayer0
                    visible: tRoot.shouldBeActive && !tRoot.isGnomeLike && tRoot.overviewController && tRoot.overviewController.windowTransitionMode === "scale-with-background"
                }

                TransitionImage {
                    id: overviewBackdrop
                    anchors.fill: parent
                    imageSource: tRoot.useWallpaperBackdrop ? tRoot.overviewController.wallpaperPath : ""
                    visible: tRoot.useWallpaperBackdrop && status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    animated: false
                    sourceSize: Config.options.background.scaleLargeWallpapers
                        ? Qt.size(tRoot.screen.width, tRoot.screen.height)
                        : Qt.size(-1, -1)
                    mipmap: false
                    antialiasing: false
                }

                Rectangle {
                    id: overviewBackdropDim
                    anchors.fill: parent
                    color: Appearance.colors.colLayer0
                    visible: tRoot.shouldBeActive && !tRoot.isGnomeLike && tRoot.overviewController && tRoot.overviewController.windowTransitionMode === "scale-with-background"
                    opacity: tRoot.overviewController ? tRoot.overviewController.dimAmount : 0.0
                }

                // ── NEIGHBOURING WORKSPACES (Real Gnome) ───────────────────
                // Cards of the previous and next workspace beside the plane,
                // one plane width plus the gap away: they arrive from off
                // screen with the zoom, as in GNOME Shell.
                //
                // The strip is drawn once, off screen, and shown only outside
                // the plane: inside it the window slots draw the same windows
                // (live, and with the hover/picker state).
                Item {
                    id: stripSource
                    anchors.fill: parent
                    visible: tRoot.isRealGnome && tRoot.shouldBeActive && tRoot.pickerProgress > 0.001

                    Repeater {
                        model: ScriptModel {
                            values: tRoot.stripWorkspaces
                        }
                        delegate: WorkspacePeek {
                            required property int modelData
                            workspaceId: modelData
                        }
                    }
                }
                // One render of the strip per frame, shown in two bands beside
                // the plane (above/below it, vertical); inside the plane the
                // window slots draw. Each band copies only its part of the
                // texture. An inverted MultiEffect mask was tried here: with an
                // invisible mask item it let the whole strip through (the
                // displayed workspace's card under translucent windows), with a
                // rendered one it darkened the screen.
                ShaderEffectSource {
                    id: stripTexture
                    anchors.fill: parent
                    sourceItem: stripSource
                    hideSource: true
                    live: true
                    visible: stripSource.visible
                }
                StripBand {
                    x: 0
                    y: 0
                    width: tRoot.stripFullMode || tRoot.isVertical ? tRoot.width : Math.max(0, slotViewport.planeX)
                    height: tRoot.stripFullMode || !tRoot.isVertical ? tRoot.height : Math.max(0, slotViewport.planeY)
                }
                StripBand {
                    visible: !tRoot.stripFullMode && stripSource.visible && width > 1 && height > 1
                    x: tRoot.isVertical ? 0 : slotViewport.planeX + tRoot.width * tRoot.captureScale
                    y: tRoot.isVertical ? slotViewport.planeY + tRoot.height * tRoot.captureScale : 0
                    width: tRoot.isVertical ? tRoot.width : Math.max(0, tRoot.width - x)
                    height: tRoot.isVertical ? Math.max(0, tRoot.height - y) : tRoot.height
                }

                // Real Gnome clips the slide to the plane: workspaces pass
                // through it like a viewport instead of across the backing.
                Item {
                    id: slotViewport
                    readonly property real planeX: tRoot.captureOriginX * (1.0 - tRoot.captureScale) + tRoot.captureTranslateX
                    readonly property real planeY: tRoot.captureOriginY * (1.0 - tRoot.captureScale) + tRoot.captureTranslateY
                    x: tRoot.isRealGnome ? planeX : 0
                    y: tRoot.isRealGnome ? planeY : 0
                    width: tRoot.isRealGnome ? tRoot.width * tRoot.captureScale : parent.width
                    height: tRoot.isRealGnome ? tRoot.height * tRoot.captureScale : parent.height
                    clip: tRoot.isRealGnome && ((tRoot.sliding && !tRoot.stripFullMode) || tRoot.searchSlide > 0.001)

                    Item {
                        x: -slotViewport.x
                        y: -slotViewport.y
                        width: tRoot.width
                        height: tRoot.height

                        // ── WORKSPACE SLOTS (roles swap on every switch) ───────────
                        WorkspaceSlot {
                            slotIndex: 0
                            hasTiles: slot0Repeater.count > 0
                            Repeater {
                                id: slot0Repeater
                                model: ScriptModel {
                                    values: tRoot.slot0Toplevels
                                }
                                delegate: WindowCaptureTile {
                                    required property var modelData
                                    required property int index

                                    toplevel: modelData
                                    monitorData: tRoot.monitorData
                                    screenWidth: tRoot.screen.width
                                    screenHeight: tRoot.screen.height
                                    freezeGeometry: tRoot.currentSlot !== 0
                                    pickerRect: tRoot.slot0Layout[address] ?? null
                                }
                            }
                        }

                        WorkspaceSlot {
                            slotIndex: 1
                            hasTiles: slot1Repeater.count > 0
                            Repeater {
                                id: slot1Repeater
                                model: ScriptModel {
                                    values: tRoot.slot1Toplevels
                                }
                                delegate: WindowCaptureTile {
                                    required property var modelData
                                    required property int index

                                    toplevel: modelData
                                    monitorData: tRoot.monitorData
                                    screenWidth: tRoot.screen.width
                                    screenHeight: tRoot.screen.height
                                    freezeGeometry: tRoot.currentSlot !== 1
                                    pickerRect: tRoot.slot1Layout[address] ?? null
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Workspace capture slot ──────────────────────────────────────────────
    // Incoming: slides in from the switch direction. Outgoing: the previous
    // workspace leaving the other way. Both stay opaque so the wallpaper
    // never shows through a cross-fade.
    component WorkspaceSlot: Item {
        required property int slotIndex
        property bool hasTiles: false
        readonly property bool incoming: tRoot.currentSlot === slotIndex
        readonly property real offset: tRoot.isRealGnome
            ? ((incoming ? tRoot.displayedWsId : tRoot.slideFromWs) - tRoot.stripCenter) * tRoot.workspaceSlideDistance
            : incoming
            ? tRoot.transitionDirection * (1.0 - tRoot.transitionProgress) * tRoot.workspaceSlideDistance
            : -tRoot.transitionDirection * tRoot.transitionProgress * tRoot.workspaceSlideDistance

        width: parent.width
        height: parent.height
        x: !tRoot.isVertical ? offset : 0
        y: (tRoot.isVertical ? offset : 0) + tRoot.searchSlideOffset
        opacity: tRoot.captureOpacity
        // GNOME keeps workspaces at full size while they slide.
        scale: tRoot.isRealGnome ? 1.0
            : incoming ? 0.98 + (0.02 * tRoot.transitionProgress) : 1.0 - (0.02 * tRoot.transitionProgress)
        visible: tRoot.shouldBeActive
            && hasTiles
            && (incoming || tRoot.transitionProgress < 1.0)

        // Apply the same scale transform as the wallpaper
        transform: [
            Scale {
                origin.x: tRoot.captureOriginX
                origin.y: tRoot.captureOriginY
                xScale: tRoot.captureScale
                yScale: tRoot.captureScale
            },
            Translate {
                x: tRoot.captureTranslateX
                y: tRoot.captureTranslateY
            }
        ]
    }

    // ── Part of the workspace strip beside the plane (Real Gnome) ──────────
    component StripBand: ShaderEffectSource {
        sourceItem: stripTexture
        hideSource: true
        live: true
        sourceRect: Qt.rect(x, y, width, height)
        visible: stripSource.visible && width > 1 && height > 1
        opacity: tRoot.captureOpacity
    }

    // ── A workspace card on the strip (Real Gnome) ──────────────────────────
    component WorkspacePeek: Item {
        id: peek
        required property int workspaceId

        readonly property var toplevels: {
            const _ = tRoot.windowDataRevision;
            return tRoot.toplevelsOnWorkspace(peek.workspaceId);
        }
        readonly property var layout: tRoot.computePickerLayout(peek.toplevels)

        readonly property real planeX: tRoot.captureOriginX * (1.0 - tRoot.captureScale)
        readonly property real planeY: tRoot.captureOriginY * (1.0 - tRoot.captureScale)
        readonly property real offset: (peek.workspaceId - tRoot.stripCenter) * tRoot.workspaceSlideDistance

        x: planeX + (!tRoot.isVertical ? peek.offset : 0)
        y: planeY + (tRoot.isVertical ? peek.offset : 0)
        width: tRoot.width * tRoot.captureScale
        height: tRoot.height * tRoot.captureScale
        visible: peek.workspaceId > 0

        StyledRectangularShadow {
            target: peekCard
            blur: 32
            opacity: 0.5 * tRoot.pickerProgress
            offset: Qt.vector2d(0, 4)
        }

        Item {
            id: peekCard
            anchors.fill: parent
            layer.enabled: true
            layer.effect: OverviewRoundedMask {
                cornerRadius: tRoot.overviewController ? tRoot.overviewController.realGnomeRadius : Appearance.rounding.large
            }

            // The workspace at its real size, scaled into the card.
            Item {
                width: tRoot.width
                height: tRoot.height
                scale: tRoot.captureScale
                transformOrigin: Item.TopLeft

                // The background plane's own picture: same file, same box, same
                // decode size (one shared decode in the pixmap cache), so the
                // displayed workspace's card is the plane, pixel for pixel, when
                // they trade places.
                Image {
                    readonly property var plane: tRoot.planeWallpaper
                    x: plane ? plane.x : 0
                    y: plane ? plane.y : 0
                    width: plane ? plane.width : tRoot.width
                    height: plane ? plane.height : tRoot.height
                    source: !peek.visible || !tRoot.overviewController || tRoot.overviewController.wallpaperSafetyTriggered ? ""
                        : plane ? plane.source : tRoot.overviewController.wallpaperPath
                    sourceSize: plane && plane.decodeWidth > 0 ? Qt.size(plane.decodeWidth, plane.decodeHeight) : Qt.size(-1, -1)
                    mipmap: plane ? plane.mipmap : true
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                    antialiasing: true
                }

                Repeater {
                    model: ScriptModel {
                        values: peek.toplevels
                    }
                    delegate: WindowCaptureTile {
                        required property var modelData
                        required property int index

                        toplevel: modelData
                        monitorData: tRoot.monitorData
                        screenWidth: tRoot.screen.width
                        screenHeight: tRoot.screen.height
                        freezeGeometry: true
                        pickerRect: peek.layout[address] ?? null
                        liveCapture: false
                        requireFrame: true
                    }
                }
            }
        }
    }

    // ── Per-window capture item ─────────────────────────────────────────────
    component WindowCaptureTile: Item {
        id: tile

        required property var toplevel
        required property var monitorData
        required property int screenWidth
        required property int screenHeight
        property bool freezeGeometry: false
        // Real Gnome: the window's slot in the picker (unscaled slot
        // coordinates), reached on the zoom's own progress.
        property var pickerRect: null
        // Real Gnome holds the frames still while a workspace slides: a live
        // capture makes Hyprland re-render every hidden window per frame, and
        // the slide dropped to every third or fourth frame (measured).
        property bool liveCapture: Config.options.background.windowZoomLiveCapture
            && !(tRoot.isRealGnome && tRoot.sliding)
        // Peeks show nothing until the capture has a frame.
        property bool requireFrame: false

        readonly property string address: tRoot.normalizedAddress(toplevel?.HyprlandToplevel?.address)
        property var windowData: null
        // Depend on the monitor-level revision instead of installing one
        // HyprlandData connection per tile. The revision changes once after
        // the coalesced list refresh above.
        readonly property int dataRevision: tRoot.windowDataRevision
        // Ready means a frame to show. A tile hidden only by its ancestors
        // (the slot's visibility settles a binding later) is not ready: it
        // let the open hide the real windows before any capture had a frame.
        readonly property bool captureReady: tile.windowData !== null
            && (tile.width <= 0 || tile.height <= 0 || capture.hasContent)

        function updateWindowData() {
            if (tile.freezeGeometry && tile.windowData)
                return;
            if (!tRoot.exitAnimating) {
                windowData = tRoot.clientForToplevel(tile.toplevel);
            }
        }

        onAddressChanged: updateWindowData()
        onDataRevisionChanged: updateWindowData()
        Component.onCompleted: {
            updateWindowData();
            if (tRoot.pickerSettled && !tile.requireFrame && !transitionScope.animationsDisabled)
                appearAnim.restart();
        }

        // Position and size from hyprland window data (screen-relative coordinates)
        readonly property int monitorOffsetX: monitorData?.x ?? 0
        readonly property int monitorOffsetY: monitorData?.y ?? 0
        readonly property int monitorReservedLeft:   monitorData?.reserved[0] ?? 0
        readonly property int monitorReservedTop:    monitorData?.reserved[1] ?? 0

        readonly property real realX: Math.max((windowData?.at[0] ?? 0) - monitorOffsetX, 0)
        readonly property real realY: Math.max((windowData?.at[1] ?? 0) - monitorOffsetY, 0)
        readonly property real realWidth: windowData?.size[0] ?? 0
        readonly property real realHeight: windowData?.size[1] ?? 0

        // A relayout while the picker is open (a window opened or closed)
        // glides from the old slot instead of jumping.
        property rect relayoutFrom: Qt.rect(0, 0, 0, 0)
        property real relayoutT: 1.0
        property bool hadPickerRect: false
        property rect lastPickerRect: Qt.rect(0, 0, 0, 0)
        onPickerRectChanged: {
            const settled = tRoot.pickerSettled && !transitionScope.animationsDisabled;
            if (settled && tile.hadPickerRect && tile.pickerRect) {
                tile.relayoutFrom = tile.lastPickerRect;
                relayoutAnim.restart();
            }
            tile.hadPickerRect = !!tile.pickerRect;
            if (tile.pickerRect)
                tile.lastPickerRect = tile.pickerRect;
        }
        NumberAnimation {
            id: relayoutAnim
            target: tile
            property: "relayoutT"
            from: 0.0
            to: 1.0
            duration: Math.round(250 * Appearance.animMultiplier)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
        }
        readonly property real pickT: tRoot.isRealGnome && pickerRect ? tRoot.pickerProgress : 0
        readonly property real slotX: !pickerRect ? realX : relayoutT < 1 ? relayoutFrom.x + (pickerRect.x - relayoutFrom.x) * relayoutT : pickerRect.x
        readonly property real slotY: !pickerRect ? realY : relayoutT < 1 ? relayoutFrom.y + (pickerRect.y - relayoutFrom.y) * relayoutT : pickerRect.y
        readonly property real slotWidth: !pickerRect ? realWidth : relayoutT < 1 ? relayoutFrom.width + (pickerRect.width - relayoutFrom.width) * relayoutT : pickerRect.width
        readonly property real slotHeight: !pickerRect ? realHeight : relayoutT < 1 ? relayoutFrom.height + (pickerRect.height - relayoutFrom.height) * relayoutT : pickerRect.height

        x: realX + (slotX - realX) * pickT
        y: realY + (slotY - realY) * pickT
        width: realWidth + (slotWidth - realWidth) * pickT
        height: realHeight + (slotHeight - realHeight) * pickT

        visible: width > 0 && height > 0

        // Real Gnome: the hovered window lifts toward the pointer.
        readonly property bool hovered: tRoot.isRealGnome && tile.address !== ""
            && GlobalStates.realGnomeHoveredWindow === tile.address && tRoot.pickerSettled
        scale: tile.hovered ? 1.0 + 12 / Math.max(80, tile.width * tRoot.captureScale) : 1.0
        Behavior on scale {
            enabled: !transitionScope.animationsDisabled
            NumberAnimation { duration: Math.round(200 * Appearance.animMultiplier); easing.type: Easing.OutCubic }
        }
        // Windows opened while the picker is up fade in at their slot.
        property real appear: 1.0
        readonly property bool dragged: tRoot.isRealGnome && GlobalStates.realGnomeDraggedWindow !== ""
            && GlobalStates.realGnomeDraggedWindow === tile.address
        opacity: tile.dragged ? 0.0 : tile.appear * (!tile.requireFrame || capture.hasContent ? 1.0 : 0.0)
        Behavior on opacity {
            enabled: tile.requireFrame && !transitionScope.animationsDisabled
            NumberAnimation { duration: Math.round(180 * Appearance.animMultiplier) }
        }
        NumberAnimation on appear {
            id: appearAnim
            running: false
            from: 0.0
            to: 1.0
            duration: Math.round(220 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }

        readonly property bool roundedCaptures: tRoot.isGnomeLike
            || (tRoot.overviewController && tRoot.overviewController.windowTransitionMode === "scale-with-background")
        // Rounded corners matching Hyprland's window rounding. Real Gnome
        // masks only the capture so its shadow stays outside the window.
        layer.enabled: tile.roundedCaptures && !tRoot.isRealGnome
        // The analytic mask needs no second rasterized texture per tile,
        // unlike OpacityMask's rasterized Rectangle source.
        layer.effect: OverviewRoundedMask {
            cornerRadius: Appearance.rounding.windowRounding
        }

        // Soft shadow behind the window capture
        StyledRectangularShadow {
            target: tile
            blur: tRoot.isRealGnome ? 24 : 16
            opacity: tRoot.isRealGnome
                ? (tRoot.overviewController ? tRoot.overviewController.shadowAmount : 0.0) * (tile.hovered ? 0.55 : 0.35)
                : tRoot.isGnomeLike
                ? 0.3
                : (tRoot.overviewController ? tRoot.overviewController.shadowAmount * 0.3 : 0.0)
            offset: Qt.vector2d(0, tRoot.isRealGnome ? 6 : 4)
        }

        Item {
            anchors.fill: parent
            layer.enabled: tRoot.isRealGnome
            layer.effect: OverviewRoundedMask {
                cornerRadius: Appearance.rounding.windowRounding
            }

            ScreencopyView {
                id: capture
                anchors.fill: parent
                captureSource: tile.visible ? tile.toplevel : null
                live: tile.liveCapture
                paintCursor: false
                opacity: 1.0
            }
        }
    }
}

