pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
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
        if ((root.autoHide || root.oledSaverHere) && root.eventId !== "" && root.bubbleBound.indexOf(root.eventId) === -1
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
     * agent and a timer on the right, the earbuds and weather glances at either end.
     *
     * A side widget never takes the centre: something passing through (a
     * notification, a workspace change) still takes the whole island for its
     * moment, and the resting face with its side widgets comes back after. An
     * agent asking for approval is not a side glance and takes the island.
     */
    readonly property var sideActivities: ["media", "ai", "recording", "timer", "mode", "update", "earbuds", "weather", "batteryGlance",
        "privacy", "discordVoice", "phoneLink", "phoneMirror", "phoneCall", "sports"]

    /** The resting face's height: what the clock face is sized to, never the live height. */
    readonly property real restingHeight: (root.pillShape && root.centerInBar)
        ? root.pillRestHeight : IslandMotion.pillHeight

    // Side-only glances (earbuds, weather, battery) stay beside the clock whatever the bubble
    // setting: no bubble ever takes them, so with bubbles on they would otherwise
    // fall through and claim the centre. The bubble-eligible ones trade the resting
    // face for a bubble when bubbles are on, exactly as before.
    readonly property var sideBound: controller.activities.filter(activity =>
        root.sideActivities.indexOf(activity.id) !== -1 && !controller.holdsCenter(activity)
        && (!root.bubbleEnabled || IslandPolicy.bubbleActivities.indexOf(activity.id) === -1)
    ).map(activity => activity.id)

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
            && !controller.holdsCenter(activity)).map(activity => activity.id)
        : []
    // ── Dashboard ────────────────────────────────────────────────────────────
    /**
     * The expanded face of an island at rest.
     *
     * The clock and the empty island have no expanded view of their own, so expanding
     * them opens the dashboard instead. Search always wins over it.
     */
    readonly property bool restingFace: root.pagedId === "" || root.pagedId === "clock"
    /**
     * The dashboard, asked for from outside the island - `qs ipc call dynamicIsland
     * openDashboard`, or anything else that wants it on screen with no pointer on it.
     *
     * A hover exists only while a pointer is there, and the hover engine owns `engaged`:
     * a request that set it would be undone the moment the pointer moved. So the request
     * is its own hold, and it ends where a hovered dashboard ends - a click away, or an
     * explicit surface (search, the session menu) taking the island.
     */
    property bool dashboardRequested: false
    readonly property bool dashboardActive: !root.searchActive && !root.wallpaperActive && !root.sessionActive
        && (root.dashboardRequested || root.pagedId === "dashboard" || root.dashboardPinned || (root.expanded && !root.hasExpanded))

    /**
     * Editing the dashboard holds it open: the pointer leaving to reach the tray or a
     * resize handle must not collapse the island in the middle of an edit.
     */
    readonly property bool dashboardPinned: notchContent.dashboardEditing

    /**
     * A page asked for from elsewhere in the shell - the media card's audio output
     * pill, say. Opening the page pins the dashboard, which brings the island out with
     * it; only the island on the focused monitor answers, so a second screen does not
     * open the same page behind the user's back.
     */
    function consumeDashboardPage() {
        const pageId = GlobalStates.islandDashboardPage;
        if (pageId === "" || !IslandPolicy.enabled)
            return;
        if (Hyprland.focusedMonitor && root.hyprMonitor && Hyprland.focusedMonitor !== root.hyprMonitor)
            return;
        GlobalStates.islandDashboardPage = "";
        notchContent.showDashboardPage(pageId);
    }

    Connections {
        target: GlobalStates
        function onIslandDashboardPageChanged() {
            root.consumeDashboardPage();
        }
    }

    /**
     * Bring the dashboard out without a pointer on the island; see `dashboardRequested`.
     *
     * What it does is what the hold-to-reveal gesture would have done: the island takes
     * the dashboard's size and shows the grid. `closeDashboard` is the other half, and
     * is the same move a click away makes.
     */
    function openDashboard() {
        root.dashboardRequested = true;
    }

    IpcHandler {
        target: "dynamicIsland"

        function openDashboard(): void {
            root.openDashboard();
        }
        function closeDashboard(): void {
            root.dismissDashboard();
        }
        function toggleDashboard(): void {
            if (root.dashboardActive)
                root.dismissDashboard();
            else
                root.openDashboard();
        }
    }

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
    readonly property bool clickToExpand: IslandPolicy.clickToExpand

    /**
     * Hold to reveal: the dashboard only opens once the pointer has rested this long,
     * and the island swells for as long as it waits.
     *
     * The wait alone would be a dead pause - the pointer sits on a surface that does
     * nothing until it suddenly becomes a dashboard. The swell answers the pointer at
     * once, with the island's own bounce, and holds that size until the dashboard opens
     * or the pointer leaves; it costs nothing but a scale (the geometry, the mask and
     * the morph are untouched). It is a hover affordance, so click-to-expand switches
     * it off.
     */
    readonly property bool holdToReveal: IslandPolicy.holdToReveal && !root.clickToExpand
    readonly property int holdRevealMs: IslandPolicy.holdToRevealMs
    /** How much bigger the island gets by the end of the hold. */
    readonly property real holdRevealScale: 1.2
    /**
     * The hold is running: the pointer is on the island and the dashboard is not open yet.
     *
     * `!dashboardActive` is the guard against swelling an island that is already open:
     * a quick-toggle page (Wi-Fi, Bluetooth) holds the dashboard through `holdOpen`,
     * and the pointer leaving to reach the tray and coming back re-arms `arriving`
     * with `expanded` false - the hold would then swell a dashboard that is already
     * up, which reads as the island shrinking and bouncing on its own face.
     */
    readonly property bool holdRevealing: root.holdToReveal && hoverIntent.arriving
        && !root.expanded && !root.hidden && !root.dashboardActive
    property bool clickedExpanded: false
    readonly property bool expanded: !root.expandSuppressed
        && (root.clickToExpand ? root.clickedExpanded : hoverIntent.engaged)
        // One thing expands at a time: never alongside an open bubble.
        && root.expandedBubbleId === ""
        // Nor over a face made of buttons, whichever way expanding is asked for.
        && !IslandRegistry.isInteractive(root.pagedId)

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

    /**
     * The surfaces a hover must never take over: the ones the user is typing into or
     * navigating with - search, the wallpaper browser, the session menu - and the
     * full-screen states that own the display.
     */
    readonly property bool explicitSurfaceActive: (controller.sources.search && controller.sources.search.active)
        || root.searchActive
        || (controller.sources.wallpaper && controller.sources.wallpaper.active)
        || root.wallpaperActive
        || (controller.sources.session && controller.sources.session.active)
        || root.sessionActive
        || GlobalStates.overviewOpen
        || GlobalStates.appDrawerOpen
        || GlobalStates.screenLocked
    /**
     * An interrupt is on screen: an explicit surface, or an activity that demands an
     * answer (a notification, the OSD). It collapses an expanded face when it lands,
     * but it does not veto the hover - every widget face the island shows opens the
     * dashboard on the pointer resting on it, the notification face included.
     */
    readonly property bool interruptsActive: root.explicitSurfaceActive || root.hasUrgentActivity

    function forceCollapse() {
        const shown = root.pagedId;
        if (root.expanded && shown !== "" && shown !== "search" && shown !== "wallpaper"
                && shown !== "session" && shown !== "clock") {
            const source = controller.sources.sourceFor(shown);
            if (source && typeof source.dismiss === "function")
                source.dismiss();
        }
        root.expandSuppressed = root.explicitSurfaceActive;
        hoverIntent.disengage();
        root.clickedExpanded = false;
        root.eventRevealed = false;
        root.eventId = "";
        // An explicit surface or an interrupt that collapses the island also ends a
        // dashboard that was asked for from outside; see `dashboardRequested`.
        root.dashboardRequested = false;
    }

    function yieldToSearch() {
        root.forceCollapse();
    }

    /**
     * A click landed outside an open dashboard, so it closes.
     *
     * Deliberately not `forceCollapse`: that also suppresses the next expand until the
     * pointer has entered and left again, and here the pointer is already elsewhere -
     * the suppression would have nothing to clear it and the island would stop opening.
     */
    function dismissDashboard() {
        hoverIntent.disengage();
        root.clickedExpanded = false;
        // A dashboard that was asked for from outside has no hover to drop, so the
        // request is the thing to end; see `dashboardRequested`.
        root.dashboardRequested = false;
    }

    onInterruptsActiveChanged: {
        if (!root.dashboardActive) {
            root.forceCollapse();
            if (!root.explicitSurfaceActive)
                root.expandSuppressed = false;
        }
        if (!root.explicitSurfaceActive && !hoverIntent.hovered)
            root.expandSuppressed = false;
    }

    Connections {
        target: controller.sources.search
        function onActiveChanged() {
            root.forceCollapse();
            if (!controller.sources.search.active && !root.explicitSurfaceActive && !hoverIntent.hovered)
                root.expandSuppressed = false;
        }
    }

    // The wallpaper browser is the same kind of request: the user asked for it by name,
    // so it takes the surface from whatever was expanded rather than queueing behind it.
    Connections {
        target: controller.sources.wallpaper
        function onActiveChanged() {
            root.forceCollapse();
            if (!controller.sources.wallpaper.active && !root.explicitSurfaceActive && !hoverIntent.hovered)
                root.expandSuppressed = false;
        }
    }

    Connections {
        target: controller.sources.session
        function onActiveChanged() {
            root.forceCollapse();
            if (!controller.sources.session.active && !root.explicitSurfaceActive && !hoverIntent.hovered)
                root.expandSuppressed = false;
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            root.forceCollapse();
            if (!GlobalStates.overviewOpen && !root.explicitSurfaceActive && !hoverIntent.hovered)
                root.expandSuppressed = false;
        }
        function onAppDrawerOpenChanged() {
            root.forceCollapse();
            if (!GlobalStates.appDrawerOpen && !root.explicitSurfaceActive && !hoverIntent.hovered)
                root.expandSuppressed = false;
        }
        function onScreenLockedChanged() {
            root.forceCollapse();
            if (!GlobalStates.screenLocked && !root.explicitSurfaceActive && !hoverIntent.hovered)
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
        blocked: root.explicitSurfaceActive || root.expandSuppressed
            // A face made of buttons: the pointer is there to press one.
            || IslandRegistry.isInteractive(root.pagedId)
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
        // Hold to reveal replaces that wait with its own, whatever auto-hide is doing.
        dwellMs: root.holdToReveal ? root.holdRevealMs
            : (root.autoHide ? IslandPolicy.hoverExpandDelayMs : 0)
        // ...and keeps the same short grace the bubbles do, so reaching inside is safe
        // without the island hanging around after the pointer has gone.
        graceMs: IslandPolicy.collapseGraceMs
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

    /** The picked-colour card and an incoming transfer, both the popups' own layouts. */
    readonly property bool colorPickerActive: root.pagedId === "colorPicker"
    readonly property bool bluetoothCardActive: root.pagedId === "bluetooth"
        && notchContent.bluetoothCardTargetHeight > 0
    readonly property bool localSendRequestActive: root.pagedId === "localSend"
        && !root.localSendDragging
        && notchContent.localSendRequestTargetHeight > 0

    /**
     * Search takes the whole surface.
     *
     * The old panel kept a strip of still-running activities along the bottom while
     * searching, which stacked a second panel under the search field and made the island
     * look like two surfaces glued together. Search is one of the island's faces, not a
     * layer over it: while it is on, it is the only thing there.
     */

    /**
     * Whether a panel (AI or hosted) owns the search surface.
     */
    readonly property bool searchPanelOwned: GlobalStates.searchPanelActive
        || GlobalStates.searchPendingPanel !== ""
        || GlobalStates.panelOpenedDirectly
        || (notchContent.searchItem ? (notchContent.searchItem.isAnySpecialMode || notchContent.searchItem.isAiMode) : false)

    /**
     * The overview sits below the notch while search is open, and its entry/exit is
     * animated, so the window has to stay tall enough to contain it for the whole
     * transition - not only while search is technically active.
     */
    readonly property bool overviewVisible: root.searchActive
        && LauncherSearch.query === ""
        && !root.searchPanelOwned
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
            return Math.min(root.widthCap, wanted > 0 ? wanted : 1156);
        }
        if (root.sessionActive) {
            const wanted = notchContent.sessionTargetWidth;
            return Math.min(root.widthCap, wanted > 0 ? wanted : 394);
        }
        if (root.colorPickerActive && notchContent.colorPickerTargetWidth > 0)
            return Math.min(root.widthCap, notchContent.colorPickerTargetWidth);
        if (root.bluetoothCardActive)
            return Math.min(root.widthCap, notchContent.bluetoothCardTargetWidth);
        if (root.localSendRequestActive)
            return Math.min(root.widthCap, notchContent.localSendRequestTargetWidth);
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
        const override = root.pagedSizeOverride;
        if (override && override.width > 0)
            return Math.min(root.widthCap, override.width);
        return IslandRegistry.widthFor(root.pagedId, root.presentation);
    }

    /**
     * A source may ask for a different box than its descriptor for one of its phases:
     * a missed call is one line, where the ringing card it shares an id with is two
     * rows and three buttons. `{ width, height }`, `-1` for the island's own metric.
     */
    readonly property var pagedSizeOverride: {
        const source = controller.sources.sourceFor(root.pagedId);
        return (source && source.sizeOverride) ? source.sizeOverride : null;
    }

    readonly property real targetHeight: {
        if (root.dashboardActive)
            return root.dashboardHeight;
        if (root.searchActive) {
            const ovHeight = (notchContent.overviewTargetHeight > 0
                ? notchContent.overviewTargetHeight + notchContent.overviewGap
                : 0) + 54;
            // When query is empty and no panel is active, we are in (or returning to) overview: target is immediately the overview height.
            // Only while the overview is actually shown: with it disabled the loader still reports a
            // height, and the island opened as a tall empty box.
            if (LauncherSearch.query === "" && !root.searchPanelOwned && root.overviewVisible)
                return Math.min(root.heightCap, ovHeight);

            const wanted = notchContent.searchTargetHeight;
            const search = wanted > 0 ? wanted : 54;
            // While searching, hold at least ovHeight while overview is fading out so it doesn't dip
            const holdingOverview = root.overviewVisible || root.overviewFade > 0.001;
            return Math.min(root.heightCap, holdingOverview ? Math.max(search, ovHeight) : search);
        }
        if (root.wallpaperActive) {
            const wanted = notchContent.wallpaperTargetHeight;
            return wanted > 0 ? Math.min(root.heightCap, wanted) : 300;
        }
        if (root.sessionActive) {
            const wanted = notchContent.sessionTargetHeight;
            return wanted > 0 ? Math.min(root.heightCap, wanted) : 236;
        }
        if (root.colorPickerActive && notchContent.colorPickerTargetHeight > 0)
            return Math.min(root.heightCap, notchContent.colorPickerTargetHeight);
        if (root.bluetoothCardActive)
            return Math.min(root.heightCap, notchContent.bluetoothCardTargetHeight);
        if (root.localSendRequestActive)
            return Math.min(root.heightCap, notchContent.localSendRequestTargetHeight);
        if (root.pagedId === "")
            return 36;   // the retracted sliver, below the resting pill
        if (root.pagedId === "osd" && notchContent.osdTargetHeight > 0)
            return Math.min(root.heightCap, notchContent.osdTargetHeight);
        if (root.localSendDragging)
            return 140;
        let registered = IslandRegistry.heightFor(root.pagedId, root.presentation);
        const override = root.pagedSizeOverride;
        if (override && override.height !== undefined)
            registered = override.height > 0 ? override.height : IslandMotion.pillHeight;
        // A pill in the bar centre rests inside the bar rather than below it.
        if (root.pillShape && root.centerInBar && registered === IslandMotion.pillHeight)
            registered = root.pillRestHeight;
        // A contracted face that needs more than a pill (a Bluetooth connection, a
        // notification) declares that height in its registry descriptor, so the
        // island grows for as long as it is on screen instead of clipping it.
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
        else if (root.centerInBar)
            top = root.barBodyInset;
        else if (root.usingWrappedFrame)
            top = Config.options.appearance.wrappedFrameThickness;
        return root.pillShape ? top + root.pillInset : top;
    }

    /**
     * The visible bar's box, which is not the bar window's.
     *
     * Float holds the bar a gap away from all four screen edges and
     * `Appearance.sizes.barHeight` counts those two vertical gaps, so a pill placed and
     * sized from the window alone sat a gap too high and stood a gap too tall for the
     * body it was meant to rest in. Every other style welds the bar to the edge, where
     * the two boxes are the same and these fall back to what they always were.
     */
    readonly property real barBodyInset: (root.centerInBar && !BarPlacement.vertical
        && BarInteraction.cornerStyle === 1) ? Appearance.sizes.hyprlandGapsOut : 0
    readonly property real barBodyHeight: Appearance.sizes.barHeight - 2 * root.barBodyInset

    /** Gap between a pill and whatever it floats under (the screen edge or the bar). */
    readonly property real pillInset: root.centerInBar ? 2 : Appearance.sizes.hyprlandGapsOut
    /** A resting pill in the bar centre fits inside the bar, like the bar's own pills. */
    readonly property real pillRestHeight: Math.max(24, root.barBodyHeight - 2 * root.pillInset)

    // ── Placement ────────────────────────────────────────────────────────────
    readonly property bool centerInBar: IslandPolicy.centerInBar
    readonly property bool hasBarHere: GlobalStates.isScreenAllowedForBar(win.screen)
    readonly property bool hasTopBar: GlobalStates.barOpen && !BarPlacement.vertical && !BarPlacement.bottom && root.hasBarHere
    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3
        && (!Config.options.bar.onlyShowOnSingleMonitor || root.hasBarHere)

    readonly property bool fullscreenHere: {
        if (!win.screen)
            return false;
        // The same check the bar and the screen corners use, for the same reasons:
        // it counts a fullscreen window on the special workspace - a scratchpad
        // pulled over the monitor - and it reads the client list rather than a
        // workspace's own toplevels, which the compactor's renumbering leaves
        // stale. The old local scan of `Hyprland.workspaces` saw neither, so a
        // fullscreen video in the scratchpad left the island sitting on top of it.
        return HyprlandData.monitorHasFullscreenWindow(win.screen.name);
    }

    readonly property bool autoHide: Config.options.bar.floatingNotch.autoHide ?? false

    // ── OLED saver ───────────────────────────────────────────────────────────
    /**
     * Over the OLED saver the island stays where it is and keeps its input region, but
     * fades to nothing while nothing is happening: a resting face on a black screen is
     * a static image, which is what burns in. It does not slide - hiding would move the
     * hover target away. Hover, a bubble, an event or an interrupt fades it back.
     */
    readonly property bool oledSaverHere: !!win.screen
        && (GlobalStates.oledSaverMonitors ?? []).includes(win.screen.name)
    readonly property bool oledResting: root.oledSaverHere
        && !hoverIntent.hovered && !root.hoverLinger
        && !root.anyBubbleHovered && root.expandedBubbleId === ""
        && !root.eventRevealed && !root.hasUrgentActivity
        && !root.expanded && !root.dashboardActive && !root.explicitSurfaceActive
        && !controller.sources.localSend.dragHovering
    property real oledFade: root.oledResting ? 0 : 1
    Behavior on oledFade {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
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
            // The suppression from an interrupt or search takeover ends once the pointer
            // leaves; only the explicit surfaces keep it past that, so a notification or
            // an OSD still on screen does not silence the island's own hover.
            if (!hoverIntent.hovered && !root.explicitSurfaceActive)
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
        interval: IslandPolicy.collapseGraceMs
        repeat: false
        onTriggered: root.hoverLinger = false
    }

    property Timer edgeHideTimer: Timer {
        interval: IslandPolicy.collapseGraceMs
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
        const seatable = id => list.some(activity => activity.id === id && !controller.holdsCenter(activity));
        const eligible = IslandPolicy.bubbleActivities;
        for (let i = 0; i < root.bubbleSlotCount; i++) {
            const held = root.bubbleSlots[i] ?? "";
            // A held activity keeps its slot while it is present *and* still eligible:
            // turning an activity's bubble off in Settings must call its bubble home,
            // not wait for the activity to end on its own.
            const alive = held !== "" && eligible.indexOf(held) !== -1 && seatable(held);
            const anchored = i < 2 || slots[i - 2] !== "";
            slots.push(alive && anchored ? held : "");
        }
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
    // Turning an activity's bubble off (Settings) re-seats the table at once, so the
    // bubble that just lost its eligibility is called home without waiting for the
    // next activity change.
    Connections {
        target: IslandPolicy
        function onBubbleActivitiesChanged() {
            root.updateBubbles();
        }
    }

    // A reload starts with the activities already present, which is no change at all.
    Component.onCompleted: {
        Qt.callLater(root.updateBubbles);
        GlobalStates.islandWindow = win;
    }
    Component.onDestruction: {
        if (GlobalStates.islandWindow === win)
            GlobalStates.islandWindow = null;
    }
    // An activity skipped because it was open gets its turn once the island closes.
    onExpandedChanged: if (!root.expanded) Qt.callLater(root.updateBubbles)

    property Timer bubbleSettleTimer: Timer {
        id: bubbleSettleTimer
        repeat: false
        onTriggered: root.updateBubbles()
    }

    /**
     * How far the island has grown over its bubbles, 0 to 1.
     *
     * The island opening - expanded, search, the dashboard - calls the bubbles in, and
     * closing lets them out again. Either way they move on this and not on a clock of
     * their own: it is read off the body's *animated* size, so the bubbles and the body
     * are one movement by construction - whatever the island is growing into, at any
     * animation speed, with whatever curve the size animation picked, stalls included.
     *
     * A clock running beside the size animation was the first attempt. It shared the
     * duration and the curve on paper, but the two pick their curve from state that
     * flips on the same turn, and they did not always pick the same one: closing the
     * dashboard the bubbles were fully out with the body a fifth of the way from home.
     * It stays as the fallback for an island that opens without changing size, where
     * there is nothing to read.
     */
    readonly property bool swallowing: root.expanded || root.largePageActive || root.dashboardActive
    /** A page the island grows into as far as the launcher does: the bubbles go in for all of them. */
    readonly property bool largePageActive: root.searchActive || root.wallpaperActive || root.sessionActive
    property real swallowClock: root.swallowing ? 1 : 0
    Behavior on swallowClock {
        NumberAnimation {
            duration: container.morphMs
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }
    /**
     * The width is what is read: the bubbles sit on the body's sides, and it is that
     * edge they are seen against. The height stands in when the width is not changing.
     */
    property real swallowFromWidth: 0
    property real swallowFromHeight: 0
    onSwallowingChanged: {
        root.swallowFromWidth = container.animatedWidth;
        root.swallowFromHeight = container.animatedHeight;
    }
    /** How far `now` is from `from` to `to`, or -1 when that is not this movement. */
    function swallowedAlong(from, now, to) {
        const span = to - from;
        // Opening grows and closing shrinks; anything else is not the bubbles' business.
        if (root.swallowing ? span < 8 : span > -8)
            return -1;
        const done = Math.max(0, Math.min(1, (now - from) / span));
        return done > 0.995 ? 1 : done;
    }
    readonly property real swallow: {
        let done = root.swallowedAlong(root.swallowFromWidth, container.animatedWidth,
            root.targetWidth + 2 * root.filletSize);
        if (done < 0)
            done = root.swallowedAlong(root.swallowFromHeight, container.animatedHeight, root.targetHeight);
        if (done < 0)
            return root.swallowClock;
        return root.swallowing ? done : 1 - done;
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
    // The comment above always promised this one and the handler never existed: the
    // bubble's own fold path cannot serve it, because an open card collapsing when
    // the island hides runs through `shown`, which the hidden island has already
    // taken away. Without this, `expandedBubbleId` outlives the card it belongs to
    // and vetoes every later retraction (`hidden` demands it be "").
    onHiddenChanged: if (root.hidden) root.expandedBubbleId = ""

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
        //
        // OnDemand for all of them, never Exclusive. Exclusive was tried for the
        // wallpaper face to force the grant when the surface already had OnDemand for
        // another face, and it fights the focus grab below: asking for it moves the
        // keyboard off the grabbed window, the grab reports that as the pointer leaving,
        // and `onCleared` closed the picker in the same frame it opened - the picker
        // never appeared at all. Every face that types asks OnDemand instead, and a
        // change of face is the change Hyprland grants on.
        WlrLayershell.keyboardFocus: (root.wallpaperActive || root.searchActive || root.sessionActive || notchContent.dashboardWantsKeyboard)
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

            // With a grid hanging outside the body the whole window takes input, so a
            // click beside the launcher lands here instead of clearing the grab below.
            // Anything over the island or the grid is theirs and never reaches this.
            MouseArea {
                anchors.fill: parent
                enabled: root.searchActive
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: mouse => {
                    const inside = mouse.x >= container.x && mouse.x <= container.x + container.width
                        && mouse.y >= container.y && mouse.y <= container.y + container.height;
                    if (inside) {
                        mouse.accepted = false;
                        return;
                    }
                    GlobalStates.closeOverview();
                }
            }
        }

        HyprlandFocusGrab {
            windows: [win]
            // The dashboard joins the two that already grabbed: it is as much an open
            // surface as they are, and having the session menu inside it close on a
            // click away while the dashboard holding it would not was the tell.
            // Editing the grid is left out on purpose - a grab there would eat every
            // click outside without anything to close. An open detail page is not
            // editing: it pins the island against the pointer leaving, not against a click.
            // The wallpaper browser needs it too: the surface is only OnDemand, so
            // without the grab it had no keyboard until it was clicked.
            active: root.searchActive || root.sessionActive || root.wallpaperActive
                || (root.dashboardActive && !notchContent.dashboardGridEditing)
            // A menu is a question put to the pointer, so clicking away is an answer -
            // and so is clicking away from the launcher, as it is everywhere else the
            // launcher is drawn.
            onCleared: {
                if (root.sessionActive)
                    GlobalStates.sessionOpen = false;
                if (root.searchActive)
                    GlobalStates.closeOverview();
                if (root.wallpaperActive)
                    GlobalStates.wallpaperSelectorOpen = false;
                if (root.dashboardActive && !notchContent.dashboardGridEditing) {
                    // The page pins the dashboard; drop it first or the dismiss is ignored.
                    notchContent.closeDashboardPage();
                    root.dismissDashboard();
                }
            }
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
                // Faded, not hidden: a bubble keeps its place and its hover.
                opacity: root.oledFade
                // Index 2 and beyond chain out of the bubble two places back.
                parentBubble: index < 2 ? null : bubbleRepeater.itemAt(index - 2)
                activityId: root.bubbleSlots[index] ?? ""
                enabledState: root.bubbleEnabled
                islandHidden: root.hidden
                expanded: root.expanded
                searchActive: root.largePageActive
                dashboardActive: root.dashboardActive
                swallow: root.swallow
                pagedId: root.pagedId
                expandedBubbleId: root.expandedBubbleId
                mayExpand: root.bubbleMayExpand
                diameter: root.bubbleDiameter
                gap: root.bubbleGap
                // Measured on the island as it is *drawn*, swell included: the hold
                // grows the body with a scale, and a bubble reading the unscaled
                // numbers would sit inside it. Everything below is an offset from the
                // container's top centre, which is the transform's origin, so the
                // swell multiplies it exactly as it does the body.
                //
                // In the bar centre the body collapses *in place* as the island hides
                // (the reveal shrinks it to nothing in less time than a bubble takes
                // to come home), so the anchor line would settle on the edge itself
                // and a bubble still travelling would end as a half-visible circle
                // stuck at the top. Riding the reveal clock off past the edge makes
                // the recall complete out of sight; floating and pill shapes need no
                // offset because their containers already slide above the edge.
                centerY: container.y + container.scale * Math.min(container.height, root.bubbleRestHeight) / 2
                    - (root.centerInBar ? (1 - root.centerBarProgress) * root.bubbleDiameter : 0)
                bodyCenterX: container.x + container.width / 2
                bodyTop: container.y
                bodyWidth: notchBody.width * container.scale
                bodyHeight: notchBody.height * container.scale
                bodyRadius: notchBody.bodyRadius * container.scale
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
            // Opacity keeps input, so the faded island still answers hover.
            opacity: root.oledFade

            /**
             * The swell, as a transform rather than geometry. The bubbles and the bar
             * are handed the scaled numbers below, so they move aside for it exactly
             * as they do for an activity arriving; the window's *input mask*
             * (`maskTarget`) deliberately stays on the unscaled size, so growing can
             * never move the hover region out from under the pointer holding it and
             * set the island flickering between the two sizes.
             *
             * Driven by these two animations and never by a Behavior on `scale`: when
             * the hold *completes* there must be no way back at all - the dashboard's
             * morph has to begin on an island at its normal size, so its opening is
             * exactly the animation it has always been.
             */
            transformOrigin: Item.Top

            NumberAnimation {
                id: holdSwell
                target: container
                property: "scale"
                to: root.holdRevealScale
                // The shell's fast preset with a bounce on top: 200 ms, the same
                // length as every other quick reaction here, so the pointer is
                // answered at once. The body's own morph (420-500 ms) is the wrong
                // clock for this - it is the length of a surface changing shape, and
                // at that length a 20 % scale reads as the island creeping. It is not
                // a countdown either: the hold is the dwell timer, not this.
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.OutBack
                easing.overshoot: 0.3
            }

            NumberAnimation {
                id: holdSwellBack
                target: container
                property: "scale"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }

            Connections {
                target: root
                function onHoldRevealingChanged() {
                    holdSwell.stop();
                    holdSwellBack.stop();
                    if (root.holdRevealing) {
                        holdSwell.start();
                        return;
                    }
                    // The hold finished: hand the dashboard an island at its own size
                    // this frame. Only an abandoned hold eases back.
                    if (root.expanded || container.scale === 1) {
                        container.scale = 1;
                        return;
                    }
                    holdSwellBack.start();
                }
            }
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
                    else if (root.centerInBar)
                        shown += root.barBodyInset;
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
            readonly property bool largeFace: root.searchActive || root.wallpaperActive || root.sessionActive
                || root.colorPickerActive || root.localSendRequestActive || root.bluetoothCardActive
                || root.dashboardActive

            /**
             * The morph away from a large face keeps the large-face curve.
             *
             * `largeFace` answers what the island shows *now*, and a Behaviour picks its
             * easing the frame the size changes - by then the face is already gone. So
             * closing the wallpaper browser ran on the small-face OutBack, and an
             * overshoot coming down from a browser-sized body undershoots the resting
             * pill by tens of pixels: the hard snap-back this used to bounce with on the
             * way out, while opening had been damped. Latched until that morph has run
             * its length, so the next small-face change gets its bounce back.
             */
            property bool settlingLarge: false
            readonly property bool dampedMorph: largeFace || settlingLarge
            onLargeFaceChanged: container.settlingLarge = !largeFace
            Timer {
                id: settlingTimer
                interval: container.morphMs
                onTriggered: container.settlingLarge = false
            }
            onSettlingLargeChanged: if (settlingLarge) settlingTimer.restart()

            readonly property int morphMs: Math.round((container.dampedMorph ? 420 : 500) * Appearance.animMultiplier)

            Behavior on animatedWidth {
                NumberAnimation {
                    duration: container.morphMs
                    easing.type: (container.closing || container.dampedMorph) ? Easing.BezierSpline : Easing.OutBack
                    easing.bezierCurve: container.dampedMorph && !container.closing
                        ? Appearance.animationCurves.standard
                        : Appearance.animationCurves.emphasizedDecel
                    easing.overshoot: 0.6
                }
            }

            readonly property bool returningToOverview: root.searchActive
                && LauncherSearch.query === ""
                && !root.searchPanelOwned
                && root.overviewVisible
                && container.animatedHeight > ((notchContent.overviewTargetHeight > 0 ? notchContent.overviewTargetHeight + notchContent.overviewGap : 0) + 54 + 10)

            Behavior on animatedHeight {
                NumberAnimation {
                    duration: container.closing ? root.centerBarCloseMs
                        : container.returningToOverview ? Appearance.animation.elementMoveFast.duration
                        : container.morphMs
                    easing.type: (container.closing || container.dampedMorph) ? Easing.BezierSpline : Easing.OutBack
                    easing.bezierCurve: container.dampedMorph && !container.closing
                        ? (container.returningToOverview ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.standard)
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
                // The hold's swell counts as width: the bar's groups move aside for it
                // the same way they do for an activity arriving.
                value: root.centerInBar
                    ? 2 * Math.round((root.pillShape
                        // No shoulders on a pill: only the body takes room in the bar.
                        ? (container.width - 2 * root.filletSize) * root.centerBarProgress
                        : container.width) * container.scale / 2)
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
                    && root.oledFade > 0
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
                enabled: root.clickToExpand && !root.explicitSurfaceActive && !root.expandSuppressed
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
                    y: (root.overviewAnimStyle === "none" || root.overviewPlainFade || root.searchActive) ? 0
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
                    y: (root.overviewAnimStyle === "none" || root.overviewPlainFade || root.searchActive) ? 0
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
