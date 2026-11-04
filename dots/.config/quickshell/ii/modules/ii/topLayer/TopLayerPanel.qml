import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.dynamicIsland.core
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.shared
import qs.modules.ii.verticalBar as VBar
import qs.modules.ii.sidebarPolicies as Policies
import qs.modules.ii.sidebarDashboard as Dashboard
import qs.modules.ii.wrappedFrame as Frame
import qs.modules.ii.topLayer.search as SearchConnect
import qs.modules.ii.topLayer.osd as OsdConnect
import qs.modules.ii.overview

PanelWindow {
    id: topPanel
    color: "transparent"
    WlrLayershell.namespace: "quickshell:topLayer"
    WlrLayershell.layer: searchOpenOnMonitor ? WlrLayer.Overlay : WlrLayer.Top
    exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3 && hasBarOnThisMonitor
    readonly property real lockTransitionProgress: GlobalStates.lockBarTransitionProgress
    readonly property bool lockTransitionActive: lockTransitionProgress > 0.01
    readonly property real lockSlideDistance: topPanel.barVertical ? Appearance.sizes.verticalBarWindowWidth + Appearance.rounding.screenRounding : Appearance.sizes.barHeight + Appearance.rounding.screenRounding
    readonly property real lockSlideOffsetX: topPanel.barVertical ? (topPanel.barOnLeft ? -lockSlideDistance : lockSlideDistance) : 0
    readonly property real lockSlideOffsetY: topPanel.barVertical ? 0 : (topPanel.barBottom ? lockSlideDistance : -lockSlideDistance)
    readonly property real lockVisualOpacity: topPanel.usingWrappedFrame ? 1.0 - lockTransitionProgress : 1.0

    BarThemes {
        id: barThemes
    }

    Component {
        id: policiesContentComponent
        Policies.SidebarPoliciesContent {
            scopeRoot: topPanel
        }
    }

    Component {
        id: leftDashboardContentComponent
        Dashboard.SidebarDashboardContent {
            keepWarm: topPanel.keepLeftSidebarContentLoaded
        }
    }

    Component {
        id: rightDashboardContentComponent
        Dashboard.SidebarDashboardContent {
            keepWarm: topPanel.keepRightSidebarContentLoaded
        }
    }

    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)
    readonly property bool hasBarOnThisMonitor: GlobalStates.isScreenAllowedForBar(topPanel.screen)
    readonly property bool barVertical: BarPlacement.vertical && hasBarOnThisMonitor
    readonly property bool barBottom: BarPlacement.bottom && hasBarOnThisMonitor
    readonly property bool barOnLeft: barVertical && !barBottom
    readonly property bool barOnRight: barVertical && barBottom
    readonly property bool policiesOnLeft: Config.options.sidebar.position === "default" || Config.options.sidebar.position === "left"
    readonly property string policiesMonitorName: policiesOnLeft ? GlobalStates.effectiveLeftMonitor : GlobalStates.effectiveRightMonitor
    readonly property bool policiesOpenOnMonitor: GlobalStates.policiesPanelOpen && screen.name === topPanel.policiesMonitorName
    readonly property bool policiesRenderedOnLeft: {
        const pos = Config.options.sidebar.position;
        return pos === "default" || (pos === "left" && GlobalStates.policiesPanelOpen && !GlobalStates.dashboardPanelOpen);
    }
    readonly property bool policiesRenderedOnRight: {
        const pos = Config.options.sidebar.position;
        return pos === "inverted" || (pos === "right" && GlobalStates.policiesPanelOpen && !GlobalStates.dashboardPanelOpen);
    }
    readonly property bool policiesActiveOnMonitor: policiesOnLeft ? topPanel.leftSidebarActiveOnMonitor : topPanel.rightSidebarActiveOnMonitor

    function togglePoliciesExtended() {
        GlobalStates.policiesExtended = !GlobalStates.policiesExtended;
    }

    function togglePoliciesDetach() {
        GlobalStates.policiesDetached = !GlobalStates.policiesDetached;
    }

    function togglePoliciesPin() {
        GlobalStates.policiesPinned = !GlobalStates.policiesPinned;
    }

    readonly property bool isDynamicIslandTop: !topPanel.barVertical && !topPanel.barBottom && BarInteraction.cornerStyle === 3 && hasBarOnThisMonitor
    readonly property bool isDynamicIslandBottom: !topPanel.barVertical && topPanel.barBottom && BarInteraction.cornerStyle === 3 && hasBarOnThisMonitor
    // A pinned dock on the top or bottom edge is a separate surface under nothing here: the
    // sidebars, the vertical bar and the wrapped frame ran on beneath it. Its exclusive zone
    // is treated as part of that edge instead - they stop where the windows do.
    readonly property var dockInset: GlobalStates.dockInsets[topPanel.screen.name] ?? null
    readonly property bool dockShapesShell: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate
    readonly property real dockTopZone: (dockShapesShell && dockInset && dockInset.side === "top") ? (dockInset.reserved ?? 0) : 0
    readonly property real dockBottomZone: (dockShapesShell && dockInset && dockInset.side === "bottom") ? (dockInset.reserved ?? 0) : 0
    // The frame's band under the dock: the reserved zone, or a full-width tray while it shows.
    // It follows the tray's reveal slide, which is what the dock no longer paints.
    // Only a full-width dock joins the frame: `shown` is its tray while it shows. Any other
    // style keeps its own design and only gets pushed.
    readonly property real dockTopBandTarget: (dockShapesShell && dockInset && dockInset.side === "top") ? (dockInset.shown ?? 0) : 0
    readonly property real dockBottomBandTarget: (dockShapesShell && dockInset && dockInset.side === "bottom") ? (dockInset.shown ?? 0) : 0
    readonly property real dockLeftBandTarget: (dockShapesShell && dockInset && dockInset.side === "left") ? (dockInset.shown ?? 0) : 0
    readonly property real dockRightBandTarget: (dockShapesShell && dockInset && dockInset.side === "right") ? (dockInset.shown ?? 0) : 0
    property real dockLeftBand: dockLeftBandTarget
    property real dockRightBand: dockRightBandTarget
    Behavior on dockLeftBand {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(topPanel)
    }
    Behavior on dockRightBand {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(topPanel)
    }
    property real dockTopBand: dockTopBandTarget
    property real dockBottomBand: dockBottomBandTarget
    Behavior on dockTopBand {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(topPanel)
    }
    Behavior on dockBottomBand {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(topPanel)
    }
    // While search is open this layer climbs to Overlay and Hyprland stacks it over the
    // dock: the band would cover the dock's content. The dock paints its own tray then,
    // switched at once both ways so there is no frame with neither.
    readonly property bool dockUnderThisLayer: !topPanel.searchOpenOnMonitor
    // Without the wrapped frame the band is a plain strip (dockBandPlain) in the sidebar's colour.
    readonly property bool dockOnFrameBand: (frameLoader.active || !usingWrappedFrame) && dockShapesShell && dockUnderThisLayer
    onDockOnFrameBandChanged: GlobalStates.setDockBand(topPanel.screen.name, topPanel.dockOnFrameBand)
    // The dock sits inside the frame's ring when nothing else holds that edge.
    readonly property real ringThickness: usingWrappedFrame ? Config.options.appearance.wrappedFrameThickness : 0
    readonly property real sidebarTopOffset: sidebarTopBarOffset + (dockTopZone > 0 ? dockTopZone + (sidebarTopBarOffset > 0 ? 0 : ringThickness) : 0)
    readonly property real sidebarBottomOffset: sidebarBottomBarOffset + (dockBottomZone > 0 ? dockBottomZone + (sidebarBottomBarOffset > 0 ? 0 : ringThickness) : 0)
    readonly property real sidebarTopBarOffset: isDynamicIslandTop ? (Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut) : ((!topPanel.barVertical && !topPanel.barBottom && (BarInteraction.cornerStyle === 0 || BarInteraction.cornerStyle === 2) && hasBarOnThisMonitor) ? Appearance.sizes.barHeight : 0)
    readonly property real sidebarBottomBarOffset: isDynamicIslandBottom ? (Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut) : ((!topPanel.barVertical && topPanel.barBottom && (BarInteraction.cornerStyle === 0 || BarInteraction.cornerStyle === 2) && hasBarOnThisMonitor) ? Appearance.sizes.barHeight : 0)

    property real leftSidebarMaskWidth: 0
    property real rightSidebarMaskWidth: 0

    readonly property real leftContentWidth: {
        const pos = Config.options.sidebar.position;
        if (pos === "inverted")
            return GlobalStates.dashboardWidth;
        if (pos === "left")
            return GlobalStates.dashboardPanelOpen ? GlobalStates.dashboardWidth : GlobalStates.policiesWidth;
        return GlobalStates.policiesWidth;
    }

    readonly property real rightContentWidth: {
        const pos = Config.options.sidebar.position;
        if (pos === "inverted")
            return GlobalStates.policiesWidth;
        if (pos === "right")
            return GlobalStates.sidebarLeftOpen ? GlobalStates.policiesWidth : GlobalStates.dashboardWidth;
        return GlobalStates.dashboardWidth;
    }

    Connections {
        target: GlobalStates
        ignoreUnknownSignals: true
        function onLeftSidebarTargetWidthChanged() {
            if (GlobalStates.leftSidebarTargetWidth > 0 && topPanel.leftSidebarWarmOnMonitor) {
                topPanel.leftSidebarMaskWidth = GlobalStates.leftSidebarTargetWidth;
            }
        }
        function onRightSidebarTargetWidthChanged() {
            if (GlobalStates.rightSidebarTargetWidth > 0 && topPanel.rightSidebarWarmOnMonitor) {
                topPanel.rightSidebarMaskWidth = GlobalStates.rightSidebarTargetWidth;
            }
        }
    }

    Component.onCompleted: {
        if (GlobalStates.leftSidebarTargetWidth > 0 && topPanel.leftSidebarWarmOnMonitor) {
            topPanel.leftSidebarMaskWidth = GlobalStates.leftSidebarTargetWidth;
        }
        if (GlobalStates.rightSidebarTargetWidth > 0 && topPanel.rightSidebarWarmOnMonitor) {
            topPanel.rightSidebarMaskWidth = GlobalStates.rightSidebarTargetWidth;
        }
        topPanel.updateFocusGrab();
        GlobalStates.setDockBand(topPanel.screen.name, topPanel.dockOnFrameBand);
    }

    readonly property bool leftSidebarOpenOnMonitor: GlobalStates.sidebarLeftOpen && screen.name === GlobalStates.effectiveLeftMonitor
    readonly property bool rightSidebarOpenOnMonitor: GlobalStates.sidebarRightOpen && screen.name === GlobalStates.effectiveRightMonitor
    readonly property bool keepRightSidebarContentLoaded: Config.ready && Config.options.sidebar.keepRightSidebarLoaded
    readonly property bool rightSidebarContentWanted: GlobalStates.sidebarRightOpen || topPanel.keepRightSidebarContentLoaded
    readonly property bool keepLeftSidebarContentLoaded: Config.ready && Config.options.sidebar.keepLeftSidebarLoaded
    readonly property bool leftSidebarContentWanted: GlobalStates.sidebarLeftOpen || topPanel.keepLeftSidebarContentLoaded
    readonly property bool leftSidebarActiveOnMonitor: (GlobalStates.animatedLeftSidebarWidth > 0 || GlobalStates.sidebarLeftOpen) && screen.name === GlobalStates.effectiveLeftMonitor && !(GlobalStates.policiesDetached && topPanel.policiesRenderedOnLeft)
    readonly property bool rightSidebarActiveOnMonitor: (GlobalStates.animatedRightSidebarWidth > 0 || GlobalStates.sidebarRightOpen) && screen.name === GlobalStates.effectiveRightMonitor && !(GlobalStates.policiesDetached && topPanel.policiesRenderedOnRight)

    readonly property bool leftSidebarDialogDimmed: leftSidebarContentLoader.status === Loader.Ready && leftSidebarContentLoader.item && leftSidebarContentLoader.item.hasOwnProperty("anyDialogVisible") && leftSidebarContentLoader.item.anyDialogVisible
    readonly property bool rightSidebarDialogDimmed: rightSidebarContentLoader.status === Loader.Ready && rightSidebarContentLoader.item && rightSidebarContentLoader.item.hasOwnProperty("anyDialogVisible") && rightSidebarContentLoader.item.anyDialogVisible

    readonly property color leftSidebarCornerColor: {
        var base = Qt.color(Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0);
        if (!leftSidebarDialogDimmed)
            return base;
        var scrim = Qt.color(Appearance.colors.colScrim);
        return Qt.rgba(base.r * (1 - scrim.a) + scrim.r * scrim.a, base.g * (1 - scrim.a) + scrim.g * scrim.a, base.b * (1 - scrim.a) + scrim.b * scrim.a, base.a);
    }
    readonly property color rightSidebarCornerColor: {
        var base = Qt.color(Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0);
        if (!rightSidebarDialogDimmed)
            return base;
        var scrim = Qt.color(Appearance.colors.colScrim);
        return Qt.rgba(base.r * (1 - scrim.a) + scrim.r * scrim.a, base.g * (1 - scrim.a) + scrim.g * scrim.a, base.b * (1 - scrim.a) + scrim.b * scrim.a, base.a);
    }
    readonly property bool searchDropSuppressed: (Config.ready && Config.options.bar.dynamicIsland.notchMode.enable) || GlobalStates.floatingNotchOwnsSearch || !GlobalStates.searchConnectActive
    readonly property bool searchOpenOnMonitor: (GlobalStates.overviewOpen || (searchDropLoader.item && searchDropLoader.item.openProgress > 0.001)) && GlobalStates.searchConnectActive && screen.name === GlobalStates.activeSearchMonitor && !topPanel.searchDropSuppressed
    readonly property bool osdOpenOnMonitor: GlobalStates.osdVolumeOpen && GlobalStates.osdConnectActive && !(Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material" || Config.options.osd.style === "tuner")) && !(Config.ready && !BarPlacement.vertical && BarInteraction.cornerStyle === 3) && screen.name === (Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0])?.name && !IslandPolicy.ownsOsd

    readonly property bool hasFullscreenWindowOnMonitor: {
        const monitorData = HyprlandData.monitors.find(m => m.name === topPanel.screen.name);
        const specialWsName = monitorData?.specialWorkspace?.name;
        const workspaces = Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === topPanel.screen.name);
        return workspaces.some(workspace => {
            const isWorkspaceActive = workspace.active || (specialWsName && specialWsName !== "" && (workspace.name === specialWsName || workspace.name === "special:" + specialWsName || (specialWsName === "special:special" && workspace.name === "special") || (specialWsName === "special" && workspace.name === "special:special")));

            return isWorkspaceActive && workspace.toplevels.values.some(toplevel => toplevel.wayland && toplevel.wayland.fullscreen);
        });
    }

    readonly property bool leftSidebarWarmOnMonitor: {
        if (GlobalStates.policiesDetached && topPanel.policiesRenderedOnLeft)
            return false;
        if (GlobalStates.effectiveLeftMonitor !== "") {
            return screen.name === GlobalStates.effectiveLeftMonitor;
        }
        return false;
    }
    readonly property bool rightSidebarWarmOnMonitor: {
        if (GlobalStates.policiesDetached && topPanel.policiesRenderedOnRight)
            return false;
        if (GlobalStates.effectiveRightMonitor !== "") {
            return screen.name === GlobalStates.effectiveRightMonitor;
        }
        return false;
    }

    onLeftSidebarActiveOnMonitorChanged: {
        // Debug removed for production performance
    }

    onRightSidebarActiveOnMonitorChanged: {
        // Debug removed for production performance
    }

    readonly property bool barMustShow: {
        if (!barVertical) {
            return horizontalBarLoader.item ? horizontalBarLoader.item.mustShow : false;
        } else {
            return verticalBarLoader.item ? verticalBarLoader.item.mustShow : false;
        }
    }

    readonly property real hBarHiddenAmount: horizontalBarLoader.item ? horizontalBarLoader.item.hiddenAmount : 0
    readonly property real vBarHiddenAmount: verticalBarLoader.item ? verticalBarLoader.item.hiddenAmount : 0

    // Float bar gaps: the bar is visually offset from screen edges by hyprlandGapsOut.
    // SearchDrop/OsdDrop need this offset so they emerge from the bar's visual top edge.
    readonly property real barMargin: BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0

    // A Float bar leaves no screen edge for a sidebar to run along, so each embedded sidebar
    // is a card floating at the bar's gaps, and the one on the bar's side fuses with the bar
    // into a single rounded shape (barFusedFill). Horizontal Float bars keep their sidebars
    // as separate windows (GlobalStates.connectSidebarsSeparate).
    readonly property bool floatSidebarCards: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && BarInteraction.cornerStyle === 1
    readonly property real floatSidebarGap: floatSidebarCards ? Appearance.sizes.hyprlandGapsOut : 0
    // The bar's own pill radius, so the fused shape is rounded alike at both ends.
    readonly property real floatSidebarRadius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut
    readonly property color floatSidebarColor: Config.options.bar.amoledBackground ? "#000000" : (Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0)
    readonly property bool floatSidebarShadow: Config.options.bar.dropShadow && !ShellModePolicy.barDropShadowBlocked
    // Only a seated bar with a background of its own fuses: island bars have none, and a bar
    // sliding off the edge hands the card its own fill back first.
    readonly property bool barCanFuse: floatSidebarCards && !!verticalBarLoader.item && topPanel.shellHide === 0
        && Config.options.bar.barBackgroundStyle !== 3
    readonly property bool leftSidebarFusesBar: barCanFuse && barOnLeft && leftSidebarActiveOnMonitor
    readonly property bool rightSidebarFusesBar: barCanFuse && barOnRight && rightSidebarActiveOnMonitor

    // With the wrapped frame on, a welded vertical bar's plate (WrappedFrameVisuals
    // leftBarPlate / rightBarPlate) already spans totalLeftPush / totalRightPush,
    // painting the sidebar and the bar as one continuous fill. Keep the sidebar's
    // own rectangle transparent then so translucent backgrounds are not blended twice.
    readonly property bool barWeldedToFrame: topPanel.usingWrappedFrame && topPanel.shellSeated
        && (BarInteraction.cornerStyle === 0 || BarInteraction.cornerStyle === 2)
        && Config.options.bar.barBackgroundStyle !== 3
        && (verticalBarLoader.item ? verticalBarLoader.item.showBarBackground : false)
    readonly property bool leftSidebarWeldedToBar: barWeldedToFrame && barOnLeft
    readonly property bool rightSidebarWeldedToBar: barWeldedToFrame && barOnRight

    // ── Shell edge slide ─────────────────────────────────────────────────────
    // Fullscreen and media mode used to drop the bar and the frame in a single
    // frame — `active` went false and the panels were simply gone. They now
    // leave through their own edge: the bar slides out past it, the frame folds
    // into the screen edges (WrappedFrameVisuals.hideProgress), and the loaders
    // are only torn down once the slide has finished. The placement swap rides
    // the same offset, so a bar that changes edge exits through the old one and
    // enters through the new one — the direction flips with the config, which
    // GlobalStates writes while we are off screen.
    readonly property bool mediaModeHere: GlobalStates.isMediaModeActiveForScreen(topPanel.screen ? topPanel.screen.name : "")
    readonly property bool shellHiddenWanted: (topPanel.hasFullscreenWindowOnMonitor
            && !GlobalStates.overviewOpen && !GlobalStates.sidebarLeftOpen && !GlobalStates.sidebarRightOpen)
        || topPanel.mediaModeHere
    property real shellHideProgress: topPanel.shellHiddenWanted ? 1 : 0
    Behavior on shellHideProgress {
        animation: Appearance.animation.shellEdgeSlide.numberAnimation.createObject(topPanel)
    }
    readonly property real shellHide: Math.max(shellHideProgress, GlobalStates.barPlacementSwapProgress)
    readonly property bool shellSeated: topPanel.shellHide < 0.999
    // Loaders outlive the hide request by exactly one slide, so there is
    // something on screen to animate out.
    readonly property bool shellContentWanted: !topPanel.mediaModeHere || topPanel.shellSeated
    readonly property real shellSlideY: topPanel.barVertical
        ? 0
        : (topPanel.barBottom ? 1 : -1) * topPanel.shellHide * (Appearance.sizes.barHeight + Appearance.rounding.screenRounding)
    readonly property real shellSlideX: topPanel.barVertical
        ? (topPanel.barOnRight ? 1 : -1) * topPanel.shellHide * (Appearance.sizes.verticalBarWindowWidth + Appearance.rounding.screenRounding)
        : 0

    readonly property bool leftSidebarNeedsKeyboard: leftSidebarOpenOnMonitor && !GlobalStates.connectSidebarsSeparate && !(GlobalStates.policiesDetached && topPanel.policiesRenderedOnLeft)
    readonly property bool rightSidebarNeedsKeyboard: rightSidebarOpenOnMonitor && !GlobalStates.connectSidebarsSeparate && !(GlobalStates.policiesDetached && topPanel.policiesRenderedOnRight)
    readonly property bool policiesNeedsKeyboard: topPanel.policiesOpenOnMonitor && !GlobalStates.connectSidebarsSeparate && !GlobalStates.policiesDetached

    WlrLayershell.keyboardFocus: (searchOpenOnMonitor || policiesNeedsKeyboard || leftSidebarNeedsKeyboard || rightSidebarNeedsKeyboard) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Resolve policy commands at window level so focused/selected TextEdits cannot
    // consume Ctrl+D before the sidebar controller sees it.
    Shortcut {
        sequence: "Ctrl+D"
        enabled: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && topPanel.policiesOpenOnMonitor && !GlobalStates.policiesDetached
        onActivated: topPanel.togglePoliciesDetach()
    }
    Shortcut {
        sequence: "Ctrl+O"
        enabled: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && topPanel.policiesOpenOnMonitor && !GlobalStates.policiesDetached
        onActivated: topPanel.togglePoliciesExtended()
    }
    Shortcut {
        sequence: "Ctrl+P"
        enabled: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && topPanel.policiesOpenOnMonitor && !GlobalStates.policiesDetached
        onActivated: topPanel.togglePoliciesPin()
    }

    // 1. Wrapped Frame Visuals
    Loader {
        id: frameLoader
        active: topPanel.usingWrappedFrame && topPanel.shellContentWanted
        visible: topPanel.shellSeated
        anchors.fill: parent
        opacity: topPanel.lockVisualOpacity
        sourceComponent: Frame.WrappedFrameVisuals {
            hideProgress: topPanel.shellHide
            showBarBackground: horizontalBarLoader.item ? horizontalBarLoader.item.showBarBackground : (verticalBarLoader.item ? verticalBarLoader.item.showBarBackground : false)
            screen: topPanel.screen

            // Plain bindings, not new properties: WrappedFrameVisuals already
            // declares both, and redeclaring them here shadowed the originals so
            // the frame (and now the shell shadow silhouette) never saw the bar
            // retract under autohide.
            hBarHiddenAmount: topPanel.hBarHiddenAmount
            vBarHiddenAmount: topPanel.vBarHiddenAmount

            leftSidebarMaskOffset: topPanel.leftSidebarMaskWidth
            rightSidebarMaskOffset: topPanel.rightSidebarMaskWidth

            sidebarTopOffset: topPanel.sidebarTopOffset
            sidebarBottomOffset: topPanel.sidebarBottomOffset
            dockTopInset: topPanel.dockUnderThisLayer ? topPanel.dockTopBand : 0
            dockBottomInset: topPanel.dockUnderThisLayer ? topPanel.dockBottomBand : 0
            dockLeftInset: topPanel.dockUnderThisLayer ? topPanel.dockLeftBand : 0
            dockRightInset: topPanel.dockUnderThisLayer ? topPanel.dockRightBand : 0
        }
    }

    // 2. Horizontal Bar Visual Layer
    Loader {
        id: horizontalBarLoader
        active: !topPanel.barVertical && GlobalStates.barOpen && hasBarOnThisMonitor && topPanel.shellContentWanted
        visible: topPanel.shellSeated
        anchors.fill: parent
        opacity: topPanel.lockVisualOpacity
        transform: Translate {
            y: (topPanel.usingWrappedFrame ? 0 : topPanel.lockSlideOffsetY * topPanel.lockTransitionProgress) + topPanel.shellSlideY
        }
        sourceComponent: Component {
            Item {
                id: hBarItem
                anchors.fill: parent

                property int monitorIndex: Quickshell.screens.indexOf(topPanel.screen)
                property bool hasActiveWindows: false
                property bool showBarBackground: (hasActiveWindows && Config.options.bar.barBackgroundStyle === 2) || Config.options.bar.barBackgroundStyle === 1 || Config.options.bar.barBackgroundStyle === 3

                Connections {
                    enabled: Config.options.bar.barBackgroundStyle === 2
                    target: HyprlandData
                    function onWindowListChanged() {
                        const monitor = HyprlandData.monitors.find(m => m.name === topPanel.screen.name);
                        const wsId = monitor?.activeWorkspace?.id;
                        const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;
                        hBarItem.hasActiveWindows = hasWindow;
                    }
                }

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: hBarItem.superShow = true
                }

                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                            return;
                        if (GlobalStates.superDown)
                            showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            hBarItem.superShow = false;
                        }
                    }
                }

                // ── Hover delay trigger ───────────────────────────────────────
                property bool hoverTriggered: false
                readonly property int hoverDelay: Config?.options.bar.autoHide.hoverDelay ?? 0

                Timer {
                    id: hoverOpenTimer
                    interval: hBarItem.hoverDelay
                    repeat: false
                    onTriggered: hBarItem.hoverTriggered = true
                }

                Connections {
                    target: hoverRegion
                    function onContainsMouseChanged() {
                        if (hoverRegion.containsMouse) {
                            if (hBarItem.hoverDelay <= 0 || (Config?.options.bar.autoHide.enable && !hBarItem.mustShow) === false || hBarItem.superShow || topPanel.leftSidebarOpenOnMonitor || topPanel.rightSidebarOpenOnMonitor) {
                                hBarItem.hoverTriggered = true;
                            } else {
                                hoverOpenTimer.restart();
                            }
                        } else {
                            hoverOpenTimer.stop();
                            hBarItem.hoverTriggered = false;
                        }
                    }
                }

                property bool superShow: false
                property bool mustShow: hoverTriggered || superShow || topPanel.leftSidebarOpenOnMonitor || topPanel.rightSidebarOpenOnMonitor

                MouseArea {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: !topPanel.barBottom ? parent.top : undefined
                        bottom: topPanel.barBottom ? parent.bottom : undefined
                        rightMargin: (Config.options.interactions.deadPixelWorkaround.enable) * 1
                        bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && topPanel.barBottom) * 1
                    }
                    height: Appearance.sizes.barHeight + Appearance.rounding.screenRounding

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            topMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            bottomMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    Bar.BarContent {
                        id: barContent
                        monitorIndex: hBarItem.monitorIndex
                        implicitHeight: Appearance.sizes.barHeight
                        anchors {
                            right: parent.right
                            left: parent.left
                            top: parent.top
                            bottom: undefined
                            topMargin: (Config?.options.bar.autoHide.enable && !hBarItem.mustShow) ? -Appearance.sizes.barHeight : 0
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable) * -1
                        }

                        Behavior on anchors.topMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barContent)
                        }
                        Behavior on anchors.bottomMargin {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barContent)
                        }

                        states: State {
                            name: "bottom"
                            when: topPanel.barBottom
                            AnchorChanges {
                                target: barContent
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: parent.bottom
                                }
                            }
                            PropertyChanges {
                                target: barContent
                                anchors.topMargin: 0
                                anchors.bottomMargin: (Config?.options.bar.autoHide.enable && !hBarItem.mustShow) ? -Appearance.sizes.barHeight : (Config.options.interactions.deadPixelWorkaround.enable) * -1
                            }
                        }
                    }

                    Loader {
                        id: roundDecorators
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: barContent.bottom
                            bottom: undefined
                        }
                        height: Appearance.rounding.screenRounding
                        active: hBarItem.showBarBackground && BarInteraction.cornerStyle === 0 && !topPanel.usingWrappedFrame

                        states: State {
                            name: "bottom"
                            when: topPanel.barBottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    right: parent.right
                                    left: parent.left
                                    top: undefined
                                    bottom: barContent.top
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitHeight: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: leftCorner
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: parent.left
                                    leftMargin: topPanel.leftSidebarActiveOnMonitor ? GlobalStates.animatedLeftSidebarWidth : 0
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: hBarItem.showBarBackground ? (Config.options.bar.amoledBackground ? "#000000" : Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: topPanel.barBottom
                                    PropertyChanges {
                                        target: leftCorner
                                        corner: RoundCorner.CornerEnum.BottomLeft
                                    }
                                }
                            }
                            RoundCorner {
                                id: rightCorner
                                anchors {
                                    top: !topPanel.barBottom ? parent.top : undefined
                                    bottom: topPanel.barBottom ? parent.bottom : undefined
                                    right: parent.right
                                    rightMargin: topPanel.rightSidebarActiveOnMonitor ? GlobalStates.animatedRightSidebarWidth : 0
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: hBarItem.showBarBackground ? (Config.options.bar.amoledBackground ? "#000000" : Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.TopRight
                                states: State {
                                    name: "bottom"
                                    when: topPanel.barBottom
                                    PropertyChanges {
                                        target: rightCorner
                                        corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }

                property alias maskItem: hoverMaskRegion
                property real hiddenAmount: (Config?.options.bar.autoHide.enable && !mustShow) ? Appearance.sizes.barHeight : 0

                Behavior on hiddenAmount {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(hBarItem)
                }
            }
        }
    }

    // 3. Vertical Bar Visual Layer
    Loader {
        id: verticalBarLoader
        active: topPanel.barVertical && GlobalStates.barOpen && hasBarOnThisMonitor && topPanel.shellContentWanted
        visible: topPanel.shellSeated
        anchors.fill: parent
        opacity: topPanel.lockVisualOpacity
        transform: Translate {
            x: (topPanel.usingWrappedFrame ? 0 : topPanel.lockSlideOffsetX * topPanel.lockTransitionProgress) + topPanel.shellSlideX
        }
        sourceComponent: Component {
            Item {
                id: vBarItem
                anchors.fill: parent

                property int monitorIndex: Quickshell.screens.indexOf(topPanel.screen)
                property bool hasActiveWindows: false
                property bool showBarBackground: (hasActiveWindows && Config.options.bar.barBackgroundStyle === 2) || Config.options.bar.barBackgroundStyle === 1 || Config.options.bar.barBackgroundStyle === 3

                Connections {
                    enabled: Config.options.bar.barBackgroundStyle === 2
                    target: HyprlandData
                    function onWindowListChanged() {
                        const monitor = HyprlandData.monitors.find(m => m.name === topPanel.screen.name);
                        const wsId = monitor?.activeWorkspace?.id;
                        const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;
                        vBarItem.hasActiveWindows = hasWindow;
                    }
                }

                Timer {
                    id: showBarTimer
                    interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                    repeat: false
                    onTriggered: vBarItem.superShow = true
                }

                Connections {
                    target: GlobalStates
                    function onSuperDownChanged() {
                        if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                            return;
                        if (GlobalStates.superDown)
                            showBarTimer.restart();
                        else {
                            showBarTimer.stop();
                            vBarItem.superShow = false;
                        }
                    }
                }

                // ── Hover delay trigger ───────────────────────────────────────
                property bool hoverTriggered: false
                readonly property int hoverDelay: Config?.options.bar.autoHide.hoverDelay ?? 0

                Timer {
                    id: hoverOpenTimer
                    interval: vBarItem.hoverDelay
                    repeat: false
                    onTriggered: vBarItem.hoverTriggered = true
                }

                Connections {
                    target: hoverRegion
                    function onContainsMouseChanged() {
                        if (hoverRegion.containsMouse) {
                            if (vBarItem.hoverDelay <= 0 || (Config?.options.bar.autoHide.enable && !vBarItem.mustShow) === false || vBarItem.superShow || topPanel.leftSidebarOpenOnMonitor || topPanel.rightSidebarOpenOnMonitor) {
                                vBarItem.hoverTriggered = true;
                            } else {
                                hoverOpenTimer.restart();
                            }
                        } else {
                            hoverOpenTimer.stop();
                            vBarItem.hoverTriggered = false;
                        }
                    }
                }

                property bool superShow: false
                property bool mustShow: hoverTriggered || superShow || topPanel.leftSidebarOpenOnMonitor || topPanel.rightSidebarOpenOnMonitor

                MouseArea {
                    id: hoverRegion
                    hoverEnabled: true
                    anchors.fill: parent

                    Item {
                        id: hoverMaskRegion
                        anchors {
                            fill: barContent
                            leftMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            rightMargin: -Config.options.bar.autoHide.hoverRegionWidth
                        }
                    }

                    // A Float card fused with the bar: one fill from the card's outer edge to
                    // the bar's, standing in for the bar's own pill and shadow. At zero width
                    // it is exactly that pill, so the hand-over never shows.
                    RectangularShadow {
                        anchors.fill: barFusedFill
                        visible: barFusedFill.visible && topPanel.floatSidebarShadow
                        radius: barFusedFill.radius
                        blur: 32
                        offset: Qt.vector2d(topPanel.barOnRight ? -4 : 4, 0)
                        color: Qt.rgba(0, 0, 0, 0.28)
                    }

                    Rectangle {
                        id: barFusedFill
                        readonly property real gap: Appearance.sizes.hyprlandGapsOut
                        visible: topPanel.leftSidebarFusesBar || topPanel.rightSidebarFusesBar
                        x: topPanel.barOnRight ? barContent.x + gap : gap
                        y: barContent.y + gap
                        width: topPanel.barOnRight ? parent.width - barContent.x - 2 * gap : barContent.x + barContent.width - 2 * gap
                        height: barContent.height - 2 * gap
                        radius: topPanel.floatSidebarRadius
                        color: topPanel.floatSidebarColor
                    }

                    VBar.VerticalBarContent {
                        id: barContent
                        monitorIndex: vBarItem.monitorIndex
                        fusedToSidebar: barFusedFill.visible
                        implicitWidth: Appearance.sizes.verticalBarWindowWidth
                        width: implicitWidth
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: undefined
                            right: undefined
                            // The column ends at a top/bottom dock and the frame's band carries
                            // on under it; without the frame there is no band, so it runs on.
                            topMargin: (topPanel.usingWrappedFrame && topPanel.dockTopZone > 0) ? topPanel.dockTopZone + topPanel.ringThickness : 0
                            bottomMargin: (topPanel.usingWrappedFrame && topPanel.dockBottomZone > 0) ? topPanel.dockBottomZone + topPanel.ringThickness : 0
                        }

                        x: {
                            if (topPanel.barOnLeft) {
                                let hide = (Config?.options.bar.autoHide.enable && !vBarItem.mustShow) ? -Appearance.sizes.verticalBarWindowWidth : 0;
                                let push = (topPanel.leftSidebarActiveOnMonitor) ? GlobalStates.animatedLeftSidebarWidth : 0;
                                return hide + push;
                            } else if (topPanel.barOnRight) {
                                let hide = (Config?.options.bar.autoHide.enable && !vBarItem.mustShow) ? Appearance.sizes.verticalBarWindowWidth : 0;
                                let push = (topPanel.rightSidebarActiveOnMonitor) ? GlobalStates.animatedRightSidebarWidth : 0;
                                return parent.width - width + hide - push;
                            }
                            return 0;
                        }

                        Behavior on x {
                            enabled: !GlobalStates.sidebarLeftOpen && !GlobalStates.sidebarRightOpen && GlobalStates.animatedLeftSidebarWidth === 0 && GlobalStates.animatedRightSidebarWidth === 0
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barContent)
                        }
                    }

                    Loader {
                        id: roundDecorators
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: barContent.right
                            right: undefined
                        }
                        width: Appearance.rounding.screenRounding
                        active: vBarItem.showBarBackground && BarInteraction.cornerStyle === 0 && !topPanel.usingWrappedFrame

                        states: State {
                            name: "right"
                            when: topPanel.barBottom
                            AnchorChanges {
                                target: roundDecorators
                                anchors {
                                    top: parent.top
                                    bottom: parent.bottom
                                    left: undefined
                                    right: barContent.left
                                }
                            }
                        }

                        sourceComponent: Item {
                            implicitWidth: Appearance.rounding.screenRounding
                            RoundCorner {
                                id: topCorner
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: vBarItem.showBarBackground ? (Config.options.bar.amoledBackground ? "#000000" : Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.TopLeft
                                states: State {
                                    name: "bottom"
                                    when: topPanel.barBottom
                                    PropertyChanges {
                                        target: topCorner
                                        corner: RoundCorner.CornerEnum.TopRight
                                    }
                                }
                            }
                            RoundCorner {
                                id: bottomCorner
                                anchors {
                                    bottom: parent.bottom
                                    left: !topPanel.barBottom ? parent.left : undefined
                                    right: topPanel.barBottom ? parent.right : undefined
                                }
                                implicitSize: Appearance.rounding.screenRounding
                                color: vBarItem.showBarBackground ? (Config.options.bar.amoledBackground ? "#000000" : Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                                corner: RoundCorner.CornerEnum.BottomLeft
                                states: State {
                                    name: "bottom"
                                    when: topPanel.barBottom
                                    PropertyChanges {
                                        target: bottomCorner
                                        corner: RoundCorner.CornerEnum.BottomRight
                                    }
                                }
                            }
                        }
                    }
                }

                property alias maskItem: hoverMaskRegion
                property real hiddenAmount: (Config?.options.bar.autoHide.enable && !mustShow) ? Appearance.sizes.verticalBarWindowWidth : 0

                Behavior on hiddenAmount {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(vBarItem)
                }
            }
        }
    }

    Loader {
        id: leftSidebarShadowLoader
        active: topPanel.leftSidebarActiveOnMonitor && (!GlobalStates.connectModeActive || topPanel.isDynamicIslandTop || topPanel.isDynamicIslandBottom)
        anchors.fill: leftSidebar
        sourceComponent: Component {
            StyledDropShadow {
                target: leftSidebar
                radius: Math.round(0.9 * Appearance.sizes.elevationMargin)
                opacity: leftSidebar.opacity
            }
        }
    }

    // Space reserver for pinned sidebar in Connect Mode
    // Disabled with a horizontal Float bar — sidebars remain separate PanelWindows with own space
    PanelWindow {
        id: pinSpaceReserver
        WlrLayershell.namespace: "quickshell:pinReserver"
        exclusionMode: ExclusionMode.Normal
        color: "transparent"
        visible: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && GlobalStates.policiesPinned && !GlobalStates.policiesDetached && topPanel.policiesActiveOnMonitor
        anchors {
            top: true
            bottom: true
            left: topPanel.policiesOnLeft
            right: !topPanel.policiesOnLeft
        }
        readonly property bool besideBar: topPanel.barVertical && ((topPanel.barOnLeft && topPanel.policiesOnLeft) || (topPanel.barOnRight && !topPanel.policiesOnLeft))
        // A Float card standing alone ends a gap further out; one beside the bar ends at it.
        implicitWidth: GlobalStates.policiesWidth + (besideBar ? 0 : topPanel.floatSidebarGap)
        exclusiveZone: implicitWidth - (besideBar ? 0 : (Appearance.sizes.hyprlandGapsOut + Appearance.sizes.elevationMargin))
    }

    // The dock's tray without the wrapped frame: painted here, like the frame's band, so it
    // blurs with the sidebars instead of on its own surface, rides on a sidebar pushing the
    // dock in the same frames, and leaves the screen corners above it (the dock's own tray
    // covered them). It starts past the bar's zone on that edge, as the dock's window does.
    readonly property bool barHoldsZones: hasBarOnThisMonitor && GlobalStates.barOpen
        && !(Config.options.bar.autoHide.enable && !Config.options.bar.autoHide.pushWindows)
    readonly property real hBarZone: (barHoldsZones && !barVertical) ? Math.max(0, Appearance.sizes.baseBarHeight + (BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0) - hBarHiddenAmount) : 0
    readonly property real vBarZone: (barHoldsZones && barVertical) ? Math.max(0, Appearance.sizes.baseVerticalBarWidth + (BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0) - vBarHiddenAmount) : 0
    readonly property real leftCornerShift: dockBandPlain.side === "left" ? dockBandPlain.cornerShift : 0
    readonly property real rightCornerShift: dockBandPlain.side === "right" ? dockBandPlain.cornerShift : 0
    Rectangle {
        id: dockBandPlain
        readonly property string side: topPanel.dockInset ? topPanel.dockInset.side : ""
        readonly property real band: side === "left" ? topPanel.dockLeftBand
            : side === "right" ? topPanel.dockRightBand
            : side === "top" ? topPanel.dockTopBand
            : side === "bottom" ? topPanel.dockBottomBand : 0
        readonly property real zoneLeft: topPanel.barOnLeft ? topPanel.vBarZone : 0
        readonly property real zoneRight: topPanel.barOnRight ? topPanel.vBarZone : 0
        readonly property real zoneTop: (!topPanel.barVertical && !topPanel.barBottom) ? topPanel.hBarZone : 0
        readonly property real zoneBottom: (!topPanel.barVertical && topPanel.barBottom) ? topPanel.hBarZone : 0
        readonly property real pushLeft: topPanel.leftSidebarActiveOnMonitor ? Math.round(GlobalStates.animatedLeftSidebarWidth) : 0
        readonly property real pushRight: topPanel.rightSidebarActiveOnMonitor ? Math.round(GlobalStates.animatedRightSidebarWidth) : 0
        visible: !topPanel.usingWrappedFrame && topPanel.dockOnFrameBand && band > 0 && !topPanel.hasFullscreenWindowOnMonitor
        // Where a sidebar pushes the dock, the band sits against the sidebar's edge: the
        // sidebar's outer corners move past it, or they paint over the band - a darker wedge.
        readonly property real cornerShift: visible ? band + ((side === "left") ? zoneLeft : zoneRight) : 0
        color: Config.options.bar.expressiveColors ? topPanel.activeTheme.barBackground : Appearance.colors.colLayer0
        x: side === "left" ? zoneLeft + pushLeft
            : side === "right" ? topPanel.width - zoneRight - pushRight - band
            : zoneLeft
        y: side === "top" ? zoneTop
            : side === "bottom" ? topPanel.height - zoneBottom - band
            : zoneTop
        width: (side === "left" || side === "right") ? band : Math.max(0, topPanel.width - zoneLeft - zoneRight)
        height: (side === "left" || side === "right") ? Math.max(0, topPanel.height - zoneTop - zoneBottom) : band
    }

    // The full-width rounded style curves into the screen at both ends of its tray; the
    // dock drew those in its own tray colour, which is empty on the band.
    Repeater {
        model: (dockBandPlain.visible && (topPanel.dockInset?.concave ?? 0) > 0) ? 2 : 0
        delegate: RoundCorner {
            required property int index
            readonly property string pos: dockBandPlain.side
            readonly property bool startEnd: index === 0
            implicitSize: Math.max(1, topPanel.dockInset?.concave ?? 0)
            color: dockBandPlain.color
            corner: pos === "top" ? (startEnd ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.TopRight)
                : pos === "left" ? (startEnd ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.BottomLeft)
                : pos === "right" ? (startEnd ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.BottomRight)
                : (startEnd ? RoundCorner.CornerEnum.BottomLeft : RoundCorner.CornerEnum.BottomRight)
            x: pos === "left" ? dockBandPlain.x + dockBandPlain.width
                : pos === "right" ? dockBandPlain.x - width
                : (startEnd ? dockBandPlain.x : dockBandPlain.x + dockBandPlain.width - width)
            y: pos === "bottom" ? dockBandPlain.y - height
                : pos === "top" ? dockBandPlain.y + dockBandPlain.height
                : (startEnd ? dockBandPlain.y : dockBandPlain.y + dockBandPlain.height - height)
        }
    }

    // A Float card standing alone casts the bar's shadow; a fused one is shadowed with the bar.
    RectangularShadow {
        anchors.fill: leftSidebar
        visible: leftSidebar.visible && topPanel.floatSidebarCards && !topPanel.leftSidebarFusesBar && topPanel.floatSidebarShadow
        radius: topPanel.floatSidebarRadius
        blur: 32
        offset: Qt.vector2d(4, 0)
        color: Qt.rgba(0, 0, 0, 0.28)
    }

    // Left Sidebar Policies Content
    // Disabled with a horizontal Float bar — sidebars remain separate PanelWindows
    // A Float card grows from its outer edge, clipping the content that rides its inner one.
    Rectangle {
        id: leftSidebar
        x: topPanel.floatSidebarCards ? topPanel.floatSidebarGap : -(width - GlobalStates.animatedLeftSidebarWidth)
        y: topPanel.sidebarTopOffset + topPanel.floatSidebarGap
        width: topPanel.floatSidebarCards ? Math.round(GlobalStates.animatedLeftSidebarWidth) : Math.round(Math.max(topPanel.leftContentWidth, GlobalStates.animatedLeftSidebarWidth))
        height: Math.max(0, Math.round(parent.height - topPanel.sidebarTopOffset - topPanel.sidebarBottomOffset - 2 * topPanel.floatSidebarGap))
        color: topPanel.floatSidebarCards ? (topPanel.leftSidebarFusesBar ? "transparent" : topPanel.floatSidebarColor) : (topPanel.leftSidebarWeldedToBar ? "transparent" : (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0))
        clip: topPanel.floatSidebarCards
        readonly property bool isConnectDynamicIslandTop: GlobalStates.connectModeActive && topPanel.isDynamicIslandTop
        readonly property bool isConnectDynamicIslandBottom: GlobalStates.connectModeActive && topPanel.isDynamicIslandBottom
        readonly property bool connectSheet: GlobalStates.connectModeActive && !topPanel.floatSidebarCards
        readonly property real defaultRadius: topPanel.floatSidebarCards ? topPanel.floatSidebarRadius : (GlobalStates.connectModeActive && !topPanel.isDynamicIslandTop && !topPanel.isDynamicIslandBottom) ? 0 : Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        radius: 0
        topLeftRadius: isConnectDynamicIslandTop ? 0 : defaultRadius
        topRightRadius: isConnectDynamicIslandBottom ? 0 : defaultRadius
        bottomLeftRadius: (isConnectDynamicIslandBottom) ? 0 : (connectSheet ? 0 : defaultRadius)
        bottomRightRadius: isConnectDynamicIslandBottom ? defaultRadius : (connectSheet ? 0 : defaultRadius)
        visible: topPanel.leftSidebarActiveOnMonitor && !GlobalStates.connectSidebarsSeparate

        // GPU compositing during animation: prevents per-frame mask/Region recalc
        // which was causing Wayland surface sync stalls on every animation frame.
        // Only active DURING the open/close animation — not while the sidebar is
        // statically open. Keeping it on while open caused massive CPU usage
        // because every minor visual change (timer ticks, notification syncs,
        // infinite pulse animations, gradient behaviors) forced a full FBO
        // re-render of the entire Phone tab subtree.
        // A Float card changes size every frame, so its constant-size content takes the layer.
        layer.enabled: GlobalStates.leftSidebarAnimating && !topPanel.floatSidebarCards

        Loader {
            id: leftSidebarContentLoader
            active: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && topPanel.leftSidebarContentWanted && !(GlobalStates.policiesDetached && topPanel.policiesRenderedOnLeft)
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            width: Math.round(Math.max(topPanel.leftContentWidth, GlobalStates.animatedLeftSidebarWidth))
            layer.enabled: GlobalStates.leftSidebarAnimating && topPanel.floatSidebarCards
            sourceComponent: {
                const pos = Config.options.sidebar.position;
                if (pos === "inverted") {
                    return leftDashboardContentComponent;
                } else if (pos === "left") {
                    if (GlobalStates.dashboardPanelOpen) {
                        return leftDashboardContentComponent;
                    } else {
                        return policiesContentComponent;
                    }
                } else {
                    return policiesContentComponent;
                }
            }
            onLoaded: {
                if (item && "isLoadedOnLeft" in item) {
                    item.isLoadedOnLeft = true;
                }
            }
        }
    }

    // Detached Sidebar Policies Window
    // Disabled in Float+Connect mode — sidebars remain separate PanelWindows
    Loader {
        active: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && GlobalStates.policiesDetached && topPanel.policiesOpenOnMonitor
        sourceComponent: FloatingWindow {
            id: detachedPoliciesWindow
            title: "ii Policies"
            screen: topPanel.screen
            color: "transparent"
            visible: true
            implicitWidth: GlobalStates.policiesWidth
            implicitHeight: Math.max(0, topPanel.height - topPanel.sidebarTopOffset - topPanel.sidebarBottomOffset - (Appearance.sizes.hyprlandGapsOut * 2))

            Shortcut {
                sequence: "Ctrl+D"
                enabled: detachedPoliciesWindow.visible
                onActivated: topPanel.togglePoliciesDetach()
            }
            Shortcut {
                sequence: "Ctrl+O"
                enabled: detachedPoliciesWindow.visible
                onActivated: topPanel.togglePoliciesExtended()
            }
            Shortcut {
                sequence: "Ctrl+P"
                enabled: detachedPoliciesWindow.visible
                onActivated: topPanel.togglePoliciesPin()
            }

            onVisibleChanged: {
                if (!visible && GlobalStates.sidebarLeftOpen)
                    GlobalStates.sidebarLeftOpen = false;
            }

            Rectangle {
                anchors.fill: parent
                focus: true
                color: Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

                Loader {
                    anchors.fill: parent
                    active: true
                    sourceComponent: policiesContentComponent
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.sidebarLeftOpen = false;
                        event.accepted = true;
                        return;
                    }
                    if ((event.modifiers & Qt.ControlModifier) !== 0) {
                        if (event.key === Qt.Key_D) {
                            topPanel.togglePoliciesDetach();
                        } else if (event.key === Qt.Key_O) {
                            topPanel.togglePoliciesExtended();
                        } else if (event.key === Qt.Key_P) {
                            topPanel.togglePoliciesPin();
                        } else {
                            return;
                        }
                        event.accepted = true;
                    }
                }
            }
        }
    }

    RectangularShadow {
        anchors.fill: rightSidebar
        visible: rightSidebar.visible && topPanel.floatSidebarCards && !topPanel.rightSidebarFusesBar && topPanel.floatSidebarShadow
        radius: topPanel.floatSidebarRadius
        blur: 32
        offset: Qt.vector2d(-4, 0)
        color: Qt.rgba(0, 0, 0, 0.28)
    }

    // Right Sidebar Dashboard Content
    // Disabled with a horizontal Float bar — sidebars remain separate PanelWindows
    Rectangle {
        id: rightSidebar
        x: parent.width - topPanel.floatSidebarGap - Math.round(GlobalStates.animatedRightSidebarWidth)
        y: topPanel.sidebarTopOffset + topPanel.floatSidebarGap
        width: topPanel.floatSidebarCards ? Math.round(GlobalStates.animatedRightSidebarWidth) : Math.round(Math.max(topPanel.rightContentWidth, GlobalStates.animatedRightSidebarWidth))
        height: Math.max(0, Math.round(parent.height - topPanel.sidebarTopOffset - topPanel.sidebarBottomOffset - 2 * topPanel.floatSidebarGap))
        color: topPanel.floatSidebarCards ? (topPanel.rightSidebarFusesBar ? "transparent" : topPanel.floatSidebarColor) : (topPanel.rightSidebarWeldedToBar ? "transparent" : (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0))
        clip: topPanel.floatSidebarCards
        readonly property bool isConnectDynamicIslandTop: GlobalStates.connectModeActive && topPanel.isDynamicIslandTop
        readonly property bool isConnectDynamicIslandBottom: GlobalStates.connectModeActive && topPanel.isDynamicIslandBottom
        readonly property bool connectSheet: GlobalStates.connectModeActive && !topPanel.floatSidebarCards
        readonly property real defaultRadius: topPanel.floatSidebarCards ? topPanel.floatSidebarRadius : (GlobalStates.connectModeActive && !topPanel.isDynamicIslandTop && !topPanel.isDynamicIslandBottom) ? 0 : Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        radius: 0
        topRightRadius: isConnectDynamicIslandTop ? 0 : defaultRadius
        topLeftRadius: isConnectDynamicIslandBottom ? 0 : defaultRadius
        bottomRightRadius: (isConnectDynamicIslandBottom) ? 0 : (connectSheet ? 0 : defaultRadius)
        bottomLeftRadius: isConnectDynamicIslandBottom ? defaultRadius : (connectSheet ? 0 : defaultRadius)
        visible: topPanel.rightSidebarActiveOnMonitor && (!topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarActiveOnMonitor) && !GlobalStates.connectSidebarsSeparate

        // GPU compositing during animation: prevents per-frame mask/Region recalc
        // which was causing Wayland surface sync stalls on every animation frame.
        // Only active DURING the open/close animation — not while the sidebar is
        // statically open. Keeping it on while open caused visible seam artifacts
        // at the corner junctions because the FBO edge anti-aliasing differs from
        // direct rendering of the RoundCorner overlays.
        // A Float card changes size every frame, so its constant-size content takes the layer.
        layer.enabled: GlobalStates.rightSidebarAnimating && !topPanel.floatSidebarCards

        Loader {
            id: rightSidebarContentLoader
            active: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && topPanel.rightSidebarContentWanted && !(GlobalStates.policiesDetached && topPanel.policiesRenderedOnRight)
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            width: Math.round(Math.max(topPanel.rightContentWidth, GlobalStates.animatedRightSidebarWidth))
            layer.enabled: GlobalStates.rightSidebarAnimating && topPanel.floatSidebarCards
            sourceComponent: {
                const pos = Config.options.sidebar.position;
                if (pos === "inverted") {
                    return policiesContentComponent;
                } else if (pos === "right") {
                    if (GlobalStates.sidebarLeftOpen) {
                        return policiesContentComponent;
                    } else {
                        return rightDashboardContentComponent;
                    }
                } else {
                    return rightDashboardContentComponent;
                }
            }
            onLoaded: {
                if (item && "isLoadedOnLeft" in item) {
                    item.isLoadedOnLeft = false;
                }
            }
        }
    }

    Loader {
        id: leftSidebarTopCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && BarInteraction.cornerStyle !== 1 && !topPanel.isDynamicIslandTop && !topPanel.usingWrappedFrame && (topPanel.barBottom || BarInteraction.cornerStyle !== 0 || !hasBarOnThisMonitor)
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.leftSidebarOpenOnMonitor
        x: GlobalStates.animatedLeftSidebarWidth + topPanel.leftCornerShift
        y: topPanel.sidebarTopOffset
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.TopLeft
            color: topPanel.leftSidebarCornerColor
        }
    }

    Loader {
        id: leftSidebarOuterTopCornerShadowLoader
        active: leftSidebarOuterTopCornerLoader.active
        anchors.fill: leftSidebarOuterTopCornerLoader
        sourceComponent: Component {
            StyledDropShadow {
                target: leftSidebarOuterTopCornerLoader
                radius: Math.round(0.9 * Appearance.sizes.elevationMargin)
                opacity: leftSidebar.opacity
            }
        }
    }

    Loader {
        id: leftSidebarOuterTopCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && topPanel.isDynamicIslandTop && !topPanel.usingWrappedFrame
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.leftSidebarOpenOnMonitor
        anchors.left: leftSidebar.left
        anchors.bottom: leftSidebar.top
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.BottomLeft
            color: topPanel.leftSidebarCornerColor
        }
    }

    Loader {
        id: leftSidebarBottomCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && (!topPanel.barBottom || !hasBarOnThisMonitor) && BarInteraction.cornerStyle !== 1 && !topPanel.usingWrappedFrame && (topPanel.barVertical === topPanel.barBottom || BarInteraction.cornerStyle !== 0 || !hasBarOnThisMonitor)
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.leftSidebarOpenOnMonitor
        x: GlobalStates.animatedLeftSidebarWidth + topPanel.leftCornerShift
        anchors.bottom: parent.bottom
        anchors.bottomMargin: topPanel.sidebarBottomOffset
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.BottomLeft
            color: topPanel.leftSidebarCornerColor
        }
    }

    Loader {
        id: rightSidebarTopCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && BarInteraction.cornerStyle !== 1 && !topPanel.isDynamicIslandTop && !topPanel.usingWrappedFrame && (topPanel.barVertical !== topPanel.barBottom || BarInteraction.cornerStyle !== 0 || !hasBarOnThisMonitor)
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarOpenOnMonitor
        anchors.right: parent.right
        anchors.rightMargin: GlobalStates.animatedRightSidebarWidth + topPanel.rightCornerShift
        y: topPanel.sidebarTopOffset
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.TopRight
            color: topPanel.rightSidebarCornerColor
        }
    }

    Loader {
        id: rightSidebarOuterTopCornerShadowLoader
        active: rightSidebarOuterTopCornerLoader.active
        anchors.fill: rightSidebarOuterTopCornerLoader
        sourceComponent: Component {
            StyledDropShadow {
                target: rightSidebarOuterTopCornerLoader
                radius: Math.round(0.9 * Appearance.sizes.elevationMargin)
                opacity: rightSidebar.opacity
            }
        }
    }

    Loader {
        id: rightSidebarOuterTopCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && topPanel.isDynamicIslandTop && !topPanel.usingWrappedFrame
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarOpenOnMonitor
        anchors.right: rightSidebar.right
        anchors.bottom: rightSidebar.top
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.BottomRight
            color: topPanel.rightSidebarCornerColor
        }
    }

    Loader {
        id: rightSidebarBottomCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && (!topPanel.barBottom || !hasBarOnThisMonitor) && BarInteraction.cornerStyle !== 1 && !topPanel.usingWrappedFrame
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarOpenOnMonitor
        anchors.right: parent.right
        anchors.rightMargin: GlobalStates.animatedRightSidebarWidth + topPanel.rightCornerShift
        anchors.bottom: parent.bottom
        anchors.bottomMargin: topPanel.sidebarBottomOffset
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.BottomRight
            color: topPanel.rightSidebarCornerColor
        }
    }

    Loader {
        id: leftSidebarBottomBarCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && !topPanel.barVertical && topPanel.barBottom && (BarInteraction.cornerStyle === 0 || BarInteraction.cornerStyle === 2) && !topPanel.usingWrappedFrame && hasBarOnThisMonitor
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.leftSidebarOpenOnMonitor
        x: GlobalStates.animatedLeftSidebarWidth + topPanel.leftCornerShift
        y: parent.height - topPanel.sidebarBottomOffset - Appearance.rounding.screenRounding
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.BottomLeft
            color: topPanel.leftSidebarCornerColor
        }
    }

    Loader {
        id: rightSidebarBottomBarCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && !topPanel.barVertical && topPanel.barBottom && (BarInteraction.cornerStyle === 0 || BarInteraction.cornerStyle === 2) && !topPanel.usingWrappedFrame && hasBarOnThisMonitor
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarOpenOnMonitor
        anchors.right: parent.right
        anchors.rightMargin: GlobalStates.animatedRightSidebarWidth + topPanel.rightCornerShift
        y: parent.height - topPanel.sidebarBottomOffset - Appearance.rounding.screenRounding
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.BottomRight
            color: topPanel.rightSidebarCornerColor
        }
    }

    Loader {
        id: leftSidebarOuterBottomCornerLoader
        active: topPanel.leftSidebarActiveOnMonitor && topPanel.isDynamicIslandBottom && !topPanel.usingWrappedFrame
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.leftSidebarOpenOnMonitor
        anchors.left: leftSidebar.left
        anchors.top: leftSidebar.bottom
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.TopLeft
            color: topPanel.leftSidebarCornerColor
        }
    }

    Loader {
        id: leftSidebarOuterBottomCornerShadowLoader
        active: leftSidebarOuterBottomCornerLoader.active
        anchors.fill: leftSidebarOuterBottomCornerLoader
        sourceComponent: Component {
            StyledDropShadow {
                target: leftSidebarOuterBottomCornerLoader
                radius: Math.round(0.9 * Appearance.sizes.elevationMargin)
                opacity: leftSidebar.opacity
            }
        }
    }

    Loader {
        id: rightSidebarOuterBottomCornerLoader
        active: topPanel.rightSidebarActiveOnMonitor && topPanel.isDynamicIslandBottom && !topPanel.usingWrappedFrame
        visible: !topPanel.hasFullscreenWindowOnMonitor || topPanel.rightSidebarOpenOnMonitor
        anchors.right: rightSidebar.right
        anchors.top: rightSidebar.bottom
        width: Appearance.rounding.screenRounding
        height: Appearance.rounding.screenRounding
        sourceComponent: RoundCorner {
            implicitSize: Appearance.rounding.screenRounding
            corner: RoundCorner.CornerEnum.TopRight
            color: topPanel.rightSidebarCornerColor
        }
    }

    Loader {
        id: rightSidebarOuterBottomCornerShadowLoader
        active: rightSidebarOuterBottomCornerLoader.active
        anchors.fill: rightSidebarOuterBottomCornerLoader
        sourceComponent: Component {
            StyledDropShadow {
                target: rightSidebarOuterBottomCornerLoader
                radius: Math.round(0.9 * Appearance.sizes.elevationMargin)
                opacity: rightSidebar.opacity
            }
        }
    }

    // 4. Search Drop (Connect Mode integration)
    Loader {
        id: searchDropLoader
        z: 10
        active: !GlobalStates.screenLocked && !topPanel.searchDropSuppressed
        focus: searchOpenOnMonitor
        sourceComponent: Component {
            SearchConnect.SearchDrop {
                id: searchDrop
                screen: topPanel.screen
                monitorIndex: Quickshell.screens.indexOf(topPanel.screen)
                panelWindow: topPanel
                barVertical: topPanel.barVertical
                barBottom: topPanel.barBottom
                barOnLeft: topPanel.barOnLeft
                barOnRight: topPanel.barOnRight
                usingWrappedFrame: topPanel.usingWrappedFrame
                frameThickness: Config.options.appearance.wrappedFrameThickness
                barHeight: hasBarOnThisMonitor ? Appearance.sizes.barHeight : 0
                verticalBarWidth: hasBarOnThisMonitor ? Appearance.sizes.verticalBarWindowWidth : 0
                barMargin: topPanel.barMargin
                hBarHiddenAmount: topPanel.hBarHiddenAmount
                vBarHiddenAmount: topPanel.vBarHiddenAmount
                animatedLeftSidebarWidth: GlobalStates.animatedLeftSidebarWidth
                animatedRightSidebarWidth: GlobalStates.animatedRightSidebarWidth
                leftSidebarActiveOnMonitor: topPanel.leftSidebarActiveOnMonitor
                rightSidebarActiveOnMonitor: topPanel.rightSidebarActiveOnMonitor
            }
        }
    }

    // 5. OSD Drop (Connect Mode integration)
    Loader {
        id: osdDropLoader
        z: 11
        // Only the horizontal Dynamic Island renders its own OSD.
        active: GlobalStates.osdConnectActive && !GlobalStates.screenLocked && !(Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material" || Config.options.osd.style === "tuner")) && !(Config.ready && !BarPlacement.vertical && BarInteraction.cornerStyle === 3) && !(Config.ready && Config.options.bar.dynamicIsland.notchMode.enable) && !IslandPolicy.ownsOsd
        sourceComponent: Component {
            OsdConnect.OsdDrop {
                screen: topPanel.screen
                panelWindow: topPanel
                barVertical: topPanel.barVertical
                barBottom: topPanel.barBottom
                barOnLeft: topPanel.barOnLeft
                barOnRight: topPanel.barOnRight
                usingWrappedFrame: topPanel.usingWrappedFrame
                frameThickness: Config.options.appearance.wrappedFrameThickness
                barHeight: hasBarOnThisMonitor ? Appearance.sizes.barHeight : 0
                verticalBarWidth: hasBarOnThisMonitor ? Appearance.sizes.verticalBarWindowWidth : 0
                barMargin: topPanel.barMargin
                hBarHiddenAmount: topPanel.hBarHiddenAmount
                vBarHiddenAmount: topPanel.vBarHiddenAmount
                animatedLeftSidebarWidth: GlobalStates.animatedLeftSidebarWidth
                animatedRightSidebarWidth: GlobalStates.animatedRightSidebarWidth
                leftSidebarActiveOnMonitor: topPanel.leftSidebarActiveOnMonitor
                rightSidebarActiveOnMonitor: topPanel.rightSidebarActiveOnMonitor
                hasFullscreenWindow: topPanel.hasFullscreenWindowOnMonitor
            }
        }
    }

    // Static items for input masking to avoid per-frame Region recalculations
    Item {
        id: leftSidebarMaskItem
        x: 0
        y: topPanel.sidebarTopOffset
        width: (GlobalStates.animatedLeftSidebarWidth > 0 && topPanel.leftSidebarWarmOnMonitor) ? topPanel.leftSidebarMaskWidth + topPanel.floatSidebarGap : 0
        height: parent.height - topPanel.sidebarTopOffset - topPanel.sidebarBottomOffset
    }

    Item {
        id: rightSidebarMaskItem
        x: parent.width - width
        y: topPanel.sidebarTopOffset
        width: (GlobalStates.animatedRightSidebarWidth > 0 && topPanel.rightSidebarWarmOnMonitor) ? topPanel.rightSidebarMaskWidth + topPanel.floatSidebarGap : 0
        height: parent.height - topPanel.sidebarTopOffset - topPanel.sidebarBottomOffset
    }

    // Static corner mask items to prevent per-frame Region recalculation
    Item {
        id: leftSidebarTopCornerMaskItem
        x: topPanel.leftSidebarMaskWidth
        y: topPanel.sidebarTopOffset
        width: leftSidebarTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: leftSidebarTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: leftSidebarOuterTopCornerMaskItem
        x: leftSidebar.x
        y: topPanel.sidebarTopOffset - (leftSidebarOuterTopCornerLoader.active ? Appearance.rounding.screenRounding : 0)
        width: leftSidebarOuterTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: leftSidebarOuterTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: leftSidebarBottomCornerMaskItem
        x: topPanel.leftSidebarMaskWidth
        y: topPanel.height - topPanel.sidebarBottomOffset - (leftSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0)
        width: leftSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: leftSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: rightSidebarTopCornerMaskItem
        x: topPanel.width - topPanel.rightSidebarMaskWidth - width
        y: topPanel.sidebarTopOffset
        width: rightSidebarTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: rightSidebarTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: rightSidebarOuterTopCornerMaskItem
        x: rightSidebar.x + rightSidebar.width - width
        y: topPanel.sidebarTopOffset - (rightSidebarOuterTopCornerLoader.active ? Appearance.rounding.screenRounding : 0)
        width: rightSidebarOuterTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: rightSidebarOuterTopCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: rightSidebarBottomCornerMaskItem
        x: topPanel.width - topPanel.rightSidebarMaskWidth - width
        y: topPanel.height - topPanel.sidebarBottomOffset - height
        width: rightSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: rightSidebarBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: leftSidebarBottomBarCornerMaskItem
        x: topPanel.leftSidebarMaskWidth
        y: parent.height - topPanel.sidebarBottomOffset - (leftSidebarBottomBarCornerLoader.active ? Appearance.rounding.screenRounding : 0)
        width: leftSidebarBottomBarCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: leftSidebarBottomBarCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: rightSidebarBottomBarCornerMaskItem
        x: topPanel.width - topPanel.rightSidebarMaskWidth - width
        y: parent.height - topPanel.sidebarBottomOffset - (rightSidebarBottomBarCornerLoader.active ? Appearance.rounding.screenRounding : 0)
        width: rightSidebarBottomBarCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: rightSidebarBottomBarCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: leftSidebarOuterBottomCornerMaskItem
        x: leftSidebar.x
        y: leftSidebar.y + leftSidebar.height
        width: leftSidebarOuterBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: leftSidebarOuterBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    Item {
        id: rightSidebarOuterBottomCornerMaskItem
        x: rightSidebar.x + rightSidebar.width - width
        y: rightSidebar.y + rightSidebar.height
        width: rightSidebarOuterBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
        height: rightSidebarOuterBottomCornerLoader.active ? Appearance.rounding.screenRounding : 0
    }

    // Static mask item for search drop bounds
    Item {
        id: searchDropMaskItem
        visible: searchDropLoader.active && searchDropLoader.item && searchDropLoader.item.isWidgetActive
        x: {
            if (searchDropLoader.item && searchDropLoader.item.coversScreen)
                return 0;
            return searchDropLoader.item ? searchDropLoader.item.x + (searchDropLoader.item.maskItem ? searchDropLoader.item.maskItem.x : 0) : 0;
        }
        y: {
            if (searchDropLoader.item && searchDropLoader.item.coversScreen)
                return 0;
            return searchDropLoader.item ? searchDropLoader.item.y + (searchDropLoader.item.maskItem ? searchDropLoader.item.maskItem.y : 0) : 0;
        }
        width: {
            if (searchDropLoader.item && searchDropLoader.item.coversScreen)
                return topPanel.width;
            return searchDropLoader.item ? (searchDropLoader.item.maskItem ? searchDropLoader.item.maskItem.width : 0) : 0;
        }
        height: {
            if (searchDropLoader.item && searchDropLoader.item.coversScreen)
                return topPanel.height;
            return searchDropLoader.item ? (searchDropLoader.item.maskItem ? searchDropLoader.item.maskItem.height : 0) : 0;
        }
    }

    // Static mask item for OSD drop bounds
    Item {
        id: osdDropMaskItem
        visible: osdDropLoader.active && osdDropLoader.item && osdDropLoader.item.isWidgetActive
        x: osdDropLoader.item ? osdDropLoader.item.x + (osdDropLoader.item.maskItem ? osdDropLoader.item.maskItem.x : 0) : 0
        y: osdDropLoader.item ? osdDropLoader.item.y + (osdDropLoader.item.maskItem ? osdDropLoader.item.maskItem.y : 0) : 0
        width: osdDropLoader.item ? (osdDropLoader.item.maskItem ? osdDropLoader.item.maskItem.width : 0) : 0
        height: osdDropLoader.item ? (osdDropLoader.item.maskItem ? osdDropLoader.item.maskItem.height : 0) : 0
    }

    // Mask region definitions
    mask: Region {
        Region {
            // Bar horizontal
            item: !topPanel.lockTransitionActive && (horizontalBarLoader.item && horizontalBarLoader.item.maskItem) ? horizontalBarLoader.item.maskItem : null
        }
        Region {
            // Bar vertical
            item: !topPanel.lockTransitionActive && (verticalBarLoader.item && verticalBarLoader.item.maskItem) ? verticalBarLoader.item.maskItem : null
        }
        Region {
            // Frame
            regions: !topPanel.lockTransitionActive && frameLoader.item ? [frameLoader.item.frameMask] : []
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.leftSidebarWarmOnMonitor) ? leftSidebarMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.rightSidebarWarmOnMonitor) ? rightSidebarMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.leftSidebarWarmOnMonitor) ? leftSidebarTopCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.leftSidebarWarmOnMonitor) ? leftSidebarOuterTopCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.leftSidebarWarmOnMonitor) ? leftSidebarBottomCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.rightSidebarWarmOnMonitor) ? rightSidebarTopCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.rightSidebarWarmOnMonitor) ? rightSidebarOuterTopCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.rightSidebarWarmOnMonitor) ? rightSidebarBottomCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.leftSidebarWarmOnMonitor) ? leftSidebarBottomBarCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.leftSidebarWarmOnMonitor) ? leftSidebarOuterBottomCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.rightSidebarWarmOnMonitor) ? rightSidebarBottomBarCornerMaskItem : null
        }
        Region {
            item: (!GlobalStates.connectSidebarsSeparate && topPanel.rightSidebarWarmOnMonitor) ? rightSidebarOuterBottomCornerMaskItem : null
        }
        Region {
            // Search drop
            item: searchDropMaskItem
        }
        Region {
            // OSD drop
            item: osdDropMaskItem
        }
    }

    function updateFocusGrab() {
        if (GlobalStates.connectSidebarsSeparate) {
            GlobalFocusGrab.removeDismissable(topPanel);
            return;
        }

        var shouldGrab = false;

        // Left sidebar on this monitor
        if (GlobalStates.sidebarLeftOpen && screen.name === GlobalStates.effectiveLeftMonitor) {
            if (topPanel.policiesOnLeft) {
                if (!GlobalStates.policiesDetached && !GlobalStates.policiesPinned) {
                    shouldGrab = true;
                }
            } else {
                shouldGrab = true;
            }
        }

        // Right sidebar on this monitor
        if (GlobalStates.sidebarRightOpen && screen.name === GlobalStates.effectiveRightMonitor) {
            if (!topPanel.policiesOnLeft) {
                if (!GlobalStates.policiesDetached && !GlobalStates.policiesPinned) {
                    shouldGrab = true;
                }
            } else {
                shouldGrab = true;
            }
        }

        if (shouldGrab) {
            GlobalFocusGrab.addDismissable(topPanel);
        } else {
            GlobalFocusGrab.removeDismissable(topPanel);
        }
    }

    Component.onDestruction: {
        GlobalFocusGrab.removeDismissable(topPanel);
        GlobalStates.setDockBand(topPanel.screen.name, false);
    }

    Connections {
        target: GlobalStates
        function onPoliciesPinnedChanged() {
            topPanel.updateFocusGrab();
        }
        function onPoliciesDetachedChanged() {
            topPanel.updateFocusGrab();
        }
        function onSidebarRightOpenChanged() {
            topPanel.updateFocusGrab();
        }
        function onSidebarLeftOpenChanged() {
            topPanel.updateFocusGrab();
        }
        function onConnectSidebarsSeparateChanged() {
            topPanel.updateFocusGrab();
        }
    }

    Connections {
        target: GlobalFocusGrab
        function onDismissed() {
            // In Float+Connect mode, sidebars handle their own dismissal
            if (GlobalStates.connectSidebarsSeparate)
                return;
            if (GlobalStates.sidebarRightOpen && topPanel.screen.name === GlobalStates.effectiveRightMonitor) {
                if (topPanel.policiesOnLeft)
                    GlobalStates.sidebarRightOpen = false;
                else if (!GlobalStates.policiesDetached && !GlobalStates.policiesPinned)
                    GlobalStates.sidebarRightOpen = false;
            }
            if (GlobalStates.sidebarLeftOpen && topPanel.screen.name === GlobalStates.effectiveLeftMonitor) {
                // A file dialog or the region snip the sidebar itself opened
                // holds it there until it is done.
                if (!topPanel.policiesOnLeft) {
                    GlobalStates.sidebarLeftOpen = false;
                } else if (!GlobalStates.policiesDetached && (!GlobalStates.policiesPinned && GlobalStates.policiesHoldOpen === 0)) {
                    GlobalStates.sidebarLeftOpen = false;
                }
            }
        }
    }

    // A pinned vertical dock pushed by a sidebar, drawn here for the slide so it moves
    // in the same frames as the sidebar (see GlobalStates.dockPushCopies).
    Image {
        id: dockPushCopy
        readonly property var copy: GlobalStates.dockPushCopies[topPanel.screen.name] ?? null
        visible: !!copy
        z: 1000
        source: copy ? copy.url : ""
        cache: false
        asynchronous: false
        width: copy ? copy.width : 0
        height: copy ? copy.height : 0
        y: copy ? copy.y : 0
        x: {
            if (!copy)
                return 0;
            if (copy.side === "left")
                return copy.inset + Math.round(GlobalStates.animatedLeftSidebarWidth);
            return topPanel.width - copy.inset - copy.width - Math.round(GlobalStates.animatedRightSidebarWidth);
        }
        readonly property bool ready: visible && status === Image.Ready
        // A swapped frame is not yet a presented one: the dock hid a frame early and blinked.
        property int framesOut: 0
        onReadyChanged: {
            framesOut = 0;
            if (!ready)
                GlobalStates.setDockPushCopyShown(topPanel.screen.name, false);
        }

        Connections {
            target: dockPushCopy.ready && !GlobalStates.dockPushCopyShown[topPanel.screen.name] ? dockPushCopy.Window.window : null
            function onFrameSwapped() {
                if (++dockPushCopy.framesOut >= 2)
                    GlobalStates.setDockPushCopyShown(topPanel.screen.name, true);
            }
        }
    }

    Item {
        id: keyFocusHandler
        focus: (topPanel.policiesOpenOnMonitor && !GlobalStates.policiesDetached) || (rightSidebarOpenOnMonitor && !(GlobalStates.policiesDetached && topPanel.policiesRenderedOnRight)) || searchOpenOnMonitor
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                GlobalStates.sidebarRightOpen = false;
                if (!GlobalStates.policiesDetached) {
                    GlobalStates.sidebarLeftOpen = false;
                }
                if (searchOpenOnMonitor) {
                    GlobalStates.overviewOpen = false;
                }
                event.accepted = true;
            }

            if ((event.modifiers & Qt.ControlModifier) !== 0 && topPanel.policiesOpenOnMonitor && !GlobalStates.policiesDetached) {
                if (event.key === Qt.Key_O) {
                    topPanel.togglePoliciesExtended();
                } else if (event.key === Qt.Key_D) {
                    topPanel.togglePoliciesDetach();
                } else if (event.key === Qt.Key_P) {
                    topPanel.togglePoliciesPin();
                } else {
                    return;
                }
                event.accepted = true;
            }
        }
    }
}
