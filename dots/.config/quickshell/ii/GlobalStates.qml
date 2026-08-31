pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Singleton {
    id: root

    property alias sidebarLeftOpen: root.policiesPanelOpen // Until all sidebars naming is fixed
    property alias sidebarRightOpen: root.dashboardPanelOpen // Until all sidebars naming is fixed

    property bool barOpen: true
    property bool phoneCameraRunning: false
    property bool phoneMicRunning: false
    property int mediaModeCount: 0
    readonly property bool mediaModeActive: mediaModeCount > 0
    property var mediaModeMonitors: []
    property int mediaModeCloseAllTrigger: 0
    property int widgetReStackTrigger: 0

    readonly property bool activeWorkspaceHasWindows: {
        const activeWsId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? HyprlandData.activeWorkspace?.id;
        if (activeWsId === undefined || activeWsId === null) return false;
        return (HyprlandData.windowList ?? []).some(w => w.workspace?.id === activeWsId);
    }

    function setMediaModeActiveForScreen(screenName, active) {
        if (!screenName)
            return;
        var list = mediaModeMonitors.slice();
        var index = list.indexOf(screenName);
        if (active && index === -1) {
            list.push(screenName);
        } else if (!active && index !== -1) {
            list.splice(index, 1);
        }
        mediaModeMonitors = list;
    }

    function isMediaModeActiveForScreen(screenName) {
        if (!Config.options.background.mediaMode.togglePerMonitor) {
            return mediaModeActive;
        }
        if (!screenName)
            return false;
        return mediaModeMonitors.includes(screenName);
    }
    property bool alarmRinging: false
    property bool cheatsheetOpen: false
    // A stable tab id makes deep links independent from the user-configurable
    // tab order. Cheatsheet consumes this intent as soon as it opens.
    property string cheatsheetPendingTab: ""
    // Notification actions can ask the lazily-loaded timetable to land on a
    // concrete local date. A serial makes two clicks for the same day visible.
    property string timetableRequestedDate: ""
    property int timetableNavigationRequest: 0
    property bool crosshairOpen: false
    property bool notesOpen: false
    property bool mediaControlsOpen: false
    property bool mediaControlsPinned: false
    // Names of screens currently blacked out by the OLED saver overlay. Independent
    // per monitor: toggling one monitor doesn't affect the others.
    property var oledSaverMonitors: []
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool searchOnlyMode: false
    // Snapshot before the Overview receives focus. Window-management actions
    // must never target the layer-shell surface that hosts Search itself.
    property string searchTargetWindowAddress: ""

    function captureSearchTargetWindow(): void {
        let rawAddress = String(ToplevelManager.activeToplevel?.HyprlandToplevel?.address ?? "").trim();
        // Foreign-toplevel focus can be momentarily empty during a global
        // shortcut. Fall back to Hyprland's most recently focused client on
        // the current workspace instead of making every action unavailable.
        if (rawAddress.length === 0) {
            const workspaceId = Number(HyprlandData.activeWorkspace?.id ?? -1);
            const candidates = Array.from(HyprlandData.windowList ?? [])
                .filter(window => Number(window?.workspace?.id ?? -2) === workspaceId)
                .sort((left, right) => Number(left?.focusHistoryID ?? 9999) - Number(right?.focusHistoryID ?? 9999));
            rawAddress = String(candidates[0]?.address ?? "").trim();
        }
        root.searchTargetWindowAddress = rawAddress.length === 0
            ? ""
            : (rawAddress.startsWith("0x") ? rawAddress : `0x${rawAddress}`);
    }

    function openTimetableAt(dateValue): void {
        const text = String(dateValue ?? "").trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(text))
            return;
        const parts = text.split("-").map(Number);
        const date = new Date(parts[0], parts[1] - 1, parts[2]);
        if (Qt.formatDate(date, "yyyy-MM-dd") !== text)
            return;
        root.timetableRequestedDate = text;
        root.timetableNavigationRequest++;
        root.cheatsheetOpen = true;
    }

    // Legacy Gnome-like window transition state.  These values intentionally
    // remain global because the transition layer and the focused background
    // share the same transform clock in the original implementation.
    property real overviewZoomScale: 1.0
    property real overviewZoomOriginX: 0.5
    property real overviewZoomOriginY: 0.5

    // Shared trigger state for the per-monitor overview background controllers.
    // Scratchpad is derived here so wallpaper, widgets, blur and transitions do
    // not implement subtly different versions of the same predicate.
    readonly property bool scratchpadOpen: {
        const monitors = HyprlandData.monitors;
        if (!monitors)
            return false;
        return monitors.some(mon => mon.specialWorkspace && mon.specialWorkspace.name !== "");
    }
    readonly property bool overviewBackgroundActive: {
        const background = Config.options && Config.options.background;
        return Boolean(background && background.zoomOutEnabled
            && (root.overviewOpen || root.cheatsheetOpen || root.scratchpadOpen || root.usageOpen || root.modesOpen));
    }

    // BackgroundRoot owns one controller per monitor. Other background surfaces
    // retrieve that same object instead of reimplementing its preset formulas.
    property var overviewBackgroundControllers: ({})

    function registerOverviewBackgroundController(screenName, controller) {
        if (!screenName || !controller)
            return;
        const next = ({})
        for (const key in root.overviewBackgroundControllers)
            next[key] = root.overviewBackgroundControllers[key];
        next[screenName] = controller;
        root.overviewBackgroundControllers = next;
    }

    function unregisterOverviewBackgroundController(screenName, controller) {
        if (!screenName || root.overviewBackgroundControllers[screenName] !== controller)
            return;
        const next = ({})
        for (const key in root.overviewBackgroundControllers) {
            if (key !== screenName)
                next[key] = root.overviewBackgroundControllers[key];
        }
        root.overviewBackgroundControllers = next;
    }

    function overviewBackgroundControllerFor(screenName) {
        return root.overviewBackgroundControllers[screenName] ?? null;
    }

    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    // Shared transition clock for the bar and wrapped-frame visuals. Their
    // PanelWindows stay mapped while this runs; each layer chooses fade or
    // slide based on whether the wrapped frame is active.
    // Also driven by Edit Mode's Lockscreen tab, so the bar leaves the way
    // it does on a real lock instead of being torn down per tab switch.
    property real lockBarTransitionProgress: lockLookActive ? 1.0 : 0.0
    Behavior on lockBarTransitionProgress {
        // Use the non-overshooting effects curve for opacity. Spatial curves
        // overshoot and make a fade look like an abrupt blink.
        animation: Appearance.animation.elementMoveSlow.numberAnimation.createObject(root)
    }
    // ── Bar widget lifecycle ─────────────────────────────────────────────
    // Assigning `Config.options.bar.layouts.<group>` replaces the whole JS
    // array, so the Repeater backing that group destroys and recreates *every*
    // delegate — not only the one that changed. With no way to tell an arrival
    // from a rebuild, all of them replayed their entry animation and grew from
    // zero width at once: that is the flicker when a single widget is added or
    // removed, and it happened on every config reload too.
    //
    // This is the id census of the layout as it stood *before* the current
    // change. Delegates are recreated synchronously when the array is
    // reassigned, so they read this while it still describes the old layout;
    // the refresh is deferred to the next event loop pass on purpose.
    property var barLayoutSnapshot: ({})
    readonly property var _barLayoutIds: {
        const out = {};
        const groups = [Config.options.bar.layouts.left, Config.options.bar.layouts.center, Config.options.bar.layouts.right];
        for (let g = 0; g < groups.length; g++) {
            const group = groups[g];
            if (!group)
                continue;
            for (let i = 0; i < group.length; i++) {
                const id = group[i] ? group[i].id : "";
                if (!id)
                    continue;
                out[id] = (out[id] ?? 0) + 1;
            }
        }
        return out;
    }
    on_BarLayoutIdsChanged: Qt.callLater(() => root.barLayoutSnapshot = root._barLayoutIds)

    // The snapshot is filled in a deferred pass, which lands long before the bar
    // is first built — so without this the whole bar would come up silently at
    // startup. The first build flips it (deferred too, so every delegate in that
    // same build still counts as arriving) and from then on the census rules.
    property bool barWidgetsIntroduced: false

    // False for a widget that was already on the bar a moment ago — it is being
    // rebuilt, not arriving, and must land silently.
    function isNewBarWidget(widgetId) {
        if (!root.barWidgetsIntroduced)
            return true;
        if (!widgetId)
            return false;
        return (root.barLayoutSnapshot[widgetId] ?? 0) === 0;
    }

    // ── Bar placement swap ───────────────────────────────────────────────
    // Moving the bar between edges used to be a hard cut: the loaders were
    // destroyed and rebuilt on the other side. This is the shared clock that
    // turns it into a round trip — the shell retracts through the edge it is
    // on, the placement is written while it is off screen, and it comes back
    // in through the new edge. Every host multiplies its own outward direction
    // by this, so the direction flips on its own when the config does.
    property real barPlacementSwapProgress: 0
    property bool barPlacementSwapping: false
    property bool _pendingBarBottom: false
    property bool _pendingBarVertical: false

    // Returns false when there is nothing to do, so callers can fall back to a
    // plain write. Config is only touched from inside the animation.
    function requestBarPlacement(bottom, vertical) {
        if (!Config.ready)
            return false;
        if (Config.options.bar.bottom === bottom && Config.options.bar.vertical === vertical)
            return false;
        root._pendingBarBottom = bottom;
        root._pendingBarVertical = vertical;
        barPlacementSwapAnim.restart();
        return true;
    }

    SequentialAnimation {
        id: barPlacementSwapAnim
        PropertyAction {
            target: root
            property: "barPlacementSwapping"
            value: true
        }
        NumberAnimation {
            target: root
            property: "barPlacementSwapProgress"
            to: 1
            duration: Appearance.animation.shellEdgeSlide.exitDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        ScriptAction {
            script: {
                Config.options.bar.bottom = root._pendingBarBottom;
                Config.options.bar.vertical = root._pendingBarVertical;
            }
        }
        // The bar loaders are torn down and rebuilt on the config change
        // (see barExtraCondition in IllogicalImpulseFamily). Hold off screen
        // long enough for the new ones to exist before sliding them in.
        PauseAnimation {
            duration: Appearance.animation.shellEdgeSlide.swapHold
        }
        NumberAnimation {
            target: root
            property: "barPlacementSwapProgress"
            to: 0
            duration: Appearance.animation.shellEdgeSlide.enterDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        PropertyAction {
            target: root
            property: "barPlacementSwapping"
            value: false
        }
    }

    property bool lockScreenCentered: false
    property bool lockAnimationActive: false
    property bool workspaceRestoreInProgress: false
    property bool capsLockActive: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    // Ripple signal: emitted by LockSurface on click, received by Background.qml
    // (WlSessionLock and WlrLayershell panels can't directly share children)
    signal lockScreenRipple(x: real, y: real)
    // Asked for by the AI composer's screenshot button, answered by the region
    // selector. The composer has no way of reaching it otherwise: it is a
    // Scope in the shell tree, not a singleton.
    signal snipForAiRequested
    property bool sessionOpen: false
    property bool superDown: false
    property bool usageOpen: false
    property bool modesOpen: false
    // Transient "Work mode on" banner: set by the Modes engine for ~3 s.
    // Payload: { kind: "mode"|"routine", id, icon, color, title, subtitle }
    property bool modeFlashActive: false
    property var modeFlashPayload: null
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property string wallpaperSelectorTarget: "desktop" // "desktop" or "lockscreen"
    property bool workspaceShowNumbers: false
    property bool filePickerOpen: false
    property bool videoEditorPopupOpen: false
    property bool videoEditorOpen: false
    property string videoEditorPath: ""
    property bool screenshotOverlayOpen: false
    property string screenshotOverlayImagePath: ""
    // Monitor that owns the current screenshot preview overlay.
    property string screenshotOverlayMonitor: ""
    property real screenshotOverlayRegionX: 0
    property real screenshotOverlayRegionY: 0
    property real screenshotOverlayRegionW: 0
    property real screenshotOverlayRegionH: 0
    property bool settingsOpen: false
    property int settingsPendingPage: -1
    property string settingsPendingSubPage: ""
    property string settingsPendingPageName: ""
    // Section to land on inside the page. Held here rather than passed along,
    // because the settings window may not exist yet when the deep link is
    // made — the same reason the page and sub-page wait here.
    property string settingsPendingSection: ""
    // Which tab the Network page was left on. The page itself is destroyed the
    // moment another settings page is picked, so it cannot remember anything;
    // held here it survives until the shell reloads, which is where the Wi-Fi
    // default comes back.
    property int settingsNetworkTab: 0
    // Welcome is an in-process window. Keep its lifecycle in the shared state
    // graph so first-run, keybinds and Settings deep links all use one owner.
    property bool welcomeOpen: false
    // A serial makes repeated requests observable even when the same page is
    // requested twice while Settings is already visible.
    property int settingsNavigationRequest: 0
    property string activeLeftSidebarMonitor: ""
    property string activeRightSidebarMonitor: ""

    // ── Edit Mode ────────────────────────────────────────────────────────────
    // `editMode` is the switch: the keybind, the IPC target, the Escape ladder
    // and the toolbar's Done flip it, and everything the mode does hangs off
    // the change handler below.
    // The history below is inert outside the mode: entries are only recorded
    // while it is on and dropped when it ends, so an edit made on the plain
    // desktop is exactly as unrecorded as it always was.
    property bool editMode: false

    // The screen the mode is on (decision D4: only the desktop focused at
    // entry shrinks). Left pointing at it through the exit animation so the
    // desktop that shrank is the one that grows back; the next entry re-points
    // it.
    property string editModeMonitor: ""
    // The per-widget menu, one at a time shell-wide. It is drawn by the edit
    // chrome of the screen it was summoned on (the canvas sits on Bottom, under
    // the bar and dock, so a menu drawn there could be covered) and acts on
    // the widget through the canvas that announced the right-click, which is
    // the one that knows the widget by its instance id. Screen coordinates.
    property bool editWidgetMenuOpen: false
    property string editWidgetMenuInstanceId: ""
    property string editWidgetMenuScreenName: ""
    property real editWidgetMenuX: 0
    property real editWidgetMenuY: 0
    property var editWidgetMenuCanvas: null

    // The drawer - the mode's catalogue - and its own animated scalar, beside
    // `editProgress` rather than a second animation of it: this one carries
    // the slide and the desktop's sideways travel, that one the shrink.
    // `&& editMode` so the exit closes the drawer even if nothing wrote the
    // flag back, and both scalars run down together on the same tier.
    property bool editDrawerOpen: false
    // Whether the catalogue's search field holds the keyboard. The chrome's
    // surface raises it while the field is focused; the desktop's canvas - the
    // mode's real key surface - reads it to know when to take the keyboard back
    // (BackgroundWidgetsWindow).
    property bool editSearchFocused: false
    // Ctrl+F. The key arrives on the canvas, which is the only surface in the
    // mode holding a keyboard, and the drawer on the edited screen answers it.
    signal editSearchFocusRequested()
    // The other direction: a press that is not on the field lets it go. The
    // chrome's own catcher answers presses on its surface; this carries the
    // ones that land on the desktop, which is a surface the drawer cannot see.
    signal editSearchReleaseRequested()
    property real editDrawerProgress: root.editMode && root.editDrawerOpen ? 1 : 0
    Behavior on editDrawerProgress {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }
    // The drawer's reveal in screen coordinates, keyed by screen name and
    // published by the chrome surface: the widget being carried back into it
    // is on another layer surface and cannot read the chrome's items.
    property var editDrawerReveals: ({})
    // The screen whose drawer a dragged desktop widget is over, "" for none -
    // what the drawer paints its remove tint from.
    property string editDrawerDropScreen: ""
    // The drop itself, answered by the chrome side. A signal, because dropping
    // the same widget twice is two gestures.
    signal editWidgetDroppedOnDrawer(string instanceId)

    // The desktop's right-click menu: which screen, where on it. Session
    // state like the widget menu's; exists in and out of Edit Mode.
    property bool desktopMenuOpen: false
    property string desktopMenuScreenName: ""
    property real desktopMenuX: 0
    property real desktopMenuY: 0
    // Whether the wallpaper row is offered: the bar asks for the menu too, and
    // a bar is not a place to pick a wallpaper from.
    property bool desktopMenuWallpaper: true

    function openDesktopMenu(screenName, x, y, wallpaper = true) {
        root.closeEditWidgetMenu();
        root.closeEditBarMenu();
        root.desktopMenuWallpaper = wallpaper;
        root.desktopMenuScreenName = screenName;
        root.desktopMenuX = x;
        root.desktopMenuY = y;
        root.desktopMenuOpen = true;
    }

    function closeDesktopMenu() {
        root.desktopMenuOpen = false;
    }

    // The bar, edited in place: a reorder drag in flight (a gesture for the
    // Escape ladder) and the per-widget menu, which the chrome surface draws
    // because the bar's own window is too thin to hold it. The point is in
    // the bar window's coordinates with that window's size alongside, so the
    // host can place it from whichever screen edge the bar sits on.
    property bool editBarDragActive: false
    signal editBarDragCancel()

    // Which controller answers for a screen's bar. Edit Mode's catalogue is
    // drawn on the chrome's surface and a row dragged out of it onto the bar
    // crosses into another layer surface, which it has no way to reach; the
    // chrome looks the bar up here and hands it the pointer. A list per screen
    // because both orientations declare a controller and the plain bar window
    // and Connect Mode's panel can hold one each - the drawn one is the one
    // that reports itself usable.
    property var editBarControllers: ({})

    function registerBarEditController(screenName, controller) {
        const next = {};
        for (const key in root.editBarControllers) {
            const kept = root.editBarControllers[key].filter(c => c && c !== controller);
            if (kept.length > 0)
                next[key] = kept;
        }
        if (screenName !== "")
            next[screenName] = (next[screenName] ?? []).concat([controller]);
        root.editBarControllers = next;
    }

    function unregisterBarEditController(controller) {
        root.registerBarEditController("", controller);
    }

    function barEditControllerFor(screenName) {
        return (root.editBarControllers[screenName] ?? []).find(c => c && c.usable) ?? null;
    }
    property bool editBarMenuOpen: false
    property string editBarMenuScreenName: ""
    property var editBarMenuController: null
    property int editBarMenuBucket: -1
    property int editBarMenuIndex: -1
    property bool editBarMenuCentered: false
    property real editBarMenuX: 0
    property real editBarMenuY: 0
    property real editBarMenuWindowWidth: 0
    property real editBarMenuWindowHeight: 0

    function openEditBarMenu(screenName, controller, bucket, index, centered, x, y, windowWidth, windowHeight) {
        if (!root.editMode)
            return;
        root.closeDesktopMenu();
        root.closeEditWidgetMenu();
        root.editBarMenuScreenName = screenName;
        root.editBarMenuController = controller;
        root.editBarMenuBucket = bucket;
        root.editBarMenuIndex = index;
        root.editBarMenuCentered = centered;
        root.editBarMenuX = x;
        root.editBarMenuY = y;
        root.editBarMenuWindowWidth = windowWidth;
        root.editBarMenuWindowHeight = windowHeight;
        root.editBarMenuOpen = true;
    }

    function closeEditBarMenu() {
        root.editBarMenuOpen = false;
        root.editBarMenuController = null;
    }

    // ── Bar widget name on hover ──────────────────────────────────────────
    // Several bar widgets are a bare icon, and while Edit Mode is on the idle
    // ones are standing in for something that is not happening, so the name is
    // worth having under the pointer. It cannot be a tooltip drawn in the bar:
    // Edit Mode's toolbar sits right under the bar on a surface of its own and
    // covers it. The bar reports which widget is hovered and where, and the
    // chrome draws the label on the surface that is on top.
    property var editBarHoverSlot: null
    property string editBarHoverName: ""
    property string editBarHoverScreenName: ""
    property real editBarHoverX: 0
    property real editBarHoverY: 0
    property real editBarHoverWindowWidth: 0
    property real editBarHoverWindowHeight: 0
    readonly property bool editBarHoverShown: root.editBarHoverSlot !== null && root.editBarHoverName.length > 0

    function showEditBarHover(slot, screenName, name, x, y, windowWidth, windowHeight) {
        if (!root.editMode || root.editBarDragActive)
            return;
        root.editBarHoverName = name;
        root.editBarHoverScreenName = screenName;
        root.editBarHoverX = x;
        root.editBarHoverY = y;
        root.editBarHoverWindowWidth = windowWidth;
        root.editBarHoverWindowHeight = windowHeight;
        root.editBarHoverSlot = slot;
    }

    function clearEditBarHover(slot) {
        // Only whoever put the label up may take it down: crossing from one
        // widget straight onto the next fires the arrival before the departure,
        // and the departure would otherwise clear the label just raised.
        if (slot !== null && root.editBarHoverSlot !== slot)
            return;
        root.editBarHoverSlot = null;
    }

    function openEditWidgetMenu(canvas, instanceId, screenName, x, y) {
        if (!root.editMode)
            return;
        root.closeDesktopMenu();
        root.closeEditBarMenu();
        root.editWidgetMenuCanvas = canvas;
        root.editWidgetMenuInstanceId = instanceId;
        root.editWidgetMenuScreenName = screenName;
        root.editWidgetMenuX = x;
        root.editWidgetMenuY = y;
        root.editWidgetMenuOpen = true;
    }

    function closeEditWidgetMenu() {
        root.editWidgetMenuOpen = false;
        root.editWidgetMenuCanvas = null;
        root.editWidgetMenuInstanceId = "";
    }

    // The entry and the exit as ONE animated scalar. The desktop lives on two
    // layer surfaces (the wallpaper and the widgets, two scene graphs) and the
    // chrome framing it on a third; all three derive their geometry from this
    // number, so a Behavior anywhere else would be two values that have to
    // agree - and the frames where they do not are the ones where the chrome
    // frames a rectangle the desktop is not at. `elementMove` whole, not an
    // enter/exit tier: those carry alwaysRunToEnd, and a mode toggled twice
    // inside its own duration would finish arriving before it started leaving.
    property real editProgress: root.editMode ? 1 : 0
    Behavior on editProgress {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(root)
    }

    // Which face of the desktop the viewport shows: a FILTER, never a mode of
    // its own - one entry, one exit ladder. The Lockscreen tab arrives with
    // stage 7b; until then this only ever holds the desktop.
    property string editTab: EditModeLogic.desktopTab
    readonly property bool editLockPreview: root.editMode && root.editTab === EditModeLogic.lockscreenTab
    // "The lock's LOOK is on screen": the real lock session or the preview of
    // it. The one derivation the theme sites are meant to read, so the preview
    // can never show the lock's wallpaper under the desktop's palette.
    readonly property bool lockLookActive: root.screenLocked || root.editLockPreview

    // The edge each dock occupies, published by the dock window itself
    // (screen name -> { side, thickness }). The dock is the one place that
    // knows its padding and style, so the mode's viewport reads this rather
    // than deriving the dock's size a second time.
    property var dockInsets: ({})
    function setDockInset(screenName, side, thickness) {
        if (!screenName)
            return;
        const next = Object.assign({}, root.dockInsets);
        if (!side || !(thickness > 0))
            delete next[screenName];
        else
            next[screenName] = { "side": side, "thickness": thickness };
        root.dockInsets = next;
    }

    function openEditMode() {
        if (root.editMode)
            return;
        // Nothing to edit without a desktop, and nothing to see while the
        // lock or media mode holds the screen.
        if (!Config.options.background.enable || root.screenLocked || root.mediaModeActive)
            return;
        // Full-screen modes over the same desktop close first rather than
        // having the mode layered under them.
        root.overviewOpen = false;
        root.sessionOpen = false;
        root.editMode = true;
    }

    function closeEditMode() {
        root.editMode = false;
    }

    function toggleEditMode() {
        if (root.editMode)
            root.closeEditMode();
        else
            root.openEditMode();
    }

    function _enterEditMode() {
        root.editTab = EditModeLogic.desktopTab;
        root.editModeMonitor = Hyprland.focusedMonitor?.name ?? Quickshell.primaryScreen?.name ?? "";
        // Panels covering the desktop being edited close, and stay closed: the
        // sidebar open handlers refuse them for the length of the mode.
        root.policiesPanelOpen = false;
        root.dashboardPanelOpen = false;
        root.mediaControlsOpen = false;
        root._editClearWorkspace();
    }

    function _leaveEditMode() {
        root.closeEditWidgetMenu();
        root.closeEditBarMenu();
        root.closeDesktopMenu();
        root.clearEditBarHover(null);
        root.editBarDragActive = false;
        // The drawer and its drop hint are the mode's: one left open would
        // greet the next entry mid-slide.
        root.editDrawerOpen = false;
        root.editDrawerDropScreen = "";
        // The lock now owns every monitor's workspace - it parks them itself
        // and restores its own record on unlock - so a restore fired here
        // would fight it. The saved pair waits for the unlock instead.
        if (root.screenLocked)
            return;
        root._editRestoreWorkspace();
    }

    // ---- the workspace under the mode ------------------------------------
    //
    // The mode can be entered over windows (the keybind), and windows cover
    // the desktop being edited. The lock's route: the focused monitor moves to
    // an empty workspace for the length of the mode and comes back on exit.
    // The empty workspace is the lock's own temp id for the workspace it
    // replaces (2147483647 - id), which the parallax and the workspace
    // indicator already map back to the real one, so nothing visibly jumps.
    // Pinned windows are ignored: they follow to the temp workspace anyway.
    property int _editSavedWorkspace: 0
    property int _editTempWorkspace: 0

    function _editClearWorkspace() {
        root._editSavedWorkspace = 0;
        root._editTempWorkspace = 0;
        const mon = root.editModeMonitor;
        if (mon === "")
            return;
        const mData = HyprlandData.monitors.find(m => m.name === mon);
        const ws = mData?.activeWorkspace?.id;
        if (ws === undefined || ws === null)
            return;
        let batch = "";
        // A special workspace is summoned over the desktop; close it first,
        // as the lock does.
        const specName = mData.specialWorkspace?.name ?? "";
        if (specName !== "" && (mData.specialWorkspace?.id ?? 0) !== 0) {
            let clean = specName.startsWith("special:") ? specName.substring(8) : specName;
            if (!clean)
                clean = "special";
            batch += ` ; dispatch hl.dsp.focus {monitor="${mon}"} ; dispatch hl.dsp.workspace.toggle_special('${clean}')`;
        }
        // Already parked on a temp workspace (the lock's, or ours): nothing to
        // clear, and nothing of ours to restore.
        if (ws <= 1000000) {
            const hasWindows = (HyprlandData.windowList ?? []).some(w => w.workspace?.id === ws && !w.pinned);
            if (hasWindows) {
                const temp = 2147483647 - ws;
                batch += ` ; dispatch hl.dsp.focus {monitor="${mon}"} ; dispatch hl.dsp.focus {workspace=${temp}}`;
                root._editSavedWorkspace = ws;
                root._editTempWorkspace = temp;
            }
        }
        if (batch !== "")
            Quickshell.execDetached(["hyprctl", "--batch", batch.substring(3)]);
    }

    function _editRestoreWorkspace() {
        const mon = root.editModeMonitor;
        const saved = root._editSavedWorkspace;
        const temp = root._editTempWorkspace;
        root._editSavedWorkspace = 0;
        root._editTempWorkspace = 0;
        if (saved === 0 || mon === "")
            return;
        // Only put back a monitor still parked where the entry left it: a
        // user who switched workspaces during the mode has moved on. The saved
        // id is accepted too, because HyprlandData refreshes asynchronously
        // and a mode left within that window still reads the pre-entry state;
        // focusing a workspace the monitor is already on is a no-op.
        const mData = HyprlandData.monitors.find(m => m.name === mon);
        const current = mData?.activeWorkspace?.id ?? 0;
        if (current !== temp && current !== saved)
            return;
        Quickshell.execDetached(["hyprctl", "--batch", `dispatch hl.dsp.focus {monitor="${mon}"} ; dispatch hl.dsp.focus {workspace=${saved}}`]);
    }

    Timer {
        id: editUnlockRestoreTimer
        // After the lock's own restore (Lock.qml waits 450 ms for its zoom-in
        // before dispatching), so the two batches never race.
        interval: 800
        repeat: false
        onTriggered: root._editRestoreWorkspace()
    }

    Connections {
        target: root

        // Anything that takes the desktop off the screen ends the mode: the
        // lock repurposes the background as its own backdrop, the overview and
        // the session menu cover it, media mode promotes the wallpaper over
        // everything, and Connect mode rebuilds the bar the mode will edit.
        function onScreenLockedChanged() {
            if (root.screenLocked) {
                root.editMode = false;
                return;
            }
            if (root._editSavedWorkspace !== 0)
                editUnlockRestoreTimer.restart();
        }

        function onOverviewOpenChanged() {
            if (root.overviewOpen)
                root.editMode = false;
        }

        function onSessionOpenChanged() {
            if (root.sessionOpen)
                root.editMode = false;
        }

        function onMediaModeActiveChanged() {
            if (root.mediaModeActive)
                root.editMode = false;
        }

        function onConnectModeActiveChanged() {
            if (root.connectModeActive)
                root.editMode = false;
        }
    }

    // Undo and redo, as two stacks of {undo, redo} closures. Closures rather
    // than diffs: each commit site knows how to reverse and replay its own
    // store write, and no one serialiser covers every store the mode edits.
    // The stacks are reassigned, never mutated in place - a `property var`
    // only notifies on reassignment, so an in-place push would leave every
    // observer of `editCanUndo` reading a depth that never moves.
    property var editUndoStack: []
    property var editRedoStack: []
    readonly property bool editCanUndo: editUndoStack.length > 0
    readonly property bool editCanRedo: editRedoStack.length > 0

    // While a batch is open, pushes collect; closing it folds them into ONE
    // entry, so a gesture that commits several writes (a group drag, a burst
    // of arrow keys, a resize with its re-centre) is one Ctrl+Z. Undo replays
    // a batch backwards and redo forwards: three arrow steps on one widget
    // push "back to 36", "back to 48", "back to 60", and reversing them in
    // push order would leave the widget at 60.
    property var _editHistoryBatch: null
    property bool _editHistoryReplaying: false

    function editHistoryBeginBatch() {
        if (root._editHistoryBatch === null)
            root._editHistoryBatch = [];
    }

    function editHistoryEndBatch() {
        const entries = root._editHistoryBatch;
        root._editHistoryBatch = null;
        if (entries === null || entries.length === 0)
            return;
        if (entries.length === 1) {
            root._editHistoryCommit(entries[0]);
            return;
        }
        root._editHistoryCommit({
            "undo": () => {
                for (let i = entries.length - 1; i >= 0; i--)
                    entries[i].undo();
            },
            "redo": () => {
                for (let i = 0; i < entries.length; i++)
                    entries[i].redo();
            }
        });
    }

    // entry: {undo: function, redo: function}. Recorded only while the mode
    // is on, and never while a replay runs - an undo that re-recorded the
    // write it reverses would never converge.
    function editHistoryPush(entry) {
        if (!root.editMode || root._editHistoryReplaying)
            return;
        if (!entry || typeof entry.undo !== "function" || typeof entry.redo !== "function")
            return;
        if (root._editHistoryBatch !== null) {
            root._editHistoryBatch.push(entry);
            return;
        }
        root._editHistoryCommit(entry);
    }

    // A new edit invalidates the redo stack: what it held was a future the
    // user has now diverged from.
    function _editHistoryCommit(entry) {
        root.editUndoStack = EditModeLogic.undoPush(root.editUndoStack, entry);
        root.editRedoStack = [];
    }

    function editUndo() {
        if (root._editHistoryBatch !== null)
            root.editHistoryEndBatch();
        const popped = EditModeLogic.undoPop(root.editUndoStack);
        root.editUndoStack = popped.stack;
        if (popped.entry === null)
            return;
        root._editHistoryReplay(popped.entry.undo);
        root.editRedoStack = EditModeLogic.undoPush(root.editRedoStack, popped.entry);
    }

    function editRedo() {
        const popped = EditModeLogic.undoPop(root.editRedoStack);
        root.editRedoStack = popped.stack;
        if (popped.entry === null)
            return;
        root._editHistoryReplay(popped.entry.redo);
        root.editUndoStack = EditModeLogic.undoPush(root.editUndoStack, popped.entry);
    }

    function _editHistoryReplay(fn) {
        root._editHistoryReplaying = true;
        try {
            fn();
        } finally {
            root._editHistoryReplaying = false;
        }
    }

    function editHistoryClear() {
        root._editHistoryBatch = null;
        root.editUndoStack = [];
        root.editRedoStack = [];
    }

    onEditModeChanged: {
        if (root.editMode) {
            root._enterEditMode();
            return;
        }
        root._leaveEditMode();
        // Done means "stop": the history is about this session of the mode,
        // and a stack surviving it would let the next entry undo edits made
        // outside it.
        root.editHistoryClear();
    }

    function isScreenAllowedForBar(screen) {
        if (!screen)
            return false;
        if (!Config.ready)
            return true;
        if (Config.options.bar.onlyShowOnSingleMonitor) {
            return screen.name === Config.options.bar.singleMonitorName;
        }
        const list = Config.options.bar.screenList;
        if (list && list.length > 0) {
            return list.includes(screen.name);
        }
        return true;
    }

    readonly property var allowedScreens: {
        if (!Config.ready)
            return Quickshell.screens;
        return Quickshell.screens.filter(screen => root.isScreenAllowedForBar(screen));
    }

    readonly property string effectiveLeftMonitor: {
        if (!Config.ready)
            return "";
        switch (Config.options.sidebar.position) {
        case "default":
            return activeLeftSidebarMonitor;
        case "inverted":
            return activeRightSidebarMonitor;
        case "left":
            return policiesPanelOpen ? activeLeftSidebarMonitor : activeRightSidebarMonitor;
        case "right":
            return "";
        default:
            return activeLeftSidebarMonitor;
        }
    }

    readonly property string effectiveRightMonitor: {
        if (!Config.ready)
            return "";
        switch (Config.options.sidebar.position) {
        case "default":
            return activeRightSidebarMonitor;
        case "inverted":
            return activeLeftSidebarMonitor;
        case "left":
            return "";
        case "right":
            return policiesPanelOpen ? activeLeftSidebarMonitor : activeRightSidebarMonitor;
        default:
            return activeRightSidebarMonitor;
        }
    }
    property string activeSearchMonitor: ""
    property real activeSearchHeight: 0
    property real activeSearchWidth: 0
    property string activeSearchQuery: ""
    // Search panels are lazy and may be hosted on any monitor. Keep a small
    // transient intent here so callers do not need to know which SearchWidget
    // instance will render it.
    property string searchPendingPanel: ""
    property string searchPendingPanelQuery: ""
    property int searchPanelNavigationRequest: 0
    // A search result snapshot belongs to the File Browser surface, not to a
    // second LauncherSearch provider. The monotonically increasing request lets
    // a kept-alive panel consume each transient handoff exactly once.
    property var fileBrowserSearchResults: []
    property string fileBrowserSearchQuery: ""
    property int fileBrowserSearchRequest: 0
    property bool searchDropActive: false
    property real searchDropExclusionX: 0
    property real searchDropExclusionY: 0
    property real searchDropExclusionWidth: 0
    property real searchDropExclusionHeight: 0
    property real searchDropTopRadius: 0
    property real searchDropBottomRadius: 0

    property bool osdDropActive: false
    property real osdDropExclusionX: 0
    property real osdDropExclusionY: 0
    property real osdDropExclusionWidth: 0
    property real osdDropExclusionHeight: 0
    property real osdDropTopRadius: 0
    property real osdDropBottomRadius: 0

    property string osdCurrentIndicator: "volume"
    property string osdProtectionMessage: ""
    signal osdInteraction
    property bool policiesExtended: false
    property bool policiesPinned: false
    property bool policiesDetached: false

    // Bluetooth connection OSD override
    property bool blockVolumeOsdForBluetooth: false
    Connections {
        target: BluetoothStatus
        ignoreUnknownSignals: true
        function onDeviceConnected(device) {
            root.blockVolumeOsdForBluetooth = true;
            blockOsdTimer.restart();
        }
        function onDeviceDisconnected(device) {
            root.blockVolumeOsdForBluetooth = true;
            blockOsdTimer.restart();
        }
    }
    property Timer blockOsdTimer: Timer {
        id: blockOsdTimer
        interval: 4000
        onTriggered: root.blockVolumeOsdForBluetooth = false
    }

    // Bluetooth connection popup
    property bool bluetoothConnectionPopupOpen: false
    property var bluetoothConnectionPopupDevice: null

    // Floating Notch Bluetooth notification
    property var floatingNotchBtDevice: null
    property string floatingNotchBtAction: "connected"
    property bool floatingNotchBtNotifActive: false

    // LocalSend transfer popup
    property bool localSendPopupOpen: false
    property var localSendPopupTransfer: null

    // Media Popup placement (transient, non-persistent)
    property rect mediaPopupRect: Qt.rect(0, 0, 0, 0)
    property bool mediaWidgetHovered: false
    property Timer mediaWidgetHoverTimer: Timer {
        id: mediaWidgetHoverTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.mediaWidgetHovered = false;
        }
    }

    function setMediaWidgetHovered(hovered) {
        if (hovered) {
            mediaWidgetHoverTimer.stop();
            root.mediaWidgetHovered = true;
        } else {
            mediaWidgetHoverTimer.restart();
        }
    }

    // Color Picker Popup
    property bool colorPickerPopupOpen: false
    property string colorPickerPopupColor: ""

    function pickColor(hex) {
        if (hex && hex.startsWith("#")) {
            root.colorPickerPopupColor = hex;
            if (Config.options && Config.options.bar && Config.options.bar.tooltips && Config.options.bar.tooltips.enablePopups && Config.options.bar.tooltips.enableColorPickerPopup) {
                root.colorPickerPopupOpen = false;
                Qt.callLater(() => {
                    root.colorPickerPopupOpen = true;
                });
            }
        }
    }

    function launchColorPicker() {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "colorPickerLaunch", "trigger"]);
    }

    IpcHandler {
        target: "pickColor"
        function handle(hex: string): void {
            root.pickColor(hex);
        }
    }

    function launchLosslessCut(path) {
        root.videoEditorPath = path;
        root.videoEditorPopupOpen = false;
        root.videoEditorOpen = false;
        Quickshell.execDetached(["gio", "launch", Directories.losslessCutDesktopPath, path]);
    }

    function launchVideoEditor(path) {
        root.videoEditorPath = path;
        // The "Recording Finished" prompt is opt-out: keep the path around so the
        // editor can still be opened manually, just don't pop anything up.
        if (!Config.options.screenRecord.showEditPrompt)
            return;
        root.videoEditorPopupOpen = true;
    }

    IpcHandler {
        target: "launchVideoEditor"
        function handle(path: string): void {
            root.launchVideoEditor(path);
        }
    }

    function toggleSettings() {
        root.settingsOpen = !root.settingsOpen;
    }

    function openSettings() {
        root.settingsOpen = true;
    }

    /**
     * Opens the settings window at a page, and optionally at a sub-page and a
     * section within it.
     *
     * `sectionId` is the section's title, which is what the window already
     * highlights by when a link inside settings points at one. It used to be
     * accepted here and dropped on the floor, so every caller outside the
     * settings window could only reach the top of a page.
     */
    function openSettingsPage(pageId, subPageId, sectionId) {
        const targetSubPage = subPageId || "";
        const targetSection = sectionId || "";
        if (!pageId || pageId === "") {
            root.settingsPendingPageName = "";
            root.settingsPendingSubPage = targetSubPage;
            root.settingsPendingSection = targetSection;
            root.settingsOpen = true;
            return;
        }

        if (SettingsPageRegistry.pageIndexById(pageId) < 0)
            return;

        root.settingsPendingPageName = pageId;
        root.settingsPendingSubPage = targetSubPage;
        root.settingsPendingSection = targetSection;
        root.settingsNavigationRequest += 1;
        root.settingsOpen = true;
    }

    function consumePendingSettingsPage() {
        const pending = root.settingsPendingPageName;
        root.settingsPendingPageName = "";
        return pending;
    }

    function toggleWelcome() {
        root.welcomeOpen = !root.welcomeOpen;
    }

    function openWelcome() {
        root.welcomeOpen = true;
    }

    function closeWelcome() {
        root.welcomeOpen = false;
    }

    function toggleCheatsheet() {
        root.cheatsheetOpen = !root.cheatsheetOpen;
    }

    function openCheatsheet(tabId) {
        root.cheatsheetPendingTab = String(tabId ?? "");
        if (root.cheatsheetOpen) {
            root.cheatsheetOpen = false;
        }
        root.cheatsheetOpen = true;
    }

    function closeCheatsheet() {
        root.cheatsheetOpen = false;
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            root.toggleSettings();
        }

        function open(): void {
            root.openSettings();
        }

        function openPage(pageId: string): void {
            root.openSettingsPage(pageId);
        }

        function openSection(pageId: string, sectionTitle: string): void {
            root.openSettingsPage(pageId, "", sectionTitle);
        }

        function openSubPage(pageId: string, subPage: string): void {
            root.openSettingsPage(pageId, subPage || "");
        }

    }
    IpcHandler {
        target: "welcome"

        function toggle(): void {
            root.toggleWelcome();
        }

        function open(): void {
            root.openWelcome();
        }

        function close(): void {
            root.closeWelcome();
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.toggleCheatsheet();
        }

        function open(): void {
            root.openCheatsheet();
        }

        function openTab(tabId: string): void {
            root.openCheatsheet(tabId);
        }

        function close(): void {
            root.closeCheatsheet();
        }
    }

    IpcHandler {
        target: "osd"

        function trigger(): void {
            root.osdCurrentIndicator = "volume";
            root.osdVolumeOpen = true;
            root.osdInteraction();
        }

        function toggle(): void {
            root.osdVolumeOpen = !root.osdVolumeOpen;
            if (root.osdVolumeOpen) {
                root.osdInteraction();
            }
        }

        function hide(): void {
            root.osdVolumeOpen = false;
        }

        function open(): void {
            root.osdCurrentIndicator = "volume";
            root.osdVolumeOpen = true;
            root.osdInteraction();
        }
    }

    GlobalShortcut {
        name: "settingsToggle"
        description: "Toggles the settings window"
        onPressed: root.toggleSettings()
    }

    readonly property bool connectModeActive: ShellModePolicy.connectModeActive

    // In Float mode (cornerStyle 1), sidebars remain as separate PanelWindows
    // rather than being embedded in the TopLayer. Only search/OSD are integrated.
    readonly property bool connectSidebarsSeparate: {
        return connectModeActive && Config.options.bar.cornerStyle === 1;
    }

    readonly property bool searchCenterMode: {
        if (!Config.ready)
            return false;
        return Config.options.search.positionStyle === "center";
    }

    readonly property bool searchConnectActive: {
        if (!connectModeActive)
            return false;
        if (root.searchCenterMode)
            return false;
        if (Config.options.search.connectStyle !== "connect")
            return false;

        // All corner styles supported
        return true;
    }

    // The floating Dynamic Island is the sole owner of the search surface
    // while it is enabled. Its PanelWindow chooses the configured target
    // monitor, so ownership must not depend on the monitor that opened it.
    readonly property bool floatingNotchOwnsSearch: {
        if (!Config.ready || !root.overviewOpen)
            return false;

        const notch = Config.options.bar.floatingNotch;
        if (!notch || !notch.enable || notch.centerInBar)
            return false;

        return true;
    }

    readonly property bool osdConnectActive: {
        if (!connectModeActive)
            return false;

        // All corner styles supported
        return true;
    }

    function enforceSidebarStyle() {
        if (!Config.ready)
            return;
        if (ShellModePolicy.shouldForceDefault) {
            Config.options.sidebar.sidebarStyle = "default";
        }
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) {
                root.enforceSidebarStyle();
            }
        }
    }

    Connections {
        target: Config.ready ? Config.options.bar : null
        function onBarBackgroundStyleChanged() {
            root.enforceSidebarStyle();
        }
    }

    Connections {
        target: Config.ready ? Config.options.sidebar : null
        function onSidebarStyleChanged() {
            root.enforceSidebarStyle();
        }
    }

    property real _lastPoliciesWidth: Appearance.sizes.sidebarWidth + 300

    onPoliciesWidthChanged: {
        if (Config.ready && !policiesExtended) {
            _lastPoliciesWidth = policiesWidth;
        }
    }

    readonly property real policiesWidth: {
        if (policiesExtended)
            return Appearance.sizes.sidebarWidthExtended;

        if (!Config.ready)
            return _lastPoliciesWidth;

        const p = Config.options.policies;
        let activeCount = 0;
        if (p.ai !== 0)
            activeCount++;
        if (p.translator !== 0)
            activeCount++;
        if (p.player !== 0)
            activeCount++;
        if (p.wallpapers !== 0)
            activeCount++;
        if (p.weeb !== 0 && p.weeb !== 2)
            activeCount++;
        if (p.phone !== 0)
            activeCount++;

        const minTabs = 3;
        const perTabWidth = 100;
        return Appearance.sizes.sidebarWidth + Math.max(0, activeCount - minTabs) * perTabWidth;
    }

    readonly property real dashboardWidth: Appearance.sizes.sidebarWidth

    readonly property real leftSidebarTargetWidth: {
        if (!effectiveLeftOpen)
            return 0;
        switch (Config.options.sidebar.position) {
        case "default":
            return policiesDetached ? 0 : policiesWidth;
        case "inverted":
            return dashboardWidth;
        case "left":
            if (policiesPanelOpen)
                return policiesDetached ? 0 : policiesWidth;
            if (dashboardPanelOpen)
                return dashboardWidth;
            return 0;
        default:
            return policiesDetached ? 0 : policiesWidth;
        }
    }

    readonly property real rightSidebarTargetWidth: {
        if (!effectiveRightOpen)
            return 0;
        switch (Config.options.sidebar.position) {
        case "default":
            return dashboardWidth;
        case "inverted":
            return policiesDetached ? 0 : policiesWidth;
        case "right":
            if (policiesPanelOpen)
                return policiesDetached ? 0 : policiesWidth;
            if (dashboardPanelOpen)
                return dashboardWidth;
            return 0;
        default:
            return dashboardWidth;
        }
    }

    property real animatedLeftSidebarWidth: 0
    property real animatedRightSidebarWidth: 0

    // Exposed for TopLayerPanel/WrappedFrameVisuals to gate `layer.enabled`
    // so the FBO layer is only active during the open/close animation, NOT
    // while the sidebar is statically open. Keeping the layer enabled while
    // open caused massive CPU usage (380%+) because every minor visual
    // change (timer ticks, notification syncs, infinite pulse animations)
    // forced a full FBO re-render of the entire sidebar subtree.
    readonly property bool leftSidebarAnimating: leftSidebarAnimation.running
    readonly property bool rightSidebarAnimating: rightSidebarAnimation.running

    NumberAnimation {
        id: leftSidebarAnimation
        target: root
        property: "animatedLeftSidebarWidth"
        easing.type: Easing.OutQuart
    }

    NumberAnimation {
        id: rightSidebarAnimation
        target: root
        property: "animatedRightSidebarWidth"
        easing.type: Easing.OutQuart
    }

    onLeftSidebarTargetWidthChanged: {
        leftSidebarAnimation.stop();
        if ((Config.options?.appearance?.animationMultiplier ?? 1.0) <= 0.25) {
            animatedLeftSidebarWidth = leftSidebarTargetWidth;
            return;
        }
        if (leftSidebarTargetWidth > 0) {
            leftSidebarAnimation.duration = Appearance.animation.elementMoveEnter.duration;
            leftSidebarAnimation.easing.type = Easing.OutQuart;
            leftSidebarAnimation.to = leftSidebarTargetWidth;
            leftSidebarAnimation.start();
        } else {
            leftSidebarAnimation.duration = Appearance.animation.elementMoveEnter.duration;
            leftSidebarAnimation.easing.type = Easing.OutQuart;
            leftSidebarAnimation.to = leftSidebarTargetWidth;
            leftSidebarAnimation.start();
        }
    }

    onRightSidebarTargetWidthChanged: {
        rightSidebarAnimation.stop();
        if ((Config.options?.appearance?.animationMultiplier ?? 1.0) <= 0.25) {
            animatedRightSidebarWidth = rightSidebarTargetWidth;
            return;
        }
        if (rightSidebarTargetWidth > 0) {
            rightSidebarAnimation.duration = Appearance.animation.elementMoveEnter.duration;
            rightSidebarAnimation.easing.type = Easing.OutQuart;
            rightSidebarAnimation.to = rightSidebarTargetWidth;
            rightSidebarAnimation.start();
        } else {
            rightSidebarAnimation.duration = Appearance.animation.elementMoveEnter.duration;
            rightSidebarAnimation.easing.type = Easing.OutQuart;
            rightSidebarAnimation.to = rightSidebarTargetWidth;
            rightSidebarAnimation.start();
        }
    }

    Component.onCompleted: {
        animatedLeftSidebarWidth = leftSidebarTargetWidth;
        animatedRightSidebarWidth = rightSidebarTargetWidth;
        root.enforceSidebarStyle();
        // Instantiate sidebars immediately on startup on the primary/focused screen to keep them warm
        Qt.callLater(() => {
            root.activeLeftSidebarMonitor = Hyprland.focusedMonitor?.name ?? Quickshell.primaryScreen?.name ?? "";
            root.activeRightSidebarMonitor = Hyprland.focusedMonitor?.name ?? Quickshell.primaryScreen?.name ?? "";
        });
    }

    property bool dashboardPanelOpen: false // formerly sidebarRightOpen
    property bool policiesPanelOpen: false  // formerly sidebarLeftOpen

    /**
     * Held above zero while something the left sidebar itself started — a file
     * dialog, the region snip — is holding focus. Losing focus normally closes
     * the sidebar, which meant its own buttons dismissed it and the work came
     * back to nothing. Raise it before opening such a thing, lower it when
     * that thing is gone.
     */
    property int policiesHoldOpen: 0

    property bool requestVolumeDialog: false

    readonly property bool effectiveLeftOpen: {
        switch (Config.options.sidebar.position) {
        case "default":
            return policiesPanelOpen;
        case "inverted":
            return dashboardPanelOpen;
        case "left":
            return dashboardPanelOpen || policiesPanelOpen;
        case "right":
            return false;
        default:
            return policiesPanelOpen;
        }
    }
    readonly property bool effectiveRightOpen: {
        switch (Config.options.sidebar.position) {
        case "default":
            return dashboardPanelOpen;
        case "inverted":
            return policiesPanelOpen;
        case "left":
            return false;
        case "right":
            return dashboardPanelOpen || policiesPanelOpen;
        default:
            return dashboardPanelOpen;
        }
    }

    function toggleLeftSidebar(monitorName) {
        if (root.policiesPanelOpen) {
            root.policiesPanelOpen = false;
        } else {
            root.activeLeftSidebarMonitor = monitorName || Hyprland.focusedMonitor?.name || "";
            root.policiesPanelOpen = true;
        }
    }

    function toggleRightSidebar(monitorName) {
        if (root.dashboardPanelOpen) {
            root.dashboardPanelOpen = false;
        } else {
            root.activeRightSidebarMonitor = monitorName || Hyprland.focusedMonitor?.name || "";
            root.dashboardPanelOpen = true;
        }
    }

    function openLeftSidebar(monitorName) {
        root.activeLeftSidebarMonitor = monitorName || Hyprland.focusedMonitor?.name || "";
        root.policiesPanelOpen = true;
    }

    function openRightSidebar(monitorName) {
        root.activeRightSidebarMonitor = monitorName || Hyprland.focusedMonitor?.name || "";
        root.dashboardPanelOpen = true;
    }

    function toggleSearch(monitorName) {
        if (root.overviewOpen) {
            root.overviewOpen = false;
        } else {
            root.captureSearchTargetWindow();
            root.activeSearchMonitor = monitorName || Hyprland.focusedMonitor?.name || "";
            root.overviewOpen = true;
        }
    }

    function openSearch(monitorName) {
        // A panel can be requested from a row after Search is already open.
        // Keep the opening snapshot in that case: the active surface is now
        // the Overview, not the application the action must operate on.
        if (!root.overviewOpen)
            root.captureSearchTargetWindow();
        root.activeSearchMonitor = monitorName || Hyprland.focusedMonitor?.name || "";
        root.overviewOpen = true;
    }

    function openSearchPanel(panelId, monitorName, initialQuery) {
        const requested = String(panelId ?? "").trim();
        if (requested.length === 0)
            return;
        if (requested === "fileBrowser")
            root.clearFileBrowserSearchResults();
        root.searchPendingPanel = requested;
        root.searchPendingPanelQuery = String(initialQuery ?? "");
        root.searchPanelNavigationRequest++;
        root.openSearch(monitorName);
    }

    function clearFileBrowserSearchResults() {
        root.fileBrowserSearchResults = [];
        root.fileBrowserSearchQuery = "";
        root.fileBrowserSearchRequest++;
    }

    function openFileBrowserResults(paths, query, monitorName) {
        const results = Array.from(paths ?? []).filter(path => String(path ?? "").length > 0);
        if (results.length === 0)
            return;
        root.fileBrowserSearchResults = results;
        root.fileBrowserSearchQuery = String(query ?? "");
        root.fileBrowserSearchRequest++;
        root.searchPendingPanel = "fileBrowser";
        root.searchPendingPanelQuery = "";
        root.searchPanelNavigationRequest++;
        root.openSearch(monitorName);
    }

    function consumePendingSearchPanel() {
        const pending = root.searchPendingPanel;
        root.searchPendingPanel = "";
        return pending;
    }

    function consumePendingSearchPanelQuery() {
        const pending = root.searchPendingPanelQuery;
        root.searchPendingPanelQuery = "";
        return pending;
    }

    IpcHandler {
        target: "searchPanel"

        function open(panelId: string): void {
            root.openSearchPanel(panelId);
        }
    }

    Timer {
        id: resetSearchOnlyModeTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.overviewOpen) {
                root.searchOnlyMode = false;
            }
        }
    }

    onOverviewOpenChanged: {
        if (root.overviewOpen) {
            // Some shortcuts and IPC entry points assign overviewOpen
            // directly. Capture here as the common synchronous boundary,
            // before the layer-shell surface can become the active toplevel.
            root.captureSearchTargetWindow();
            resetSearchOnlyModeTimer.stop();
            if (root.activeSearchMonitor === "") {
                root.activeSearchMonitor = Hyprland.focusedMonitor?.name ?? "";
            }
        } else {
            root.activeSearchMonitor = "";
            resetSearchOnlyModeTimer.start();
        }
    }

    onAnimatedLeftSidebarWidthChanged: {}

    onAnimatedRightSidebarWidthChanged: {}

    onPoliciesPanelOpenChanged: {
        // Edit Mode refuses the sidebars for its whole length: its chrome is
        // Overlay and the sidebars are Top, so an open one is painted over by
        // the toolbar that shares its edge - and neither sidebar is something
        // the mode edits. Refused here, on the flag, because the corners, the
        // bar and the IPC handlers all open them through it.
        if (policiesPanelOpen && root.editMode) {
            policiesPanelOpen = false;
            return;
        }
        if (policiesPanelOpen) {
            if (root.activeLeftSidebarMonitor === "") {
                root.activeLeftSidebarMonitor = Hyprland.focusedMonitor?.name ?? "";
            }
            if (Config.options.sidebar.position == "right" || Config.options.sidebar.position == "left") {
                root.dashboardPanelOpen = false;
            }
        }
    }

    onDashboardPanelOpenChanged: {
        // Before the notification sweep, not after: a refused open must not
        // count as the user having read what it would have shown them.
        if (dashboardPanelOpen && root.editMode) {
            dashboardPanelOpen = false;
            return;
        }
        if (dashboardPanelOpen) {
            if (root.activeRightSidebarMonitor === "") {
                root.activeRightSidebarMonitor = Hyprland.focusedMonitor?.name ?? "";
            }
            Notifications.timeoutAll();
            Notifications.markAllRead();
            if (Config.options.sidebar.position == "right" || Config.options.sidebar.position == "left") {
                root.policiesPanelOpen = false;
            }
        }
    }

    // Sidebar Right (Dashboard) IPC
    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            root.toggleRightSidebar();
        }

        function close(): void {
            root.dashboardPanelOpen = false;
        }

        function open(): void {
            root.openRightSidebar();
        }
    }

    // Sidebar Left (Policies) IPC
    IpcHandler {
        target: "sidebarLeft"
        function toggle(): void {
            root.toggleLeftSidebar();
        }
        function close(): void {
            root.sidebarLeftOpen = false;
        }
        function open(): void {
            root.openLeftSidebar();
        }
    }

    // Sidebar Right Global Shortcuts
    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"
        onPressed: {
            root.toggleRightSidebar();
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"
        onPressed: {
            root.openRightSidebar();
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"
        onPressed: {
            root.sidebarRightOpen = false;
        }
    }

    // Sidebar Left Global Shortcuts
    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"
        onPressed: {
            root.toggleLeftSidebar();
        }
    }
    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"
        onPressed: {
            root.openLeftSidebar();
        }
    }
    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"
        onPressed: {
            root.sidebarLeftOpen = false;
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"
        onPressed: {
            root.superDown = true;
        }
        onReleased: {
            root.superDown = false;
        }
    }

    // Edit Mode entry points. `qs -c ii ipc call editMode toggle|open|close`;
    // the shortcut is what the Super+Shift+E bind reaches.
    IpcHandler {
        target: "editMode"

        function toggle(): void {
            root.toggleEditMode();
        }

        function open(): void {
            root.openEditMode();
        }

        function close(): void {
            root.closeEditMode();
        }
    }

    GlobalShortcut {
        name: "editModeToggle"
        description: "Toggles the desktop layout editor"
        onPressed: root.toggleEditMode()
    }
}
