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
import qs.modules.ii.dynamicIsland.dashboard
import qs.modules.ii.dynamicIsland.bubble
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
 * A single slot means everything the controller cannot place goes to overflow, which
 * waits its turn there. The island shows one activity at a time and arbitration alone
 * decides which: there is no manual way to page between them, by wheel or otherwise.
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
        // An auto-hiding island only appears because something happened, so while that
        // reveal lasts it shows the thing that happened - pressing play shows the track
        // even when arbitration would otherwise keep an agent in the centre. It keeps that
        // face while it retracts, so the content does not swap under a closing surface;
        // a later hover shows whatever arbitration puts in the centre.
        // Search is never replaced by an event arriving while the user types.
        // An event from a bubbled-out activity is shown by its bubble, not the island.
        // An event from a side widget is shown by the resting face it sits in.
        if (root.autoHide && root.eventId !== "" && root.bubbleBound.indexOf(root.eventId) === -1
                && root.sideBound.indexOf(root.eventId) === -1
                && controller.centerId !== "search"
                && controller.centerId !== "wallpaper"
                && controller.centerId !== "session"
                && (root.eventRevealed || !hoverIntent.hovered)
                && controller.activities.some(activity => activity.id === root.eventId))
            return root.eventId;
        return root.islandCenterId;
    }

    /** The centre, less whatever the bubbles have taken: the next in line, else the clock. */
    readonly property string islandCenterId: {
        const taken = id => root.bubbleBound.indexOf(id) !== -1 || root.sideBound.indexOf(id) !== -1;
        const center = controller.centerId;
        if (!taken(center))
            return center;
        const overflow = controller.overflowIds;
        for (let i = 0; i < overflow.length; i++) {
            if (!taken(overflow[i]))
                return overflow[i];
        }
        return "clock";
    }

    /**
     * Side widgets: activities that sit beside the clock inside the resting face
     * instead of taking the whole island - media and a recording on the left, an
     * agent and a timer on the right.
     *
     * Only without bubbles; with bubbles on, the same activities go out into them. A
     * side widget never takes the centre: something passing through (a notification,
     * a workspace change) still takes the whole island for its moment, and the resting
     * face with its side widgets comes back after. An agent asking for approval is not
     * a side glance and takes the island.
     */
    readonly property var sideActivities: ["media", "ai", "recording", "timer"]

    /** The resting face's height: what the clock face is sized to, never the live height. */
    readonly property real restingHeight: (root.pillShape && root.centerInBar)
        ? root.pillRestHeight
        : Math.max(IslandMotion.pillHeight, IslandPolicy.notchHeightFor("clock"))
    readonly property var sideBound: !root.bubbleEnabled
        ? controller.activities.filter(activity => root.sideActivities.indexOf(activity.id) !== -1
            && activity.tier !== "interrupt").map(activity => activity.id)
        : []

    /**
     * Everything the bubbles take, derived straight from the activities.
     *
     * Bubble activities go straight out, so this is simply every one that is present
     * and not asking for an answer. It is a binding on purpose: the slots are seated
     * by a handler that may run after the controller has already put a new arrival in
     * the centre, and the island reading the slots showed that arrival's face for a
     * moment before the bubble took it.
     */
    readonly property var bubbleBound: root.bubbleEnabled
        ? controller.activities.filter(activity => IslandPolicy.bubbleActivities.indexOf(activity.id) !== -1
            && activity.tier !== "interrupt").map(activity => activity.id)
        : []
    // ── Dashboard ────────────────────────────────────────────────────────────
    /**
     * The expanded face of an island at rest.
     *
     * The clock and the empty island have no expanded view of their own, so expanding
     * them opens the dashboard instead. Search always wins over it.
     */
    readonly property bool restingFace: root.pagedId === "" || root.pagedId === "clock"
    readonly property bool dashboardActive: !root.searchActive && !root.wallpaperActive && !root.sessionActive
        && (root.pagedId === "dashboard" || root.dashboardPinned || (root.expanded && !root.hasExpanded))

    /**
     * Editing the dashboard holds it open: the pointer leaving to reach the tray or a
     * resize handle must not collapse the island in the middle of an edit.
     */
    readonly property bool dashboardPinned: notchContent.dashboardEditing

    /** What the surface is drawing: the paged activity, or the dashboard in its place. */
    readonly property string faceId: root.dashboardActive ? "dashboard" : root.pagedId

    // Declared, like search: the dashboard computes its size from its grid (columns x
    // rows, plus the tray while editing) and the shape morphs to it. The first frame,
    // before the grid exists, uses a sensible default so the morph can start at once.
    /** Everything below the island's top, less a margin: the dashboard never leaves the screen. */
    readonly property real dashboardHeightCap: win.screen
        ? win.screen.height - root.surfaceTop - 2 * Appearance.sizes.hyprlandGapsOut
        : 800
    // Before the grid exists (the outgoing face is still fading) the size comes from
    // DashboardMetrics, which computes the same numbers from the layout - so the first
    // target is the final one and the morph never overshoots and corrects.
    readonly property real dashboardWidth: Math.min(root.widthCap,
        notchContent.dashboardTargetWidth > 0 ? notchContent.dashboardTargetWidth : DashboardMetrics.restWidth)
    readonly property real dashboardHeight: Math.min(root.dashboardHeightCap,
        notchContent.dashboardTargetHeight > 0 ? notchContent.dashboardTargetHeight : DashboardMetrics.restHeight)

    // ── Hover and expansion ──────────────────────────────────────────────────
    readonly property bool clickToExpand: Config.options.bar.floatingNotch.clickToExpand ?? false
    property bool clickedExpanded: false
    readonly property bool expanded: !root.expandSuppressed
        && (root.clickToExpand ? root.clickedExpanded : hoverIntent.engaged)
        // One thing expands at a time: never alongside an open bubble.
        && root.expandedBubbleId === ""

    // ── Search takes over an expanded island ────────────────────────────────
    /**
     * Opening search ends whatever was expanded, at once.
     *
     * An expanded activity is pinned to the centre so it is not swapped out from under
     * the pointer, and that pin also held search back: the expanded widget stayed until
     * its own timer ran out and only then did the island shrink and show search. Search
     * is an explicit request, so it wins immediately - a transient on screen is
     * dismissed (its timer ends now), the hover expansion is dropped, and the expansion
     * stays off until the pointer leaves, so closing search does not bring the expanded
     * widget back.
     */
    property bool expandSuppressed: false

    function yieldToSearch() {
        const shown = root.pagedId;
        if (root.expanded && shown !== "" && shown !== "search" && shown !== "wallpaper"
                && shown !== "session" && shown !== "clock") {
            const source = controller.sources.sourceFor(shown);
            if (source && typeof source.dismiss === "function")
                source.dismiss();
        }
        root.expandSuppressed = true;
        hoverIntent.disengage();
        root.clickedExpanded = false;
        root.eventRevealed = false;
        root.eventId = "";
    }

    Connections {
        target: controller.sources.search
        function onActiveChanged() {
            if (controller.sources.search.active)
                root.yieldToSearch();
            else if (!hoverIntent.hovered)
                root.expandSuppressed = false;
        }
    }

    // The wallpaper browser is the same kind of request: the user asked for it by name,
    // so it takes the surface from whatever was expanded rather than queueing behind it.
    Connections {
        target: controller.sources.wallpaper
        function onActiveChanged() {
            if (controller.sources.wallpaper.active)
                root.yieldToSearch();
            else if (!hoverIntent.hovered)
                root.expandSuppressed = false;
        }
    }

    Connections {
        target: controller.sources.session
        function onActiveChanged() {
            if (controller.sources.session.active)
                root.yieldToSearch();
            else if (!hoverIntent.hovered)
                root.expandSuppressed = false;
        }
    }
    /**
     * Whether the island has an expanded face of its own for what it shows.
     *
     * Expanding the island opens the dashboard, whatever is on it: the per-widget
     * expanded faces are gone, and the few worth keeping live in the bubbles' cards.
     * LocalSend is the exception because its "expanded" face is not a hover view but
     * the drop-to-send flow (the files and the device picker), with nowhere else to go.
     */
    readonly property bool hasExpanded: root.pagedId === "localSend"

    // ── LocalSend ────────────────────────────────────────────────────────────
    readonly property bool kdeDropReady: IslandPolicy.kdeConnectColumnEnabled
        && typeof KdeConnectService !== "undefined"
        && KdeConnectService.available
        && KdeConnectService.activeReachable
        && !!KdeConnectService.activeDevice

    /** A file drag is over the island: it grows into the two-column drop target. */
    readonly property bool localSendDragging: root.pagedId === "localSend"
        && controller.sources.localSend.dragHovering

    /**
     * LocalSend opens by itself when there is something to do: files were just dropped
     * (the device picker, or KDE Connect's send button), a transfer is coming in (accept
     * or decline), or one is being sent. It does not wait for a hover - a hover opens
     * the dashboard now - and a fresh drop stays open for a few seconds, or for as long
     * as the pointer rests on it.
     */
    property bool localSendHold: false
    readonly property bool localSendOpen: root.pagedId === "localSend" && !root.localSendDragging
        && (root.localSendHold || LocalSend.currentTransfer !== null || LocalSend.sending
            || (root.expanded && root.hasExpanded))
    Connections {
        target: controller.sources.localSend
        function onServiceChoiceChanged() {
            root.localSendHold = controller.sources.localSend.serviceChoice !== 0;
            if (root.localSendHold)
                localSendHoldTimer.restart();
        }
    }
    property Timer localSendHoldTimer: Timer {
        id: localSendHoldTimer
        interval: 3000
        onTriggered: {
            if (hoverIntent.hovered)
                localSendHoldTimer.restart();
            else
                root.localSendHold = false;
        }
    }

    IslandHoverIntent {
        id: hoverIntent
        // The island's own pointer only: a bubble expands itself, never the island.
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
     * The wallpaper picker, drawn as one of the island's faces.
     *
     * Like search it takes the whole surface and sizes it, and like search it is only
     * ever the centre - a picker being browsed does not belong in a bubble hanging off
     * the side. See IslandPolicy.ownsWallpaper for who draws it.
     */
    readonly property bool wallpaperActive: root.pagedId === "wallpaper"

    /** The session menu, drawn as one of the island's faces; see IslandSessionMenu. */
    readonly property bool sessionActive: root.pagedId === "session"

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
    /**
     * The island lays the overview out itself: a small fixed grid, opening and closing
     * with the island rather than playing the desktop overview's own entrance.
     *
     * Two rows of three at a pinned scale. The scale is small on purpose - the overview
     * hangs under the island and the window has to contain it, so a grid sized for the
     * desktop pushed the bar's own widgets far out of the way to make room.
     */
    readonly property bool integratedOverview: IslandPolicy.ownsOverview
    readonly property int overviewRows: 2
    readonly property int overviewColumns: 3
    /** Relative to the screen, like Config.options.overview.scale. */
    readonly property real overviewScale: 0.15

    /**
     * How the overview arrives. Integrated, it is a plain fade on the island's own
     * timing, exactly as the search face arrives - no bounce, no zoom, no travel, and
     * nothing that answers to the desktop overview's animation setting.
     */
    readonly property string overviewAnimStyle: root.integratedOverview
        ? "island" : (Config.options.overview.animationStyle ?? "bounce")
    readonly property bool overviewPlainFade: root.overviewAnimStyle === "island"
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
                : root.overviewPlainFade ? Appearance.animation.elementMoveFast.duration
                : Math.round((root.overviewVisible ? 420 : 260) * Appearance.animMultiplier)
            easing.type: root.overviewPlainFade ? Appearance.animation.elementMoveFast.type : Easing.BezierSpline
            easing.bezierCurve: root.overviewPlainFade ? Appearance.animation.elementMoveFast.bezierCurve
                : (root.overviewVisible ? Appearance.animationCurves.expressiveFastSpatial
                    : Appearance.animationCurves.emphasizedAccel)
        }
    }

    Behavior on overviewFade {
        NumberAnimation {
            duration: root.overviewAnimStyle === "none" ? 0
                : root.overviewPlainFade ? Appearance.animation.elementMoveFast.duration
                : Math.round((root.overviewVisible ? 420 : 260) * Appearance.animMultiplier)
            easing.type: root.overviewPlainFade ? Appearance.animation.elementMoveFast.type
                : (root.overviewVisible ? Easing.OutCubic : Easing.InCubic)
            // Only read when the type is a BezierSpline, which is the plain-fade case.
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // ── Geometry ─────────────────────────────────────────────────────────────
    readonly property string presentation: root.localSendOpen ? "expanded" : "compact"

    /** Room the surface may never exceed, so a wide result row cannot push it off screen. */
    readonly property real widthCap: win.screen ? win.screen.width - 2 * Appearance.sizes.hyprlandGapsOut : 1600
    readonly property real heightCap: win.screen ? win.screen.height * 0.7 : 600

    readonly property real targetWidth: {
        if (root.dashboardActive)
            return root.dashboardWidth;
        if (root.searchActive) {
            const wanted = notchContent.searchTargetWidth;
            const search = wanted > 0 ? wanted : (Config.options.search.baseWidth ?? 440);
            // The grid sits inside the body, so the island is as wide as the wider of
            // the two rather than letting the grid hang over its edges.
            const overview = (root.integratedOverview && root.overviewVisible)
                ? notchContent.overviewTargetWidth : 0;
            return Math.min(root.widthCap, Math.max(search, overview));
        }
        if (root.wallpaperActive) {
            const wanted = notchContent.wallpaperTargetWidth;
            return Math.min(root.widthCap, wanted > 0 ? wanted : 848);
        }
        if (root.sessionActive) {
            const wanted = notchContent.sessionTargetWidth;
            return Math.min(root.widthCap, wanted > 0 ? wanted : 394);
        }
        // The indicator declares its own size; see NotchContent.osdTargetWidth.
        if (root.pagedId === "osd" && notchContent.osdTargetWidth > 0)
            return Math.min(root.widthCap, notchContent.osdTargetWidth);
        // The drop target is two columns wide enough to aim at.
        if (root.localSendDragging)
            return 360;
        // The resting face measures itself: the clock, and the side widgets beside it.
        if (root.restingFace && notchContent.restingWidth > 0)
            return notchContent.restingWidth;
        if (root.pagedId === "")
            return 180;
        // The workspaces strip is as wide as the workspaces the user actually has, so it
        // measures itself rather than taking a number from the registry.
        if (root.pagedId === "workspaces" && root.presentation === "compact"
                && notchContent.workspaceWidgetRef)
            // As much air at the sides as above and below: the strip's own width plus
            // the vertical gap the resting height leaves around it, on each side.
            return Math.max(60, notchContent.workspaceWidgetRef.contentWidth
                + Math.max(8, root.restingHeight - notchContent.workspaceWidgetRef.contentHeight));
        return IslandRegistry.widthFor(root.pagedId, root.presentation);
    }

    readonly property real targetHeight: {
        if (root.dashboardActive)
            return root.dashboardHeight;
        if (root.searchActive) {
            const wanted = notchContent.searchTargetHeight;
            const search = wanted > 0 ? wanted : 54;
            return Math.min(root.heightCap, search + notchContent.overviewArea);
        }
        if (root.wallpaperActive) {
            const wanted = notchContent.wallpaperTargetHeight;
            return wanted > 0 ? Math.min(root.heightCap, wanted) : 300;
        }
        if (root.sessionActive) {
            const wanted = notchContent.sessionTargetHeight;
            return wanted > 0 ? Math.min(root.heightCap, wanted) : 236;
        }
        if (root.pagedId === "")
            return Config.options.bar.floatingNotch.heightHome ?? 36;
        if (root.pagedId === "osd" && notchContent.osdTargetHeight > 0)
            return Math.min(root.heightCap, notchContent.osdTargetHeight);
        if (root.localSendDragging)
            return 140;
        let registered = IslandRegistry.heightFor(root.pagedId, root.presentation);
        // A pill in the bar centre rests inside the bar rather than below it.
        if (root.pillShape && root.centerInBar && registered === IslandMotion.pillHeight)
            registered = root.pillRestHeight;
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
    readonly property bool attachedToEdge: !root.pillShape && (root.centerInBar || !root.hasTopBar)

    // ── Shell ────────────────────────────────────────────────────────────────
    /**
     * The "island" shell: a pill that floats free of every edge, iOS style.
     *
     * Same faces, same sizes and the same morph as the notch; what differs is the
     * outside. Every corner is round, there are no shoulders, and hiding is a vertical
     * slide out of view instead of a retract into the edge - the pill keeps its shape
     * the whole way.
     */
    readonly property bool pillShape: IslandPolicy.shape === "island"

    /**
     * Where the top edge of the shown surface sits. Independent of the surface's size,
     * so anything sized from it (the dashboard's height cap) cannot loop back into it.
     */
    readonly property real surfaceTop: {
        let top = 0;
        if (root.hasTopBar && !root.centerInBar)
            top = Appearance.sizes.barHeight;
        else if (root.usingWrappedFrame)
            top = Config.options.appearance.wrappedFrameThickness;
        return root.pillShape ? top + root.pillInset : top;
    }
    /** Gap between a pill and whatever it floats under (the screen edge or the bar). */
    readonly property real pillInset: root.centerInBar ? 2 : Appearance.sizes.hyprlandGapsOut
    /** A resting pill in the bar centre fits inside the bar, like the bar's own pills. */
    readonly property real pillRestHeight: Math.max(24, Appearance.sizes.barHeight - 2 * root.pillInset)

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
    property bool edgeRevealed: false

    /**
     * Slid out of view.
     *
     * In bar-centre mode the notch never slides: it grows and shrinks in place, because
     * anything that leaves the bar's centre empty for a frame shows a hole in the bar.
     */
    readonly property bool hidden: {
        if (root.searchActive || root.wallpaperActive || root.sessionActive || root.dashboardPinned)
            return false;
        // A drop target has to be visible to be a target, and no hover signal arrives
        // during a drag to reveal it.
        if (controller.sources.localSend.dragHovering)
            return false;
        if (root.fullscreenHere)
            return true;
        if (root.autoHide)
            return !root.edgeRevealed && !hoverIntent.hovered && !root.hoverLinger
                && !root.eventRevealed && !root.hasUrgentActivity
                // Bubbles hang from the island: it stays while one is being read.
                && !root.anyBubbleHovered && root.expandedBubbleId === "";
        if (root.centerInBar)
            return false;
        // Without auto-hide only the resting face hides, so the island is not a
        // permanent bar the user never asked for.
        // Nor while the bubbles hold something: the island is what they hang from.
        return (root.pagedId === "" || root.pagedId === "clock") && root.bubbleHeld.length === 0
            && root.sideBound.length === 0
            ? !root.edgeRevealed && !hoverIntent.hovered : false;
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
    readonly property int eventRevealMs: 4000
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
            root.updateBubbles();
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

    /**
     * A short linger after the pointer leaves. Hiding the instant it left made the
     * island vanish under a pointer that had only drifted off its edge.
     */
    property bool hoverLinger: false
    Connections {
        target: hoverIntent
        function onHoveredChanged() {
            // The suppression from a search takeover ends once the pointer leaves.
            if (!hoverIntent.hovered && !controller.sources.search.active)
                root.expandSuppressed = false;
            if (hoverIntent.hovered) {
                hoverLingerTimer.stop();
                root.hoverLinger = true;
            } else {
                hoverLingerTimer.restart();
            }
        }
    }
    property Timer hoverLingerTimer: Timer {
        id: hoverLingerTimer
        interval: 1500
        repeat: false
        onTriggered: root.hoverLinger = false
    }

    property Timer edgeHideTimer: Timer {
        interval: 700
        repeat: false
        onTriggered: root.edgeRevealed = false
    }

    // ── Auxiliary bubbles ────────────────────────────────────────────────────
    /**
     * Round surfaces beside the island that activities move out into.
     *
     * Media or a workspace change arrives, takes the island for its settle window (the
     * registry's `settleMs`), and then - since the island already had something to show,
     * even if only the clock - moves out into a bubble and leaves the island to it. A
     * bubble is a glance, not a second island: hovering it opens its activity in the
     * island, and the island expanding calls the bubbles back in. That keeps one place
     * where things expand, and none of the side-slot arbitration the cluster style
     * needs.
     *
     * There is one slot per activity the bubble may take, so media and the workspace
     * change can sit out at once: the first to settle takes the island's right, the
     * second its left. If the eligible list ever grows past the two sides, the next
     * arrival chains out of the first bubble, and so on, alternating sides. Slots stick:
     * an activity keeps its slot and its side for as long as it is present, and a freed
     * slot is simply the first hole the next arrival fills - so a bubble never trades
     * sides under the user's pointer, and a workspace change while a track sits to the
     * right takes the left rather than trading places.
     */
    readonly property bool bubbleEnabled: IslandPolicy.auxiliaryBubble
    /** One entry per slot, "" for a hole. The index fixes the side and the chain. */
    readonly property int bubbleSlotCount: IslandPolicy.bubbleActivities.length
    property var bubbleSlots: []
    readonly property var bubbleHeld: root.bubbleSlots.filter(id => id !== "")

    function updateBubbles() {
        if (!root.bubbleEnabled) {
            root.bubbleSlots = [];
            return;
        }
        const list = controller.activities;
        const now = Date.now();
        // The table always carries every slot, so a delegate never reads past its end.
        // A held activity keeps its slot while it is present; a slot whose chain parent
        // has been freed gives its activity back, and the pass below may seat it again
        // closer in.
        const slots = [];
        // Something demanding an answer (an agent asking for approval) is never a
        // glance: it comes back to the island for as long as it asks.
        const seatable = id => list.some(activity => activity.id === id && activity.tier !== "interrupt");
        for (let i = 0; i < root.bubbleSlotCount; i++) {
            const held = root.bubbleSlots[i] ?? "";
            const alive = held !== "" && seatable(held);
            const anchored = i < 2 || slots[i - 2] !== "";
            slots.push(alive && anchored ? held : "");
        }
        const eligible = IslandPolicy.bubbleActivities;
        let wait = -1;
        for (let e = 0; e < eligible.length; e++) {
            const id = eligible[e];
            if (slots.some(held => held === id))
                continue;
            const activity = list.find(entry => entry.id === id);
            if (!activity || !seatable(id))
                continue;
            // Never pulled out from under the pointer while it is open in the island.
            if (root.expanded && root.pagedId === id)
                continue;
            // A direct activity leaves the moment it arrives: its bubble is the whole
            // announcement, so it never holds the centre for the settle window.
            const settle = IslandPolicy.bubbleDirectActivities.indexOf(id) === -1
                ? (activity.settleMs || 0) : 0;
            const left = settle - (now - (activity.arrivedAt || 0));
            if (left > 0) {
                wait = wait < 0 ? left : Math.min(wait, left);
                continue;
            }
            const slot = root.freeBubbleSlot(slots);
            if (slot < 0)
                continue;
            slots[slot] = id;
        }
        root.bubbleSlots = slots;
        if (wait > 0) {
            bubbleSettleTimer.interval = Math.ceil(wait) + 20;
            bubbleSettleTimer.restart();
        }
    }

    /**
     * The first slot an arrival may take: the leftmost hole whose chain parent is
     * seated. A chained bubble with no parent would hang from nothing.
     */
    function freeBubbleSlot(slots) {
        for (let i = 0; i < slots.length; i++) {
            if (slots[i] !== "")
                continue;
            if (i >= 2 && slots[i - 2] === "")
                continue;
            return i;
        }
        return -1;
    }

    onBubbleEnabledChanged: root.updateBubbles()
    // A reload starts with the activities already present, which is no change at all.
    Component.onCompleted: Qt.callLater(root.updateBubbles)
    // An activity skipped because it was open gets its turn once the island closes.
    onExpandedChanged: if (!root.expanded) Qt.callLater(root.updateBubbles)

    property Timer bubbleSettleTimer: Timer {
        id: bubbleSettleTimer
        repeat: false
        onTriggered: root.updateBubbles()
    }

    // ── Expanded bubbles ─────────────────────────────────────────────────────
    /**
     * The activity whose bubble is open into a card of its own, or "".
     *
     * Only one thing is ever expanded - one bubble, or the island - so two surfaces
     * never grow into each other: a bubble may open only while the island is compact
     * and on its resting business (no search, no dashboard) and no other bubble is
     * open, and the island will not expand while a bubble is (see `expanded`).
     */
    property string expandedBubbleId: ""
    readonly property bool bubbleMayExpand: root.expandedBubbleId === "" && !root.expanded
        && !root.searchActive && !root.wallpaperActive && !root.sessionActive && !root.dashboardActive && !root.hidden

    function requestBubbleExpand(activityId) {
        if (root.bubbleMayExpand && root.bubbleHeld.indexOf(activityId) !== -1)
            root.expandedBubbleId = activityId;
    }

    function requestBubbleCollapse(activityId) {
        if (root.expandedBubbleId === activityId)
            root.expandedBubbleId = "";
    }

    // An open bubble folds when its activity leaves it, and when anything bigger
    // takes over (search, the dashboard being pinned, the island hiding).
    onBubbleHeldChanged: {
        if (root.expandedBubbleId !== "" && root.bubbleHeld.indexOf(root.expandedBubbleId) === -1)
            root.expandedBubbleId = "";
    }
    onSearchActiveChanged: if (root.searchActive) root.expandedBubbleId = ""
    onWallpaperActiveChanged: if (root.wallpaperActive) root.expandedBubbleId = ""
    onSessionActiveChanged: if (root.sessionActive) root.expandedBubbleId = ""
    onDashboardActiveChanged: if (root.dashboardActive) root.expandedBubbleId = ""

    // ── What the bubbles report back ─────────────────────────────────────────
    // Each slot answers through a signal and the island keeps the aggregate: one
    // pointer count, one reach per side, one mask list. No pollers.

    property var bubblePointers: []
    function noteBubblePointer(index, over) {
        if ((root.bubblePointers[index] === true) === over)
            return;
        const list = root.bubblePointers.slice();
        list[index] = over;
        root.bubblePointers = list;
    }
    readonly property bool anyBubbleHovered: root.bubblePointers.some(over => over === true)

    property var bubbleReaches: []
    function noteBubbleReach(index, right, left) {
        const current = root.bubbleReaches[index];
        if (current && current[0] === right && current[1] === left)
            return;
        const list = root.bubbleReaches.slice();
        list[index] = [right, left];
        root.bubbleReaches = list;
    }
    function widestBubbleReach(edge) {
        let widest = 0;
        const list = root.bubbleReaches;
        for (let i = 0; i < list.length; i++) {
            const reach = list[i];
            if (reach && reach[edge] > widest)
                widest = reach[edge];
        }
        return widest;
    }
    readonly property real bubbleRightExtra: root.widestBubbleReach(0)
    readonly property real bubbleLeftExtra: root.widestBubbleReach(1)

    /** The mask entries of every bubble's hit target, whatever its side. */
    readonly property var bubbleMaskRegions: {
        const regions = [];
        for (let i = 0; i < bubbleRepeater.count; i++) {
            const slot = bubbleRepeater.itemAt(i);
            if (slot)
                regions.push(slot.maskRegion);
        }
        return regions;
    }

    /** A bar widget's size: the resting pill's height, in the bar or floating. */
    readonly property real bubbleDiameter: root.centerInBar ? root.pillRestHeight : IslandMotion.pillHeight - 6
    // Clear air between the two, even with tight window gaps.
    readonly property real bubbleGap: Math.max(8, Appearance.sizes.hyprlandGapsOut)
    /** The height the bubble lines up with: the island's resting face, not whatever it grew to. */
    readonly property real bubbleRestHeight: (root.centerInBar && root.pillShape) ? root.pillRestHeight : IslandMotion.pillHeight

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
        // Search and the wallpaper browser are the states that type, so they are the
        // ones that take the keyboard - a notch that holds focus while merely showing a
        // track would swallow every shortcut in the session.
        WlrLayershell.keyboardFocus: (root.searchActive || root.wallpaperActive || root.sessionActive || notchContent.dashboardWantsKeyboard)
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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
                // A grid that hangs outside the body needs the whole surface to accept
                // input; the integrated one is inside the island's own shape, which
                // maskTarget already covers.
                const outsideGrid = root.overviewVisible
                    && (root.scrollingLayout || !root.integratedOverview);
                return outsideGrid ? fullWindow : maskTarget;
            }
            // The bubbles take the pointer too, so hovering one can open the island.
            regions: root.bubbleMaskRegions
        }

        Item {
            id: fullWindow
            anchors.fill: parent
        }

        HyprlandFocusGrab {
            windows: [win]
            active: root.searchActive || root.sessionActive
        }

        Item {
            id: maskTarget
            anchors.horizontalCenter: container.horizontalCenter
            anchors.top: container.top
            width: container.width
            height: container.height
        }

        // ── Auxiliary bubbles: the shapes, beneath the body ──────────────────
        // The fields draw only the necks and the bubbles; the body drawn over them
        // is the island's own, so the surfaces read as one body pulling apart.
        Repeater {
            id: bubbleRepeater
            model: root.bubbleSlotCount
            AuxiliaryBubble {
                side: index % 2 === 0 ? "right" : "left"
                // Index 2 and beyond chain out of the bubble two places back.
                parentBubble: index < 2 ? null : bubbleRepeater.itemAt(index - 2)
                activityId: root.bubbleSlots[index] ?? ""
                enabledState: root.bubbleEnabled
                islandHidden: root.hidden
                expanded: root.expanded
                searchActive: root.searchActive
                dashboardActive: root.dashboardActive
                pagedId: root.pagedId
                expandedBubbleId: root.expandedBubbleId
                mayExpand: root.bubbleMayExpand
                diameter: root.bubbleDiameter
                gap: root.bubbleGap
                centerY: container.y + Math.min(container.height, root.bubbleRestHeight) / 2
                bodyCenterX: container.x + container.width / 2
                bodyTop: container.y
                bodyWidth: notchBody.width
                bodyHeight: notchBody.height
                bodyRadius: notchBody.bodyRadius
                reservedRight: container.x + container.width / 2 + IslandGeometry.centerWidth / 2
                reservedLeft: container.x + container.width / 2 - IslandGeometry.centerWidth / 2
                surfaceColor: notchBody.color
                shadowEnabled: notchBody.layer.enabled
                onExpandRequested: activityId => root.requestBubbleExpand(activityId)
                onCollapseRequested: activityId => root.requestBubbleCollapse(activityId)
                onPointerChanged: over => root.noteBubblePointer(index, over)
                onReachChanged: (right, left) => root.noteBubbleReach(index, right, left)
            }
        }

        Item {
            id: container

            anchors.horizontalCenter: parent.horizontalCenter
            /**
             * In the bar centre the island retracts into its own centre as it hides, and
             * the bar closes the gap it leaves (the published width follows this). As
             * with the height, the size animates once and the reveal scales the result.
             */
            property real animatedWidth: root.targetWidth + 2 * root.filletSize
            // The pill keeps its size and slides instead (see `y`).
            width: (root.centerInBar && !root.pillShape) ? root.centerBarProgress * container.animatedWidth : container.animatedWidth
            /**
             * The size animates once, and the bar-centre reveal scales that result.
             *
             * The reveal used to multiply the *target* height and the height Behavior
             * then animated the product - a second animation chasing a value the reveal
             * was already moving every frame, so hiding lagged and settled late.
             */
            property real animatedHeight: root.targetHeight
            height: (root.centerInBar && !root.pillShape) ? root.centerBarProgress * container.animatedHeight : container.animatedHeight

            y: {
                if (root.pillShape) {
                    let shown = root.pillInset;
                    if (!root.centerInBar && root.hasTopBar)
                        shown += Appearance.sizes.barHeight;
                    else if (root.usingWrappedFrame)
                        shown += Config.options.appearance.wrappedFrameThickness;
                    const away = -container.height - 10;
                    // In the bar centre the slide rides the reveal clock the bar already
                    // follows; floating, the y Behavior below animates it.
                    if (root.centerInBar)
                        return away + (shown - away) * root.centerBarProgress;
                    return root.hidden ? away : shown;
                }
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
            readonly property bool largeFace: root.searchActive || root.wallpaperActive || root.sessionActive || root.dashboardActive


            readonly property int morphMs: Math.round((container.largeFace ? 420 : 500) * Appearance.animMultiplier)

            Behavior on animatedWidth {
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
                // A sliding pill keeps its width, so the gap it leaves closes with the
                // reveal instead of with the width.
                value: root.centerInBar
                    ? 2 * Math.round((root.pillShape
                        // No shoulders on a pill: only the body takes room in the bar.
                        ? (container.width - 2 * root.filletSize) * root.centerBarProgress
                        : container.width) / 2)
                    : 0
                restoreMode: Binding.RestoreBindingOrValue
            }
            // How far past the island each side's bubbles reach, so the bar keeps clear.
            Binding {
                target: IslandGeometry
                property: "rightExtra"
                value: root.centerInBar ? root.bubbleRightExtra : 0
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: IslandGeometry
                property: "leftExtra"
                value: root.centerInBar ? root.bubbleLeftExtra : 0
                restoreMode: Binding.RestoreBindingOrValue
            }
            // What is out in bubbles, so the bar does not show it a second time. Only
            // while the island is on screen: a hidden island leaves the bar to show it.
            Binding {
                target: IslandGeometry
                property: "bubbledIds"
                value: root.bubbleEnabled && !root.hidden ? root.bubbleHeld : []
                restoreMode: Binding.RestoreBindingOrValue
            }
            Binding {
                target: IslandGeometry
                property: "reveal"
                value: root.centerInBar ? root.centerBarProgress : 1
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
                // Never deeper than the body: at a fixed size they stayed out as two
                // spikes while an auto-hiding island retracted into the edge.
                width: Math.min(root.filletSize, container.height)
                height: width
                visible: root.attachedToEdge && container.height > 0
                mirrored: true
                color: notchBody.color
            }

            NotchFillet {
                anchors.left: notchBody.right
                anchors.top: parent.top
                width: Math.min(root.filletSize, container.height)
                height: width
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
                // Which half the drag is over, so the widget can light that column.
                onPositionChanged: drag => {
                    controller.sources.localSend.dragOnRight = root.kdeDropReady && drag.x >= fileDrop.width / 2;
                }

                onDropped: drop => {
                    if (!drop.hasUrls)
                        return;
                    // Which half of the island the files landed on picks the service.
                    const useKde = root.kdeDropReady && drop.x >= fileDrop.width / 2;
                    const source = controller.sources.localSend;
                    source.queueFiles = drop.urls.map(url => url.toString().replace(/^file:\/\//, ""));
                    source.dragOnRight = false;
                    source.serviceChoice = useKde ? 2 : 1;
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
                    activityId: root.faceId
                    expanded: root.localSendOpen
                    sideIds: root.sideBound
                    restingHeight: root.restingHeight
                    dashboardAvailableWidth: root.widthCap
                    dashboardAvailableHeight: root.dashboardHeightCap
                    // The surface the faces are drawn on: a face that fades its own
                    // edges has to fade into the island's colour, which follows the
                    // expressive bar theme when one is on.
                    surfaceColor: notchBody.color
                    // The workspace overview, drawn inside the body under the search
                    // field; see NotchContent.overviewVisible.
                    overviewVisible: root.integratedOverview && root.overviewVisible
                    overviewBuilt: root.overviewBuilt && !root.scrollingLayout
                    overviewFade: root.overviewFade
                    overviewRows: root.overviewRows
                    overviewColumns: root.overviewColumns
                    overviewScale: root.overviewScale
                    overviewPanelWindow: win
                    overviewMonitorIndex: Quickshell.screens.indexOf(win.screen)
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
            // Integrated, the grid is drawn inside the body by NotchContent; this
            // panel is what the overview looks like when the island does not hold it.
            active: root.overviewBuilt && !root.scrollingLayout && !root.integratedOverview
            visible: opacity > 0.01
            opacity: root.overviewFade

            // Integrated, the fade above is the whole animation - the same arrival the
            // search face has. The desktop overview's travel and zoom stay for when the
            // island does not own it.
            transform: [
                Translate {
                    y: (root.overviewAnimStyle === "none" || root.overviewPlainFade) ? 0
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
                gridRows: root.integratedOverview ? root.overviewRows : Config.options.overview.rows
                gridColumns: root.integratedOverview ? root.overviewColumns : Config.options.overview.columns
                fixedScale: root.integratedOverview ? root.overviewScale : 0
                suppressEntrance: root.integratedOverview
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
                    y: (root.overviewAnimStyle === "none" || root.overviewPlainFade) ? 0
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
            // A sliver along the top edge. In the bar centre the gap closes while the
            // island is hidden, so anything taller would sit over the bar's own widgets.
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
