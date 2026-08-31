pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
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
    property real lockBarTransitionProgress: screenLocked ? 1.0 : 0.0
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
    // Whether a hosted panel (or the AI chat) currently owns the Search
    // surface. The Super shortcut lives outside any PanelWindow, so it cannot
    // ask a SearchWidget directly, and closing the whole Overview from inside
    // a panel loses a level of navigation the user expects Super to walk back.
    property bool searchPanelActive: false
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

    function toggleSearchOnly(monitorName) {
        const requestedMonitor = monitorName || "";
        const sameMonitor = requestedMonitor === ""
            || root.activeSearchMonitor === ""
            || root.activeSearchMonitor === requestedMonitor;

        if (root.overviewOpen && root.searchOnlyMode && sameMonitor) {
            root.overviewOpen = false;
            return;
        }

        root.searchOnlyMode = true;
        root.openSearch(monitorName);
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
            // A panel cannot outlive the surface that hosted it, and a flag
            // left set would make the next Super press try to leave a panel
            // that is not there instead of opening the launcher.
            root.searchPanelActive = false;
            resetSearchOnlyModeTimer.start();
        }
    }

    onAnimatedLeftSidebarWidthChanged: {}

    onAnimatedRightSidebarWidthChanged: {}

    onPoliciesPanelOpenChanged: {
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
}
