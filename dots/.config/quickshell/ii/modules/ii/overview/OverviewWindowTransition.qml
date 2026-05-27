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
//   • ScreencopyView is kept live:true during overview so captures are always fresh.
//   • captureSource is set BEFORE setting visible=true (QML binding order).
//   • A 16ms delay ensures QML has painted the layer at scale=1.0 before
//     we read GlobalStates.overviewZoomScale (which may already be < 1).

import qs
import qs.services
import qs.modules.common
import Qt5Compat.GraphicalEffects
import QtQuick
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

            // Delay applying window opacity rule to let ScreencopyView render its first frame (prevents 1-frame wallpaper pop on open)
            Timer {
                id: openDelayTimer
                interval: 60
                onTriggered: {
                    if (tRoot.monitorFocused) {
                        Quickshell.execDetached(["hyprctl", "eval", "hl.window_rule({ match = { class = '.*' }, opacity = '0.0 0.0', no_anim = true })"]);
                    }
                }
            }

            // Restore real windows slightly before transition ends to allow Hyprland config to reload without visual pop-in
            Timer {
                id: restoreWindowsTimer
                interval: 300
                onTriggered: {
                    if (tRoot.monitorFocused) {
                        Quickshell.execDetached(["hyprctl", "reload"]);
                    }
                }
            }

            Timer {
                id: exitAnimTimer
                // Keep transition layer visible for an extra 400ms after restore starts to cover the reload delay and fadeIn animation perfectly
                interval: 700
                onTriggered: tRoot.exitAnimating = false
            }

            // We only activate for the focused monitor to avoid showing
            // captures on non-focused monitors (they'd be wrong workspace).
            readonly property bool shouldBeActive:
                transitionScope.featureEnabled &&
                monitorFocused &&
                (GlobalStates.overviewOpen || exitAnimating)

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
                NumberAnimation {
                    duration: 400
                    easing.type: Easing.OutQuint
                }
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
                        if (GlobalStates.overviewOpen && tRoot.monitorFocused) {
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
                // Clip prevents window captures from bleeding outside screen bounds
                clip: true

                // ── OUTGOING WORKSPACE CONTAINER ────────────────────────────
                Item {
                    id: outgoingContainer
                    width: parent.width
                    height: parent.height
                    
                    x: !tRoot.isVertical ? -tRoot.transitionDirection * tRoot.transitionProgress * (tRoot.width * 0.3) : 0
                    y: tRoot.isVertical ? -tRoot.transitionDirection * tRoot.transitionProgress * (tRoot.height * 0.3) : 0
                    opacity: 1.0 - tRoot.transitionProgress
                    scale: 1.0 - (0.07 * tRoot.transitionProgress)
                    visible: opacity > 0.0

                    // Apply the same scale transform as the wallpaper
                    transform: Scale {
                        origin.x: GlobalStates.overviewZoomOriginX
                        origin.y: GlobalStates.overviewZoomOriginY
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
                        origin.x: GlobalStates.overviewZoomOriginX
                        origin.y: GlobalStates.overviewZoomOriginY
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
        readonly property var windowData: HyprlandData.windowByAddress[address]

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

        ScreencopyView {
            id: capture
            anchors.fill: parent
            captureSource: tile.visible ? tile.toplevel : null
            live: !tRoot.exitAnimating
            paintCursor: false
            opacity: 1.0
        }
    }
}
