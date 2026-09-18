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
        // An auto-hiding island only appears because something happened, so while that
        // reveal lasts it shows the thing that happened - pressing play shows the track
        // even when arbitration would otherwise keep an agent in the centre. It keeps that
        // face while it retracts, so the content does not swap under a closing surface;
        // a later hover shows whatever arbitration puts in the centre.
        // Search is never replaced by an event arriving while the user types.
        if (root.autoHide && root.eventId !== "" && controller.centerId !== "search"
                && (root.eventRevealed || !hoverIntent.hovered)
                && controller.activities.some(activity => activity.id === root.eventId))
            return root.eventId;
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
        // Hovering an auto-hiding island shows its contracted face immediately (see
        // `hidden`); the expanded face waits until the pointer has rested this long.
        dwellMs: root.autoHide ? IslandPolicy.hoverExpandDelayMs : 0
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
     * Search takes the whole surface.
     *
     * The old panel kept a strip of still-running activities along the bottom while
     * searching, which stacked a second panel under the search field and made the island
     * look like two surfaces glued together. Search is one of the island's faces, not a
     * layer over it: while it is on, it is the only thing there.
     */

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

    /**
     * The workspace grid is built once and then kept.
     *
     * Building it is the most expensive thing search does - a tile and a screen copy per
     * window - and doing that on every open dropped up to a hundred milliseconds of
     * frames right in the middle of the island's morph. The tiles already stop capturing
     * while hidden and refresh their frozen frame when shown again, so a kept grid costs
     * memory, not work. It is also warmed once the session is quiet, so even the first
     * open does not pay for it.
     */
    property bool overviewBuilt: false
    onOverviewAnimatingChanged: {
        if (root.overviewAnimating)
            root.overviewBuilt = true;
    }
    property Timer overviewWarmTimer: Timer {
        interval: 4000
        running: !root.overviewBuilt && !IslandPolicy.quietWindowActive && !GlobalStates.screenLocked
        onTriggered: root.overviewBuilt = true
    }

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

    /** Room the surface may never exceed, so a wide result row cannot push it off screen. */
    readonly property real widthCap: win.screen ? win.screen.width - 2 * Appearance.sizes.hyprlandGapsOut : 1600
    readonly property real heightCap: win.screen ? win.screen.height * 0.7 : 600

    readonly property real targetWidth: {
        if (root.searchActive) {
            const wanted = notchContent.searchTargetWidth;
            return Math.min(root.widthCap, wanted > 0 ? wanted : (Config.options.search.baseWidth ?? 440));
        }
        if (root.pagedId === "")
            return 180;
        // The workspaces strip is as wide as the workspaces the user actually has, so it
        // measures itself rather than taking a number from the registry.
        if (root.pagedId === "workspaces" && root.presentation === "compact"
                && notchContent.workspaceWidgetRef)
            return Math.max(100, notchContent.workspaceWidgetRef.implicitWidth);
        return IslandRegistry.widthFor(root.pagedId, root.presentation);
    }

    readonly property real targetHeight: {
        if (root.searchActive) {
            const wanted = notchContent.searchTargetHeight;
            return wanted > 0 ? Math.min(root.heightCap, wanted) : 54;
        }
        if (root.pagedId === "")
            return Config.options.bar.floatingNotch.heightHome ?? 36;
        const registered = IslandRegistry.heightFor(root.pagedId, root.presentation);
        // A contracted face that needs more than a pill (a Bluetooth connection, a
        // notification) grows the island for as long as it is on screen, instead of
        // being clipped to the resting height.
        if (root.presentation === "compact")
            return Math.max(registered, IslandPolicy.notchHeightFor(root.pagedId));
        return registered;
    }

    // ── Shape ────────────────────────────────────────────────────────────────
    /**
     * How far the concave corner reaches out from the body.
     *
     * Deliberately small: it is a transition into the bezel, not a feature of its own.
     * The old shape derived this from the corner radius, which made every rounding
     * change also change the island's width.
     */
    readonly property real filletSize: Appearance.rounding.verysmall

    /** Whether the notch meets the screen edge, which is what the fillets are for. */
    /**
     * Whether the notch meets the screen edge - a matter of where it sits, not of
     * whether it is showing. It used to follow `!hidden`, so the moment an auto-hiding
     * island began to collapse its top corners rounded and the fillets vanished, and it
     * shrank away as a detached pill instead of retracting into the edge. Only a notch
     * floating below a top bar is detached.
     */
    readonly property bool attachedToEdge: root.centerInBar || !root.hasTopBar

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
            return !root.edgeRevealed && !hoverIntent.hovered && !root.eventRevealed && !root.hasUrgentActivity;
        if (root.centerInBar)
            return false;
        // Without auto-hide only the resting face hides, so the island is not a
        // permanent bar the user never asked for.
        return root.pagedId === "" || root.pagedId === "clock" ? !root.edgeRevealed && !hoverIntent.hovered : false;
    }

    /** Something is genuinely happening, as opposed to the clock being on screen. */
    readonly property bool hasLiveActivity: controller.activities.some(activity => activity.id !== "clock")

    // ── Event-driven reveal (auto-hide) ──────────────────────────────────────
    /**
     * An auto-hiding island shows *events*, not state.
     *
     * It used to stay out while any activity was present, so a paused track or an idle
     * agent kept it on screen indefinitely. Now it appears when something happens - an
     * activity arriving, a transient firing again, playback starting, a new track - for
     * `eventRevealMs`, and then retracts. Interrupts (a notification, the volume OSD)
     * hold it for as long as they last; they are short-lived by definition.
     */
    readonly property int eventRevealMs: 2600
    readonly property bool hasUrgentActivity: controller.activities.some(activity => activity.tier === "interrupt")
    property bool eventRevealed: false
    property string eventId: ""
    property var _seenRevisions: ({})

    function wantsReveal(activityId) {
        // Media is present while paused; only playing media is worth showing.
        if (activityId === "media")
            return MprisController.activePlayer ? MprisController.activePlayer.isPlaying : false;
        return true;
    }

    function noteActivityEvents() {
        const seen = {};
        let latest = "";
        let latestAt = -1;
        const list = controller.activities;
        for (let i = 0; i < list.length; i++) {
            const activity = list[i];
            if (activity.id === "clock")
                continue;
            seen[activity.id] = activity.revision;
            const previous = root._seenRevisions[activity.id];
            if (previous !== undefined && previous === activity.revision)
                continue;
            if (!root.wantsReveal(activity.id))
                continue;
            if (activity.arrivedAt >= latestAt) {
                latestAt = activity.arrivedAt;
                latest = activity.id;
            }
        }
        root._seenRevisions = seen;
        // Bulk restores after a boot, a reload or an unlock are not events.
        if (latest === "" || IslandPolicy.quietWindowActive)
            return;
        root.eventId = latest;
        root.eventRevealed = true;
        eventRevealTimer.restart();
    }

    Connections {
        target: controller
        function onActivitiesChanged() {
            root.noteActivityEvents();
        }
    }

    property Timer eventRevealTimer: Timer {
        id: eventRevealTimer
        interval: root.eventRevealMs
        repeat: false
        onTriggered: {
            // Reading it keeps it: the reveal ends when the pointer leaves, not under it.
            if (hoverIntent.hovered) {
                eventRevealTimer.restart();
                return;
            }
            root.eventRevealed = false;
        }
    }

    property Timer edgeHideTimer: Timer {
        interval: 700
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
        /**
         * Always the screen's height; the mask keeps everything but the shape
         * click-through.
         *
         * It used to be 240px and grew to full height only while search was open. A
         * layer surface that changes size commits a new buffer, and the compositor
         * showed the island at its old place in the old buffer for one frame while the
         * new one was configured - the one-frame vertical hop at the start of every
         * search open. A constant size has nothing to reconfigure.
         */
        implicitHeight: win.screen ? win.screen.height : 1080

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
            width: root.targetWidth + 2 * root.filletSize
            /**
             * The size animates once, and the bar-centre reveal scales that result.
             *
             * The reveal used to multiply the *target* height and the height Behavior
             * then animated the product - a second animation chasing a value the reveal
             * was already moving every frame, so hiding lagged and settled late.
             */
            property real animatedHeight: root.targetHeight
            height: root.centerInBar ? root.centerBarProgress * container.animatedHeight : container.animatedHeight

            y: {
                if (root.hidden && !root.centerInBar)
                    return -root.targetHeight - 10;
                if (root.hasTopBar && !root.centerInBar)
                    return Appearance.sizes.barHeight;
                if (root.usingWrappedFrame)
                    return Config.options.appearance.wrappedFrameThickness;
                return 0;
            }

            /**
             * The island's size settles with a small bounce.
             *
             * One interceptor per property: `centerInBar` and the reveal pick their
             * timing *inside* each behaviour rather than adding a second one, because
             * two Behaviours on the same property log "Attempting to set another
             * interceptor" and the second is silently ignored.
             *
             * The overshoot is softer than the old island's (0.9/0.5), which read as a
             * wobble, but a plain decel curve made the island feel mechanical - the
             * bounce is what makes a surface that changes size look like an object
             * rather than a resizing rectangle. Closing is the exception: it keeps a
             * decel curve, since an overshoot on the way out would briefly expose a gap
             * where the island sits inside the bar.
             */
            readonly property bool closing: root.hidden

            /**
             * Large faces settle, small ones bounce.
             *
             * A pill showing a track name is a small object and reads as one when it
             * overshoots slightly. Search is a panel most of the screen tall: the same
             * overshoot on it is a wobble the eye follows all the way down, and it
             * arrives *after* the content has been laid out, so the rows visibly slide
             * past their final place. Big surfaces get tight damping instead.
             *
             * There is exactly one animator per axis, always this one. The search widget
             * no longer eases its own size while the island is its host, so nothing here
             * is chasing a target that is itself in motion.
             */
            readonly property bool largeFace: root.searchActive


            readonly property int morphMs: Math.round((container.largeFace ? 420 : 500) * Appearance.animMultiplier)

            Behavior on width {
                NumberAnimation {
                    duration: container.morphMs
                    easing.type: (container.closing || container.largeFace) ? Easing.BezierSpline : Easing.OutBack
                    easing.bezierCurve: container.largeFace && !container.closing
                        ? Appearance.animationCurves.standard
                        : Appearance.animationCurves.emphasizedDecel
                    easing.overshoot: 0.6
                }
            }

            Behavior on animatedHeight {
                NumberAnimation {
                    duration: container.closing ? root.centerBarCloseMs : container.morphMs
                    easing.type: (container.closing || container.largeFace) ? Easing.BezierSpline : Easing.OutBack
                    easing.bezierCurve: container.largeFace && !container.closing
                        ? Appearance.animationCurves.standard
                        : Appearance.animationCurves.emphasizedDecel
                    easing.overshoot: 0.35
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
                /**
                 * Whole, even pixels.
                 *
                 * The bar lays its groups out with a RowLayout, and layouts snap sizes
                 * to integers while positions stay fractional. Fed this width raw, the
                 * pill's width moved in rounded 2px steps while its centring offset
                 * moved continuously, so the right-hand group wobbled a pixel back and
                 * forth every few frames and slid left at the very end of each morph.
                 * Even means each half-gap is also whole, so every quantity the bar
                 * derives from this is an integer and moves monotonically with it.
                 */
                value: root.centerInBar ? 2 * Math.round(container.width / 2) : 0
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: IslandGeometry
                property: "centerHeight"
                value: root.centerInBar ? container.height : 0
                restoreMode: Binding.RestoreBindingOrValue
            }

            /**
             * The body.
             *
             * Square where it meets the screen edge and rounded below, with the concave
             * transition drawn *outside* it by the two fillets. The previous silhouette
             * carved the shoulders out of the shape itself and tied their width to the
             * corner radius, so a rounder island was also a visibly wider one and the
             * curve ate into the content.
             */
            Rectangle {
                id: notchBody
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                // Derived from the *animated* container, never from the target. Bound to
                // the target it snapped to its final width while the clip box animated
                // around it, so during every resize the content was visible outside the
                // shape - and the overshoot made it worse. One animated size, everything
                // else measured from it.
                width: Math.max(0, parent.width - 2 * root.filletSize)
                height: parent.height
                antialiasing: true

                color: Config.options.bar.expressiveColors
                    ? barThemes.getTheme(Config.options.bar.expressiveColorTheme).barBackground
                    : Appearance.colors.colLayer0

                /**
                 * A capsule while short, a card once tall - one continuous function of
                 * the *animated* height, with one cap for every face.
                 *
                 * It used to switch between two formulas (and a cap 4px larger for
                 * compact faces, which is why search looked rounder than media) behind
                 * its own Behavior. That Behavior restarted on every frame of the height
                 * morph, since the radius is derived from the height, so the bottom
                 * corners only caught up after the surface had stopped growing. Derived
                 * directly, they are always right for the size on screen.
                 */
                readonly property real bodyRadius: Math.min(height / 2, Appearance.rounding.large)

                // Attached to the edge, so the top corners go square and the fillets
                // take over from there.
                topLeftRadius: root.attachedToEdge ? 0 : notchBody.bodyRadius
                topRightRadius: root.attachedToEdge ? 0 : notchBody.bodyRadius
                bottomLeftRadius: notchBody.bodyRadius
                bottomRightRadius: notchBody.bodyRadius

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

            // The fillets flare from the body's top edge out to the bezel.
            NotchFillet {
                anchors.right: notchBody.left
                anchors.top: parent.top
                width: root.filletSize
                height: root.filletSize
                visible: root.attachedToEdge && container.height > 0
                mirrored: true
                color: notchBody.color
            }

            NotchFillet {
                anchors.left: notchBody.right
                anchors.top: parent.top
                width: root.filletSize
                height: root.filletSize
                visible: root.attachedToEdge && container.height > 0
                color: notchBody.color
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

            // The body's silhouette, rendered only as the content's mask.
            Item {
                id: contentShape
                anchors.fill: contentClip
                visible: false
                layer.enabled: true

                Rectangle {
                    anchors.fill: parent
                    antialiasing: true
                    color: "black"
                    topLeftRadius: notchBody.topLeftRadius
                    topRightRadius: notchBody.topRightRadius
                    bottomLeftRadius: notchBody.bottomLeftRadius
                    bottomRightRadius: notchBody.bottomRightRadius
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
                width: Math.max(0, parent.width - 2 * root.filletSize)
                clip: true

                /**
                 * Clipped to the body's *shape*, not its bounding box.
                 *
                 * `clip` is rectangular, so anything a face drew near its bottom edge
                 * - a background, a row, a fading icon - showed in the triangles
                 * outside the rounded corners, most visibly while the surface was
                 * resizing and the content had not settled into it yet.
                 */
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: contentShape
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                NotchContent {
                    id: notchContent
                    anchors.fill: parent
                    activityId: root.pagedId
                    expanded: root.expanded && root.hasExpanded
                    controller: controller
                }
            }
        }

        Loader { // Classic overview
            id: overviewLoader
            // Built off the UI thread: the workspace grid (previews of every window) is the
            // heaviest thing search opens, and building it synchronously stalled the
            // island's morph for its first frames. It fades in after the surface anyway.
            asynchronous: true
            anchors.top: container.bottom
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            active: root.overviewBuilt && !root.scrollingLayout
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
            // Built off the UI thread: the workspace grid (previews of every window) is the
            // heaviest thing search opens, and building it synchronously stalled the
            // island's morph for its first frames. It fades in after the surface anyway.
            asynchronous: true
            anchors.top: container.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            active: root.overviewBuilt && root.scrollingLayout
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
            // In the bar centre the island leaves its gap in the bar while hidden, so that
            // whole gap is the target; floating, a sliver along the top edge.
            width: root.centerInBar ? Math.max(160, container.width) : 160
            height: root.centerInBar ? Appearance.sizes.barHeight : 4
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
