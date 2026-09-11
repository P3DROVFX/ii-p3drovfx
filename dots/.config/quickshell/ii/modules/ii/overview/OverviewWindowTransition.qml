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
import Qt5Compat.GraphicalEffects
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
            script += "local ok = false; if rule ~= nil then ok = pcall(function() rule:set_enabled(true) end) end; ";
            script += "if not ok then local createdOk, created = pcall(function() return hl.window_rule({ name = 'quickshell-overview-window-handoff', enabled = true, match = { class = '.*' }, opacity = '0.0 0.0', no_anim = true }) end); if createdOk and created ~= nil then " + globalRef + " = created else error(tostring(created)) end end";
        } else {
            script += "if rule ~= nil then local ok = pcall(function() rule:set_enabled(false) end); if not ok then " + globalRef + " = nil end end";
        }
        return script;
    }

    function runWindowHandoffCommand() {
        windowHandoffProcess.command = ["hyprctl", "eval", transitionScope.windowHandoffScript(transitionScope.windowHandoffDesiredActive)];
        windowHandoffProcess.running = true;
    }

    function setWindowHandoffActive(active) {
        transitionScope.windowHandoffDesiredActive = active;
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
        Quickshell.execDetached(["hyprctl", "eval", transitionScope.windowHandoffScript(false)]);
    }

    Process {
        id: windowHandoffProcess
        onExited: {
            if (!transitionScope.windowHandoffCommandQueued)
                return;
            transitionScope.windowHandoffCommandQueued = false;
            transitionScope.runWindowHandoffCommand();
        }
    }

    Component.onCompleted: {
        // Recover if Quickshell was restarted while the overview handoff rule
        // was active in the still-running compositor.
        if (!GlobalStates.overviewOpen)
            transitionScope.setWindowHandoffActive(false);
    }
    Component.onDestruction: transitionScope.forceWindowHandoffInactive()

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
                    || (Config.options.background.overviewBackgroundStyle === ""
                        && Config.options.background.zoomOutStyle === 0))
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
            onDisplayedWsIdChanged: scheduleToplevelUpdate()
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
                if (tRoot.isGnomeLike && tRoot.monitorFocused && GlobalStates.overviewOpen && transitionScope.featureEnabled) {
                    tRoot.isOverviewActive = true;
                    openDelayTimer.restart();
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
                    tRoot.exitAnimating = false;
                    tRoot.isOverviewActive = false;
                    tRoot.slideAnimEnabled = false;
                    tRoot.transitionProgress = 1.0;
                    tRoot.outgoingToplevels = [];
                    if (tRoot.activeWsId > 0)
                        tRoot.displayedWsId = tRoot.activeWsId;
                    return;
                }

                if (!GlobalStates.overviewOpen || !transitionScope.featureEnabled)
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
                    openDelayTimer.restart();
                Qt.callLater(tRoot.scheduleToplevelUpdate);
            }

            Timer {
                id: openDelayTimer
                interval: 60
                onTriggered: {
                    if (tRoot.isGnomeLike && Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0]) {
                        transitionScope.setWindowHandoffActive(true);
                    }
                }
            }

            Timer {
                id: restoreWindowsTimer
                interval: 300
                onTriggered: {
                    if (tRoot.isGnomeLike && Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0]) {
                        transitionScope.setWindowHandoffActive(false);
                    }
                }
            }

            onIsGnomeLikeChanged: {
                if (Quickshell.screens.length === 0 || tRoot.screen !== Quickshell.screens[0])
                    return;
                if (!tRoot.isGnomeLike) {
                    openDelayTimer.stop();
                    restoreWindowsTimer.stop();
                    transitionScope.setWindowHandoffActive(false);
                } else if (GlobalStates.overviewOpen && transitionScope.featureEnabled) {
                    tRoot.exitAnimating = false;
                    tRoot.isOverviewActive = tRoot.monitorFocused;
                    exitAnimTimer.stop();
                    restoreWindowsTimer.stop();
                    openDelayTimer.restart();
                }
            }

            Timer {
                id: exitAnimTimer
                // Keep the capture mapped through the Hyprland handoff.
                interval: 700
                onTriggered: {
                    tRoot.exitAnimating = false;
                    tRoot.isOverviewActive = false;
                }
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
            readonly property real captureOpacity: tRoot.isGnomeLike ? 1.0 : (overviewController ? overviewController.progress : 0.0)

            visible: shouldBeActive

            // ── Workspace switch animation ──────────────────────────────────
            // We detect workspace switches while overview is open and animate
            // the transition between the outgoing and incoming workspaces.
            property int displayedWsId: activeWsId   // lags one frame on switch
            readonly property bool isVertical: Config.options.background.parallax.vertical

            property list<var> outgoingToplevels: []

            property real transitionProgress: 1.0
            property int transitionDirection: 1 // 1: next, -1: prev
            property bool slideAnimEnabled: false
            property int slideWaitTicks: 0
            readonly property int maxSlideWaitTicks: 8
            // Move the capture container past the complete viewport. A
            // fractional distance leaves the outermost window visible at the
            // edge, which is especially obvious on ultrawide monitors. The
            // extra elevation margin clears the rounded mask and shadow too.
            readonly property real workspaceSlideDistance:
                (tRoot.isVertical ? tRoot.height : tRoot.width)
                + Appearance.sizes.elevationMargin * 2

            readonly property bool incomingCapturesReady: {
                if (!tRoot.incomingModelReady)
                    return false;
                for (let i = 0; i < incomingRepeater.count; i++) {
                    const item = incomingRepeater.itemAt(i);
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
                    if (!GlobalStates.overviewOpen || !tRoot.shouldBeActive || tRoot.transitionProgress !== 0.0)
                        return;
                    if (!tRoot.incomingCapturesReady && ++tRoot.slideWaitTicks < tRoot.maxSlideWaitTicks) {
                        restart();
                        return;
                    }
                    tRoot.slideAnimEnabled = true;
                    tRoot.transitionProgress = 1.0;
                }
            }

            Behavior on transitionProgress {
                enabled: tRoot.slideAnimEnabled && !transitionScope.animationsDisabled
                // GNOME's workspace motion accelerates into the handoff and
                // settles at the destination instead of using the generic
                // spatial curve that made the two captures feel detached.
                animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
            }

            onTransitionProgressChanged: {
                if (transitionProgress === 1.0) {
                    outgoingToplevels = []
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
                    if (!GlobalStates.overviewOpen || tRoot.displayedWsId <= 0)
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
                if (!GlobalStates.overviewOpen) {
                    // Not in overview — just sync, no animation needed
                    slideStartTimer.stop()
                    displayedWsId = activeWsId
                    outgoingToplevels = []
                    return
                }
                
                // Workspace changed while overview open: determine direction
                const direction = activeWsId > displayedWsId ? 1 : -1

                // 1. Capture current workspace windows as outgoing
                outgoingToplevels = frozenToplevels

                // 2. Setup progress and direction with animation disabled
                slideAnimEnabled = false
                transitionDirection = direction
                transitionProgress = 0.0
                slideWaitTicks = 0
                incomingModelReady = false

                // 3. Switch model to the new workspace (so frozenToplevels updates)
                displayedWsId = activeWsId

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
                    if (GlobalStates.overviewOpen) {
                        if (tRoot.isGnomeLike) {
                            // Start the legacy handoff only after the capture
                            // layer has had a frame to render.
                            if (Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0])
                                openDelayTimer.restart();
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
                        if (tRoot.isGnomeLike) {
                            if (Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0]) {
                                openDelayTimer.stop();
                                restoreWindowsTimer.restart();
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

                // ── OUTGOING WORKSPACE CONTAINER ────────────────────────────
                Item {
                    id: outgoingContainer
                    width: parent.width
                    height: parent.height
                    
                    x: !tRoot.isVertical ? -tRoot.transitionDirection * tRoot.transitionProgress * tRoot.workspaceSlideDistance : 0
                    y: tRoot.isVertical ? -tRoot.transitionDirection * tRoot.transitionProgress * tRoot.workspaceSlideDistance : 0
                    // Workspace changes are a spatial handoff. Keep both
                    // captures opaque so the wallpaper never shows through a
                    // cross-fade while the incoming frame is settling.
                    opacity: tRoot.captureOpacity
                    scale: 1.0 - (0.02 * tRoot.transitionProgress)
                    visible: tRoot.shouldBeActive
                        && tRoot.transitionProgress < 1.0
                        && outgoingRepeater.count > 0

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

                    Repeater {
                        id: outgoingRepeater
                        model: ScriptModel {
                            values: tRoot.outgoingToplevels
                        }

                        delegate: WindowCaptureTile {
                            required property var modelData
                            required property int index

                            toplevel: modelData
                            monitorData: tRoot.monitorData
                            screenWidth: tRoot.screen.width
                            screenHeight: tRoot.screen.height
                            freezeGeometry: true
                        }
                    }
                }

                // ── INCOMING WORKSPACE CONTAINER ────────────────────────────
                Item {
                    id: incomingContainer
                    width: parent.width
                    height: parent.height

                    x: !tRoot.isVertical ? tRoot.transitionDirection * (1.0 - tRoot.transitionProgress) * tRoot.workspaceSlideDistance : 0
                    y: tRoot.isVertical ? tRoot.transitionDirection * (1.0 - tRoot.transitionProgress) * tRoot.workspaceSlideDistance : 0
                    opacity: tRoot.captureOpacity
                    scale: 0.98 + (0.02 * tRoot.transitionProgress)
                    visible: tRoot.shouldBeActive && incomingRepeater.count > 0

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

                    Repeater {
                        id: incomingRepeater
                        model: ScriptModel {
                            values: tRoot.frozenToplevels
                        }

                        delegate: WindowCaptureTile {
                            required property var modelData
                            required property int index

                            toplevel: modelData
                            monitorData: tRoot.monitorData
                            screenWidth: tRoot.screen.width
                            screenHeight: tRoot.screen.height
                            freezeGeometry: false
                        }
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

        readonly property string address: tRoot.normalizedAddress(toplevel?.HyprlandToplevel?.address)
        property var windowData: null
        // Depend on the monitor-level revision instead of installing one
        // HyprlandData connection per tile. The revision changes once after
        // the coalesced list refresh above.
        readonly property int dataRevision: tRoot.windowDataRevision
        readonly property bool captureReady: tile.windowData !== null
            && (!tile.visible || capture.hasContent)

        function updateWindowData() {
            if (tile.freezeGeometry && tile.windowData)
                return;
            if (!tRoot.exitAnimating) {
                windowData = tRoot.clientForToplevel(tile.toplevel);
            }
        }

        onAddressChanged: updateWindowData()
        onDataRevisionChanged: updateWindowData()
        Component.onCompleted: updateWindowData()

        // Position and size from hyprland window data (screen-relative coordinates)
        readonly property int monitorOffsetX: monitorData?.x ?? 0
        readonly property int monitorOffsetY: monitorData?.y ?? 0
        readonly property int monitorReservedLeft:   monitorData?.reserved[0] ?? 0
        readonly property int monitorReservedTop:    monitorData?.reserved[1] ?? 0

        x: Math.max((windowData?.at[0] ?? 0) - monitorOffsetX, 0)
        y: Math.max((windowData?.at[1] ?? 0) - monitorOffsetY, 0)
        width:  windowData?.size[0] ?? 0
        height: windowData?.size[1] ?? 0

        visible: width > 0 && height > 0

        // Rounded corners matching Hyprland's window rounding
        layer.enabled: tRoot.isGnomeLike
            || (tRoot.overviewController && tRoot.overviewController.windowTransitionMode === "scale-with-background")
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: tile.width
                height: tile.height
                radius: Appearance.rounding.windowRounding
            }
        }

        // Soft shadow behind the window capture
        StyledRectangularShadow {
            target: tile
            blur: 16
            opacity: tRoot.isGnomeLike
                ? 0.3
                : (tRoot.overviewController ? tRoot.overviewController.shadowAmount * 0.3 : 0.0)
            offset: Qt.vector2d(0, 4)
        }

        ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: tile.visible ? tile.toplevel : null
            live: Config.options.background.windowZoomLiveCapture
            paintCursor: false
            opacity: 1.0
        }
    }
}
