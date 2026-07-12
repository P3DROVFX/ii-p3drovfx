pragma ComponentBehavior: Bound

// OverviewWindowTransition.qml
// ----------------------------
// Renders scaled ScreencopyView of windows on the active workspace
// in sync with the wallpaper zoom animation (GNOME-like overview effect).
//
// Architecture:
//   • One PanelWindow per screen (WlrLayer.Top, no_anim via rules)
//   • When overview opens: immediately shows full-scale window captures at real
//     screen positions, then follows GlobalStates.overviewZoomScale/Origin to
//     shrink in sync with the wallpaper.
//   • When workspace switches (while overview is open): slides captures out and
//     brings in captures of the next workspace — matching the workspace slide
//     animation direction.
//   • On overview close: reverse-animates scale back to 1.0 then hides.
//
// Flicker prevention:
//   • ScreencopyView uses live:false for performance; captures are taken once on open.
//   • captureSource is set BEFORE setting visible=true (QML binding order).
//   • A 16ms delay ensures QML has painted the layer at scale=1.0 before
//     we read GlobalStates.overviewZoomScale (which may already be < 1).

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: transitionScope

    readonly property bool featureEnabled:
        Config.options.background.zoomOutEnabled &&
        Config.options.background.windowZoomOnOverview &&
        Config.options.background.zoomOutStyle === 0

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
            readonly property int barSize: barVertical ? Appearance.sizes.verticalBarWindowWidth : Appearance.sizes.barHeight
            readonly property int gap: Appearance.gapsOut

            readonly property int padLeft: barVertical && !barBottom ? barSize : gap
            readonly property int padRight: barVertical && barBottom ? barSize : gap
            readonly property int padTop: !barVertical && !barBottom ? barSize : gap
            readonly property int padBottom: !barVertical && barBottom ? barSize : gap

            readonly property real scaleOriginX: padLeft + (tRoot.screen.width - padLeft - padRight) / 2
            readonly property real scaleOriginY: padTop + (tRoot.screen.height - padTop - padBottom) / 2

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

            Component.onCompleted: updateToplevels()

            // ── Visibility / readiness ──────────────────────────────────────
            // Must be visible while overview is open OR while exit animation runs.
            property bool exitAnimating: false
            property bool isOverviewActive: false

            // Delay applying window opacity rule to let ScreencopyView render its first frame (prevents 1-frame wallpaper pop on open)
            Timer {
                id: openDelayTimer
                interval: 60
                onTriggered: {
                    if (Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0]) {
                        Quickshell.execDetached(["hyprctl", "eval", "hl.window_rule({ match = { class = '.*' }, opacity = '0.0 0.0', no_anim = true })"]);
                    }
                }
            }

            // Restore real windows slightly before transition ends to allow Hyprland config to reload without visual pop-in
            Timer {
                id: restoreWindowsTimer
                interval: 300
                onTriggered: {
                    if (Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0]) {
                        Quickshell.execDetached(["hyprctl", "reload"]);
                    }
                }
            }

            Timer {
                id: exitAnimTimer
                // Keep transition layer visible for an extra 400ms after restore starts to cover the reload delay and fadeIn animation perfectly
                interval: 700
                onTriggered: {
                    tRoot.exitAnimating = false;
                    tRoot.isOverviewActive = false;
                }
            }

            // We activate for all monitors so that each monitor displays the zoomed-out
            // capture representation of its own active workspace windows.
            readonly property bool shouldBeActive:
                transitionScope.featureEnabled &&
                isOverviewActive

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
                    if (!transitionScope.featureEnabled) {
                        return; // Do absolutely nothing if window zoom is toggled off!
                    }
                    if (GlobalStates.overviewOpen) {
                        // Start delay timer to hide windows (allows screencopy to load first)
                        openDelayTimer.restart()

                        // Reset slide to center on fresh open
                        tRoot.slideAnimEnabled = false
                        tRoot.transitionDirection = 1
                        tRoot.transitionProgress = 1.0
                        tRoot.outgoingToplevels = []
                        tRoot.exitAnimating = false
                        tRoot.isOverviewActive = true
                        exitAnimTimer.stop()
                        restoreWindowsTimer.stop()
                        tRoot.displayedWsId = tRoot.activeWsId
                    } else {
                        // Overview closed: cancel any pending open hide
                        openDelayTimer.stop()

                        // Start exit animation and reload timing
                        tRoot.exitAnimating = true
                        restoreWindowsTimer.restart()
                        exitAnimTimer.restart()
                    }
                }
            }

            Connections {
                target: transitionScope
                function onFeatureEnabledChanged() {
                    if (!transitionScope.featureEnabled) {
                        openDelayTimer.stop()
                        if (GlobalStates.overviewOpen && (Quickshell.screens.length > 0 && tRoot.screen === Quickshell.screens[0])) {
                            Quickshell.execDetached(["hyprctl", "reload"]);
                        }
                    }
                }
            }

            // ── Scale transform — synced to wallpaper zoom ──────────────────
            // GlobalStates.overviewZoomScale is animated by Background.qml's
            // wallpaperPlanes.scaleValue (375ms OutCubic, same curve).
            // We read it directly so our transform is always frame-perfect.
            Item {
                id: scaleContainer
                anchors.fill: parent
                opacity: tRoot.shouldBeActive ? 1.0 : 0.0
                // Performance: removed clip to avoid scissor overhead during scale
                // Window captures are already positioned within screen bounds
                // clip: true

                // ── OUTGOING WORKSPACE CONTAINER ────────────────────────────
                Item {
                    id: outgoingContainer
                    width: parent.width
                    height: parent.height
                    
                    x: !tRoot.isVertical ? -tRoot.transitionDirection * tRoot.transitionProgress * (tRoot.width * 0.5) : 0
                    y: tRoot.isVertical ? -tRoot.transitionDirection * tRoot.transitionProgress * (tRoot.height * 0.5) : 0
                    opacity: 1.0 - tRoot.transitionProgress
                    scale: 1.0 - (0.07 * tRoot.transitionProgress)
                    visible: opacity > 0.0

                    // Apply the same scale transform as the wallpaper
                    transform: Scale {
                        origin.x: tRoot.scaleOriginX
                        origin.y: tRoot.scaleOriginY
                        xScale: GlobalStates.overviewZoomScale
                        yScale: GlobalStates.overviewZoomScale
                    }

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
                    opacity: tRoot.transitionProgress
                    scale: 0.95 + (0.05 * tRoot.transitionProgress)

                    // Apply the same scale transform as the wallpaper
                    transform: Scale {
                        origin.x: tRoot.scaleOriginX
                        origin.y: tRoot.scaleOriginY
                        xScale: GlobalStates.overviewZoomScale
                        yScale: GlobalStates.overviewZoomScale
                    }

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
        layer.enabled: true
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
            opacity: 0.3
            offset: Qt.vector2d(0, 4)
        }

        ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: (tile.visible && Config.options.overview.showWindowPreviews) ? tile.toplevel : null
            // Performance: live false to avoid continuous screencopy overhead
            live: false
            paintCursor: false
            opacity: 1.0
        }
    }
}
