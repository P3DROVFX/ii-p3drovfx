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
//   • ScreencopyView uses live:false for performance; captures are taken once on open.
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
            readonly property bool monitorFocused: Hyprland.focusedMonitor?.name == monitor?.name
            readonly property int activeWsId: monitor?.activeWorkspace?.id ?? 1

            readonly property bool barVertical: Config.options.bar.vertical
            readonly property bool barBottom: Config.options.bar.bottom
            readonly property int barSize: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
            readonly property int gap: Appearance.gapsOut

            readonly property int padLeft: barVertical && !barBottom ? barSize : gap
            readonly property int padRight: barVertical && barBottom ? barSize : gap
            readonly property int padTop: !barVertical && !barBottom ? barSize : gap
            readonly property int padBottom: !barVertical && barBottom ? barSize : gap

            readonly property real scaleOriginX: padLeft + (tRoot.screen.width - padLeft - padRight) / 2
            readonly property real scaleOriginY: padTop + (tRoot.screen.height - padTop - padBottom) / 2
            readonly property var overviewController: GlobalStates.overviewBackgroundControllerFor(tRoot.screen ? tRoot.screen.name : "")
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

            function updateToplevels() {
                if (tRoot.exitAnimating) {
                    // Freeze completely during exit transition to protect previews from being destroyed by hyprctl reload!
                    return;
                }
                if (!tRoot.shouldBeActive) {
                    tRoot.frozenToplevels = [];
                    return;
                }
                const res = ToplevelManager.toplevels.values.filter(toplevel => {
                    const addr = "0x" + toplevel.HyprlandToplevel?.address;
                    const win = HyprlandData.windowByAddress[addr];
                    if (!win) return false;
                    return win.workspace?.id == tRoot.displayedWsId &&
                           win.monitor == tRoot.monitor?.id;
                });
                tRoot.frozenToplevels = res;
            }

            onShouldBeActiveChanged: updateToplevels()
            onDisplayedWsIdChanged: updateToplevels()
            
            Connections {
                target: ToplevelManager.toplevels
                function onValuesChanged() {
                    tRoot.updateToplevels();
                }
            }

            Connections {
                target: HyprlandData
                ignoreUnknownSignals: true
                function onWindowByAddressChanged() {
                    tRoot.updateToplevels();
                }
            }

            Component.onCompleted: {
                updateToplevels();
                if (tRoot.isGnomeLike && GlobalStates.overviewOpen && transitionScope.featureEnabled) {
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
                    tRoot.isOverviewActive = true;
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
                (tRoot.isGnomeLike
                    ? tRoot.isOverviewActive
                    : (overviewController && overviewController.windowTransitionMode !== "none"
                        && (overviewController.active || overviewController.progress > 0.001)))

            readonly property real captureScale: tRoot.isGnomeLike
                ? GlobalStates.overviewZoomScale
                : (overviewController && overviewController.windowTransitionMode === "scale-with-background"
                    ? overviewController.scale
                    : (overviewController ? 0.98 + 0.02 * overviewController.progress : 1.0))
            readonly property real captureOriginX: tRoot.isGnomeLike ? GlobalStates.overviewZoomOriginX : (overviewController ? overviewController.scaleOriginX : tRoot.scaleOriginX)
            readonly property real captureOriginY: tRoot.isGnomeLike ? GlobalStates.overviewZoomOriginY : (overviewController ? overviewController.scaleOriginY : tRoot.scaleOriginY)
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

            Behavior on transitionProgress {
                enabled: tRoot.slideAnimEnabled
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            onTransitionProgressChanged: {
                if (transitionProgress === 1.0) {
                    outgoingToplevels = []
                }
            }

            onActiveWsIdChanged: {
                if (!GlobalStates.overviewOpen) {
                    // Not in overview — just sync, no animation needed
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

                // 3. Switch model to the new workspace (so frozenToplevels updates)
                displayedWsId = activeWsId

                // 4. Start the smooth transition one frame later
                Qt.callLater(() => {
                    slideAnimEnabled = true
                    transitionProgress = 1.0
                })
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
                            openDelayTimer.restart();
                            tRoot.exitAnimating = false;
                            tRoot.isOverviewActive = true;
                            exitAnimTimer.stop();
                            restoreWindowsTimer.stop();
                        }
                        // Reset slide to center on fresh open
                        tRoot.slideAnimEnabled = false
                        tRoot.transitionDirection = 1
                        tRoot.transitionProgress = 1.0
                        tRoot.outgoingToplevels = []
                        tRoot.displayedWsId = tRoot.activeWsId
                    } else {
                        if (tRoot.isGnomeLike) {
                            openDelayTimer.stop();
                            tRoot.exitAnimating = true;
                            restoreWindowsTimer.restart();
                            exitAnimTimer.restart();
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

                // The Overview surface is transparent. Keep real windows from
                // showing through for presets that use a backdrop. Gnome
                // restores its original handoff by hiding real windows after
                // the first capture frame.
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
                    
                    x: !tRoot.isVertical ? -tRoot.transitionDirection * tRoot.transitionProgress * (tRoot.width * 0.5) : 0
                    y: tRoot.isVertical ? -tRoot.transitionDirection * tRoot.transitionProgress * (tRoot.height * 0.5) : 0
                    opacity: (1.0 - tRoot.transitionProgress) * tRoot.captureOpacity
                    scale: 1.0 - (0.07 * tRoot.transitionProgress)
                    visible: opacity > 0.0

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
                        model: ScriptModel {
                            values: tRoot.outgoingToplevels
                        }

                        delegate: WindowCaptureTile {
                            required property var modelData
                            required property int index

                            toplevel: modelData
                            monitorData: HyprlandData.monitors.find(m => m.id === tRoot.monitor?.id)
                            screenWidth: tRoot.screen.width
                            screenHeight: tRoot.screen.height
                        }
                    }
                }

                // ── INCOMING WORKSPACE CONTAINER ────────────────────────────
                Item {
                    id: incomingContainer
                    width: parent.width
                    height: parent.height

                    x: !tRoot.isVertical ? tRoot.transitionDirection * (1.0 - tRoot.transitionProgress) * (tRoot.width * 0.5) : 0
                    y: tRoot.isVertical ? tRoot.transitionDirection * (1.0 - tRoot.transitionProgress) * (tRoot.height * 0.5) : 0
                    opacity: tRoot.transitionProgress * tRoot.captureOpacity
                    scale: 0.95 + (0.05 * tRoot.transitionProgress)

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
                        model: ScriptModel {
                            values: tRoot.frozenToplevels
                        }

                        delegate: WindowCaptureTile {
                            required property var modelData
                            required property int index

                            toplevel: modelData
                            monitorData: HyprlandData.monitors.find(m => m.id === tRoot.monitor?.id)
                            screenWidth: tRoot.screen.width
                            screenHeight: tRoot.screen.height
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

        readonly property string address: `0x${toplevel.HyprlandToplevel?.address}`
        property var windowData: null

        function updateWindowData() {
            if (!tRoot.exitAnimating) {
                windowData = HyprlandData.windowByAddress[address] || null;
            }
        }

        onAddressChanged: updateWindowData()

        Connections {
            target: HyprlandData
            ignoreUnknownSignals: true
            function onWindowByAddressChanged() {
                tile.updateWindowData();
            }
        }

        Connections {
            target: tRoot
            ignoreUnknownSignals: true
            function onExitAnimatingChanged() {
                tile.updateWindowData();
            }
        }

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
            // Performance: live false to avoid continuous screencopy overhead
            live: Config.options.background.windowZoomLiveCapture
            paintCursor: false
            opacity: 1.0
        }
    }
}
