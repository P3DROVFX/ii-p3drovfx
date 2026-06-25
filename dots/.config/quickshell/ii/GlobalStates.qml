pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property alias sidebarLeftOpen: root.policiesPanelOpen // Until all sidebars naming is fixed
    property alias sidebarRightOpen: root.dashboardPanelOpen // Until all sidebars naming is fixed

    property bool barOpen: true
    property bool cheatsheetOpen: false
    property bool crosshairOpen: false
    property bool mediaControlsOpen: false
    property bool mediaControlsPinned: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool searchOnlyMode: false

    // scaleValue: animated 1.0 → ~0.85 during overview open (zoomOutStyle 0 only)
    // originX/Y: scale transform center in screen coordinates
    property real overviewZoomScale: 1.0
    property real overviewZoomOriginX: 0.5
    property real overviewZoomOriginY: 0.5
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property bool filePickerOpen: false
    property bool videoEditorPopupOpen: false
    property bool videoEditorOpen: false
    property string videoEditorPath: ""
    property bool settingsOpen: false
    property int settingsPendingPage: -1
    property string settingsPendingSubPage: ""
    property string settingsPendingPageName: ""
    property string activeLeftSidebarMonitor: ""
    property string activeRightSidebarMonitor: ""
    property string activeSearchMonitor: ""
    property string activeSearchQuery: ""
    property bool searchDropActive: false
    property real searchDropExclusionX: 0
    property real searchDropExclusionY: 0
    property real searchDropExclusionWidth: 0
    property real searchDropExclusionHeight: 0
    property real searchDropTopRadius: 0
    property real searchDropBottomRadius: 0
    property bool policiesExtended: false
    property bool policiesPinned: false
    property bool policiesDetached: false

    // Bluetooth connection popup
    property bool bluetoothConnectionPopupOpen: false
    property var bluetoothConnectionPopupDevice: null

    // LocalSend transfer popup
    property bool localSendPopupOpen: false
    property var localSendPopupTransfer: null

    // Media Popup placement (transient, non-persistent)
    property rect mediaPopupRect: Qt.rect(0, 0, 0, 0)
    property bool mediaWidgetHovered: false
    property Timer mediaWidgetHoverTimer: Timer {
        interval: 100
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
            if (Config.options && Config.options.bar && Config.options.bar.tooltips && Config.options.bar.tooltips.enableColorPickerPopup) {
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

    function launchVideoEditor(path) {
        root.videoEditorPath = path;
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

    IpcHandler {
        target: "settings"

        function toggle(): void {
            root.toggleSettings();
        }

        function open(): void {
            root.openSettings();
        }
    }

    GlobalShortcut {
        name: "settingsToggle"
        description: "Toggles the settings window"
        onPressed: root.toggleSettings()
    }

    readonly property bool connectModeActive: {
        if (!Config.ready) return false;
        const style = Config.options.sidebar.sidebarStyle || "default";
        if (style !== "connect") return false;

        // Connect style is disabled if the bar background style is Transparent
        if (Config.options.bar.barBackgroundStyle === 0) return false;

        // Works in all rounding modes except Edge (4)
        if (Config.options.appearance.fakeScreenRounding === 4) return false;

        // Only works with cornerStyle 0 (Hug) or 2 (Rect)
        const cs = Config.options.bar.cornerStyle;
        return cs === 0 || cs === 2;
    }

    readonly property bool searchConnectActive: {
        if (!connectModeActive) return false;
        if (Config.options.search.connectStyle !== "connect") return false;

        // Float mode (cornerStyle 1) excluded — bar disconnected from edges
        if (Config.options.bar.cornerStyle === 1) return false;

        // All other corner styles (Hug, Rect, Dynamic Island) supported
        return true;
    }

    function enforceSidebarStyle() {
        if (!Config.ready) return;
        if (Config.options.bar.barBackgroundStyle === 0 && Config.options.sidebar.sidebarStyle === "connect") {
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

    readonly property real policiesWidth: {
        if (policiesExtended)
            return Appearance.sizes.sidebarWidthExtended;

        const p = Config.options.policies;
        let activeCount = 0;
        if (p.ai !== 0) activeCount++;
        if (p.translator !== 0) activeCount++;
        if (p.player !== 0) activeCount++;
        if (p.wallpapers !== 0) activeCount++;
        if (p.weeb !== 0 && p.weeb !== 2) activeCount++;
        if (p.phone !== 0) activeCount++;

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
        if (leftSidebarTargetWidth > 0) {
            leftSidebarAnimation.duration = Appearance.animation.elementMoveEnter.duration;
            leftSidebarAnimation.easing.type = Easing.OutQuart;
        } else {
            leftSidebarAnimation.duration = Appearance.animation.elementMoveEnter.duration;
            leftSidebarAnimation.easing.type = Easing.OutQuart;
        }
        leftSidebarAnimation.to = leftSidebarTargetWidth;
        leftSidebarAnimation.start();
    }

    onRightSidebarTargetWidthChanged: {
        rightSidebarAnimation.stop();
        if (rightSidebarTargetWidth > 0) {
            rightSidebarAnimation.duration = Appearance.animation.elementMoveEnter.duration;
            rightSidebarAnimation.easing.type = Easing.OutQuart;
        } else {
            rightSidebarAnimation.duration = Appearance.animation.elementMoveEnter.duration;
            rightSidebarAnimation.easing.type = Easing.OutQuart;
        }
        rightSidebarAnimation.to = rightSidebarTargetWidth;
        rightSidebarAnimation.start();
    }

    Component.onCompleted: {
        animatedLeftSidebarWidth = leftSidebarTargetWidth;
        animatedRightSidebarWidth = rightSidebarTargetWidth;
        root.enforceSidebarStyle();
    }

    property bool dashboardPanelOpen: false // formerly sidebarRightOpen
    property bool policiesPanelOpen: false  // formerly sidebarLeftOpen

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
            root.activeSearchMonitor = monitorName || Hyprland.focusedMonitor?.name || "";
            root.overviewOpen = true;
        }
    }

    function openSearch(monitorName) {
        root.activeSearchMonitor = monitorName || Hyprland.focusedMonitor?.name || "";
        root.overviewOpen = true;
    }

    onOverviewOpenChanged: {
        if (root.overviewOpen && root.searchConnectActive && root.activeSearchMonitor === "") {
            root.activeSearchMonitor = Hyprland.focusedMonitor?.name ?? ""
        }
        if (!root.overviewOpen && root.searchConnectActive) {
            root.activeSearchMonitor = ""
            // Overview.qml's PanelWindow (which resets searchOnlyMode) is inactive in
            // connect mode — reset it here so the next SUPER press opens the full overview.
            root.searchOnlyMode = false
        }
    }

    onAnimatedLeftSidebarWidthChanged: {
        if (animatedLeftSidebarWidth === 0 && !policiesPanelOpen) {
            root.activeLeftSidebarMonitor = "";
        }
    }

    onAnimatedRightSidebarWidthChanged: {
        if (animatedRightSidebarWidth === 0 && !dashboardPanelOpen) {
            root.activeRightSidebarMonitor = "";
        }
    }

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
