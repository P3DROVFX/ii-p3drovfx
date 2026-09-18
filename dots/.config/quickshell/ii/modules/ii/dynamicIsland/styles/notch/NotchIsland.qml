pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.shared
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.overview

/**
 * The notch: one surface hanging from the top edge, driven by the engine.
 *
 * Visually this is the island users already have. What changed is underneath: presence
 * comes from sources, priority and geometry from IslandRegistry, and the choice of what
 * to show from IslandController with a single slot. The old panel did all of that inline,
 * which is why a new activity meant editing four ladders and why the same question ("is
 * this widget on?") had several different answers.
 *
 * A single slot means everything the controller cannot place goes to overflow, which this
 * surface renders as the pager dots at the bottom - the same affordance the old notch had,
 * now fed by the arbitration instead of a hand-maintained list.
 */
Scope {
    id: root

    readonly property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(win.screen)

    // ── What to show ─────────────────────────────────────────────────────────
    IslandController {
        id: controller
        maxIslands: 1
        expandedId: root.expanded ? root.pagedId : ""
    }

    /**
     * The activity on screen.
     *
     * Normally whatever the controller put in the centre, but a manual page turn wins
     * until the user stops paging - otherwise the wheel would fight the arbitration.
     */
    readonly property string pagedId: {
        if (root.pagerId !== "" && root.pagerIndex >= 0)
            return root.pagerId;
        return controller.centerId;
    }
    property string pagerId: ""
    property int pagerIndex: -1

    /** Centre plus overflow, in arbitration order: what the pager can walk through. */
    readonly property var pageIds: {
        const ids = [];
        if (controller.centerId !== "")
            ids.push(controller.centerId);
        const overflow = controller.overflowIds;
        for (let i = 0; i < overflow.length; i++)
            ids.push(overflow[i]);
        return ids;
    }

    function pageBy(delta) {
        const ids = root.pageIds;
        if (ids.length <= 1)
            return;
        const current = ids.indexOf(root.pagedId);
        const next = Math.max(0, Math.min(ids.length - 1, (current === -1 ? 0 : current) + delta));
        root.pagerIndex = next;
        root.pagerId = ids[next];
        pagerReleaseTimer.restart();
    }

    // A manual page is a temporary override: once the user leaves it alone, arbitration
    // takes the centre back rather than leaving the island parked on an old activity.
    property Timer pagerReleaseTimer: Timer {
        interval: 6000
        repeat: false
        onTriggered: {
            root.pagerId = "";
            root.pagerIndex = -1;
        }
    }

    // ── Hover and expansion ──────────────────────────────────────────────────
    readonly property bool clickToExpand: Config.options.bar.floatingNotch.clickToExpand ?? false
    property bool clickedExpanded: false
    readonly property bool expanded: root.clickToExpand ? root.clickedExpanded : hoverIntent.engaged
    readonly property bool hasExpanded: root.pagedId !== "" && root.pagedId !== "clock"
        && root.pagedId !== "search" && root.pagedId !== "osd"

    IslandHoverIntent {
        id: hoverIntent
        hovered: containerHover.hovered
        // `velocity.length` is a *method* on the vector, not a number: assigning it
        // silently handed a function to a real property. Magnitude, in px/ms.
        pointerSpeed: {
            const v = containerHover.point.velocity;
            if (!v)
                return 0;
            return Math.sqrt(v.x * v.x + v.y * v.y) / 1000;
        }
        dwellMs: 0            // the notch expands on hover with no dwell, as it always has
        graceMs: 1500         // ...and takes its time closing, so reaching inside is safe
    }

    // Sources hold their TTL open while the pointer is on them, so reading a notch
    // never races its own timer.
    onPagedIdChanged: controller.sources.setHovered(root.pagedId, hoverIntent.hovered)
    Connections {
        target: hoverIntent
        function onHoveredChanged() {
            controller.sources.setHovered(root.pagedId, hoverIntent.hovered);
        }
    }

    // ── Search ───────────────────────────────────────────────────────────────
    readonly property bool searchActive: root.pagedId === "search"

    /**
     * The overview sits below the notch while search is open, and its entry/exit is
     * animated, so the window has to stay tall enough to contain it for the whole
     * transition - not only while search is technically active.
     */
    readonly property bool overviewVisible: root.searchActive
        && LauncherSearch.query === ""
        && !GlobalStates.searchOnlyMode
        && !Config.options.search.alwaysListApps
        && (Config.options.overview.enable ?? true)
    readonly property string overviewAnimStyle: Config.options.overview.animationStyle ?? "bounce"
    property real overviewReveal: root.overviewVisible ? 1.0 : 0.0
    property real overviewFade: root.overviewVisible ? 1.0 : 0.0
    readonly property bool overviewAnimating: root.searchActive || root.overviewReveal > 0.001 || root.overviewFade > 0.001
    readonly property bool scrollingLayout: Persistent.states.hyprland.layout === "scrolling"

    Behavior on overviewReveal {
        NumberAnimation {
            duration: root.overviewAnimStyle === "none" ? 0
                : Math.round((root.overviewVisible ? 420 : 260) * Appearance.animMultiplier)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.overviewVisible
                ? Appearance.animationCurves.expressiveFastSpatial
                : Appearance.animationCurves.emphasizedAccel
        }
    }

    Behavior on overviewFade {
        NumberAnimation {
            duration: root.overviewAnimStyle === "none" ? 0
                : Math.round((root.overviewVisible ? 420 : 260) * Appearance.animMultiplier)
            easing.type: root.overviewVisible ? Easing.OutCubic : Easing.InCubic
        }
    }

    // ── Geometry ─────────────────────────────────────────────────────────────
    readonly property string presentation: (root.expanded && root.hasExpanded) ? "expanded" : "compact"
    readonly property bool compactProfile: Config.options.bar.floatingNotch.extraCompact ?? false
    readonly property real compactHeightMul: root.compactProfile ? 0.75 : 1.0
    readonly property real compactWidthMul: root.compactProfile ? 1.3 : 1.0

    readonly property real targetWidth: {
        if (root.searchActive)
            return notchContent.searchImplicitWidth > 0 ? notchContent.searchImplicitWidth : 420;
        if (root.pagedId === "")
            return 180 * root.compactWidthMul;
        const width = IslandRegistry.widthFor(root.pagedId, root.presentation);
        return root.presentation === "expanded" ? width : width * root.compactWidthMul;
    }

    readonly property real targetHeight: {
        if (root.searchActive) {
            const wanted = notchContent.searchImplicitHeight;
            const cap = win.screen ? win.screen.height * 0.7 : 600;
            return wanted > 0 ? Math.min(cap, wanted) : 54;
        }
        if (root.pagedId === "")
            return (Config.options.bar.floatingNotch.heightHome ?? 36) * root.compactHeightMul;
        const height = IslandRegistry.heightFor(root.pagedId, root.presentation);
        return root.presentation === "expanded" ? height : height * root.compactHeightMul;
    }

    // ── Placement ────────────────────────────────────────────────────────────
    readonly property bool centerInBar: IslandPolicy.centerInBar
    readonly property bool hasBarHere: GlobalStates.isScreenAllowedForBar(win.screen)
    readonly property bool hasTopBar: GlobalStates.barOpen && !BarPlacement.vertical && !BarPlacement.bottom && root.hasBarHere
    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3
        && (!Config.options.bar.onlyShowOnSingleMonitor || root.hasBarHere)

    readonly property bool fullscreenHere: {
        if (!win.screen)
            return false;
        const workspaces = Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === win.screen.name);
        return workspaces.some(w => w.active && w.toplevels.values.some(t => t.wayland && t.wayland.fullscreen));
    }

    readonly property bool autoHide: Config.options.bar.floatingNotch.autoHide ?? false
    property bool rightClickHidden: false
    property bool edgeRevealed: false

    /**
     * Slid out of view.
     *
     * In bar-centre mode the notch never slides: it grows and shrinks in place, because
     * anything that leaves the bar's centre empty for a frame shows a hole in the bar.
     */
    readonly property bool hidden: {
        if (root.searchActive)
            return false;
        // A drop target has to be visible to be a target, and no hover signal arrives
        // during a drag to reveal it.
        if (controller.sources.localSend.dragHovering)
            return false;
        if (root.fullscreenHere || root.rightClickHidden)
            return true;
        if (root.autoHide)
            return !root.edgeRevealed && !hoverIntent.hovered && !root.hasLiveActivity;
        if (root.centerInBar)
            return false;
        // Without auto-hide only the resting face hides, so the island is not a
        // permanent bar the user never asked for.
        return root.pagedId === "" || root.pagedId === "clock" ? !root.edgeRevealed && !hoverIntent.hovered : false;
    }

    /** Something is genuinely happening, as opposed to the clock being on screen. */
    readonly property bool hasLiveActivity: controller.activities.some(activity => activity.id !== "clock")

    property Timer edgeHideTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: root.edgeRevealed = false
    }

    readonly property int centerBarOpenMs: Math.round(450 * Appearance.animMultiplier)
    readonly property int centerBarCloseMs: Math.round(280 * Appearance.animMultiplier)
    property real centerBarProgress: (root.centerInBar && !root.hidden) ? 1.0 : 0.0
    Behavior on centerBarProgress {
        enabled: root.centerInBar
        NumberAnimation {
            duration: root.centerInBar && !root.hidden ? root.centerBarOpenMs : root.centerBarCloseMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }

    PanelWindow {
        id: win

        screen: {
            if (!Config.options.bar.floatingNotch.onlyShowOnSingleMonitor) {
                const focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
                return Quickshell.screens.find(s => s.name === focused)
                    ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
            }
            const pinned = Config.options.bar.floatingNotch.singleMonitorName;
            return Quickshell.screens.find(s => s.name === pinned)
                ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null);
        }

        visible: !GlobalStates.screenLocked
        color: "transparent"
        // Tall enough for the overview while search is open, otherwise just the notch
        // and the room its expanded state needs.
        implicitHeight: (root.searchActive || root.overviewAnimating)
            ? (win.screen ? win.screen.height : 1080)
            : 240

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:floatingNotch"
        // Search is the only state that types, so it is the only one that takes the
        // keyboard - a notch that holds focus while merely showing a track would swallow
        // every shortcut in the session.
        WlrLayershell.keyboardFocus: root.searchActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            left: true
            right: true
        }

        // Only the shape itself takes input: the rest of this window sits over the
        // user's desktop and must stay click-through. While hidden, all that is left is
        // the sliver at the screen edge that reveals it again.
        mask: Region {
            item: {
                if (root.hidden)
                    return edgeSensor;
                // The overview fills the window, so the whole surface has to accept
                // input while it is on screen.
                return root.overviewVisible ? fullWindow : maskTarget;
            }
        }

        Item {
            id: fullWindow
            anchors.fill: parent
        }

        HyprlandFocusGrab {
            windows: [win]
            active: root.searchActive
        }

        Item {
            id: maskTarget
            anchors.horizontalCenter: container.horizontalCenter
            anchors.top: container.top
            width: container.width
            height: container.height
        }

        Item {
            id: container

            anchors.horizontalCenter: parent.horizontalCenter
            width: root.targetWidth + 2 * notchShape.topRadius
            height: root.centerInBar ? root.centerBarProgress * root.targetHeight : root.targetHeight

            y: {
                if (root.hidden && !root.centerInBar)
                    return -root.targetHeight - 10;
                if (root.hasTopBar && !root.centerInBar)
                    return Appearance.sizes.barHeight;
                if (root.usingWrappedFrame)
                    return Config.options.appearance.wrappedFrameThickness;
                return 0;
            }

            // One interceptor per property. `centerInBar` picks the timing inside each
            // behaviour rather than adding a second one - two Behaviours on the same
            // property log "Attempting to set another interceptor" and the second is
            // silently ignored.
            Behavior on width {
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.9
                }
            }

            Behavior on height {
                NumberAnimation {
                    duration: root.centerInBar
                        ? (root.hidden ? root.centerBarCloseMs : root.centerBarOpenMs)
                        : 500
                    easing.type: root.centerInBar ? Easing.BezierSpline : Easing.OutBack
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    easing.overshoot: 0.5
                }
            }

            Behavior on y {
                enabled: !root.centerInBar
                NumberAnimation {
                    duration: 330
                    easing.type: Easing.OutBack
                    easing.overshoot: root.hidden ? 0.9 : 0.3
                }
            }

            // The bar lays its widget groups out around this; see IslandGeometry.
            Binding {
                target: IslandGeometry
                property: "centerWidth"
                value: root.centerInBar ? container.width : 0
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: IslandGeometry
                property: "centerHeight"
                value: root.centerInBar ? container.height : 0
                restoreMode: Binding.RestoreBindingOrValue
            }

            Notch {
                id: notchShape
                anchors.fill: parent
                bodyWidth: parent.width
                bodyHeight: parent.height
                disableBehaviors: true

                topRadius: {
                    if (root.compactProfile)
                        return Math.max(12, Math.round(root.targetHeight * 0.5));
                    if (root.centerInBar)
                        return Math.min(Appearance.rounding.large, container.height * 0.8);
                    return (root.expanded && root.hasExpanded) ? Appearance.rounding.verylarge : Appearance.rounding.large;
                }
                bottomRadius: {
                    if (root.compactProfile)
                        return 22;
                    if (root.centerInBar)
                        return Math.min(Appearance.rounding.windowRounding, container.height);
                    return (root.expanded && root.hasExpanded) ? Appearance.rounding.large : Appearance.rounding.windowRounding;
                }

                fillColor: Config.options.bar.expressiveColors
                    ? barThemes.getTheme(Config.options.bar.expressiveColorTheme).barBackground
                    : Appearance.colors.colLayer0

                layer.enabled: (Config.options.bar.floatingNotch.dropShadow ?? false) && !root.hidden
                layer.smooth: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, root.expanded ? 0.65 : 0.45)
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    shadowBlur: root.expanded ? 2.4 : 1.8
                }
            }

            /**
             * Dropping files on the island hands them to LocalSend or KDE Connect.
             *
             * The source is told a drag is hovering so the activity stays up for the
             * whole gesture: a drop target that disappears as the pointer arrives is
             * worse than none. `HoverHandler` does not fire during a drag, which is why
             * this is a DropArea and not hover state.
             */
            DropArea {
                id: fileDrop
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(parent.width, root.targetWidth + 60)
                keys: ["text/uri-list"]
                enabled: IslandPolicy.widgetEnabled("localSend") && LocalSend.available

                onEntered: drag => drag.accept(Qt.CopyAction)

                onDropped: drop => {
                    if (!drop.hasUrls)
                        return;
                    const kdeReady = IslandPolicy.kdeConnectColumnEnabled
                        && typeof KdeConnectService !== "undefined"
                        && KdeConnectService.available
                        && KdeConnectService.activeReachable
                        && KdeConnectService.activeDevice;
                    // Which half of the island the files landed on picks the service.
                    const useKde = kdeReady && drop.x >= fileDrop.width / 2;
                    controller.sources.localSend.serviceChoice = useKde ? 2 : 1;
                    if (!useKde) {
                        for (let i = 0; i < drop.urls.length; i++)
                            LocalSend.addDroppedFile(drop.urls[i]);
                        LocalSend.startScanning();
                    }
                    drop.accept(Qt.CopyAction);
                }
            }

            Binding {
                target: controller.sources.localSend
                property: "dragHovering"
                value: fileDrop.containsDrag
            }

            HoverHandler {
                id: containerHover
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                enabled: root.clickToExpand
                onTapped: root.clickedExpanded = !root.clickedExpanded
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: root.rightClickHidden = true
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    if (root.pageIds.length <= 1)
                        return;
                    root.pageBy(event.angleDelta.y > 0 ? -1 : 1);
                    event.accepted = true;
                }
            }

            // Content is clipped to the straight part of the shape: the concave
            // shoulders belong to the silhouette, and anything drawn into them is cut
            // off at an angle.
            Item {
                id: contentClip
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Math.max(0, parent.width - 2 * notchShape.topRadius)
                clip: true

                NotchContent {
                    id: notchContent
                    anchors.fill: parent
                    activityId: root.pagedId
                    expanded: root.expanded && root.hasExpanded
                    controller: controller
                }
            }

            // Pager dots for whatever the single slot could not show. The old notch had
            // these too; here they are simply the controller's overflow.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 3
                spacing: 4
                visible: root.pageIds.length > 1 && !root.expanded
                    && !root.searchActive && root.pagedId !== "osd"
                opacity: visible ? 1 : 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Repeater {
                    model: root.pageIds
                    delegate: Rectangle {
                        required property string modelData
                        width: modelData === root.pagedId ? 10 : 4
                        height: 4
                        radius: height / 2
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: modelData === root.pagedId ? 1.0 : 0.45

                        Behavior on width {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }

        Loader { // Classic overview
            id: overviewLoader
            anchors.top: container.bottom
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            active: root.overviewAnimating && !root.scrollingLayout
            visible: opacity > 0.01
            opacity: root.overviewFade

            transform: [
                Translate {
                    y: root.overviewAnimStyle === "none" ? 0
                        : (root.overviewAnimStyle === "zoom"
                            ? ((1.0 - root.overviewFade) * -30)
                            : ((1.0 - root.overviewReveal) * 30))
                },
                Scale {
                    origin.x: overviewLoader.implicitWidth / 2
                    origin.y: overviewLoader.implicitHeight / 2
                    xScale: root.overviewAnimStyle === "zoom" ? (0.92 + 0.08 * root.overviewFade) : 1.0
                    yScale: root.overviewAnimStyle === "zoom" ? (0.92 + 0.08 * root.overviewFade) : 1.0
                }
            ]

            sourceComponent: OverviewWidget {
                panelWindow: win
                monitorIndex: Quickshell.screens.indexOf(win.screen)
            }
        }

        Loader { // Scrolling overview
            id: scrollingOverviewLoader
            anchors.top: container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            active: root.overviewAnimating && root.scrollingLayout
            visible: opacity > 0.01
            opacity: root.overviewFade

            transform: [
                Translate {
                    y: root.overviewAnimStyle === "none" ? 0
                        : (root.overviewAnimStyle === "zoom"
                            ? ((1.0 - root.overviewFade) * -30)
                            : ((1.0 - root.overviewReveal) * 30))
                },
                Scale {
                    origin.x: scrollingOverviewLoader.width / 2
                    origin.y: scrollingOverviewLoader.height / 2
                    xScale: root.overviewAnimStyle === "zoom" ? (0.92 + 0.08 * root.overviewFade) : 1.0
                    yScale: root.overviewAnimStyle === "zoom" ? (0.92 + 0.08 * root.overviewFade) : 1.0
                }
            ]

            sourceComponent: ScrollingOverviewWidget {
                anchors.fill: parent
                panelWindow: win
                monitorIndex: Quickshell.screens.indexOf(win.screen)
            }
        }

        // Reveals the notch again after it slid away, and the only thing the window
        // takes input for while hidden.
        Rectangle {
            id: edgeSensor
            width: 160
            height: 4
            color: "transparent"
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.hidden

            HoverHandler {
                id: edgeHover
                onHoveredChanged: {
                    if (edgeHover.hovered) {
                        root.edgeHideTimer.stop();
                        root.edgeRevealed = true;
                        root.rightClickHidden = false;
                    } else {
                        root.edgeHideTimer.restart();
                    }
                }
            }
        }
    }

    BarThemes {
        id: barThemes
    }
}
