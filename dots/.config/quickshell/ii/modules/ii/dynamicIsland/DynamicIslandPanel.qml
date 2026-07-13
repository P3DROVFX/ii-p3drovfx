import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overview
import qs.modules.common.functions
import qs.modules.ii.bar
import qs.modules.ii.bar.shared

Scope {
    id: root

    // Monitor for fullscreen windows
    readonly property HyprlandMonitor hMonitor: Hyprland.monitorFor(win.screen)
    readonly property int activeWsId: (hMonitor && hMonitor.activeWorkspace) ? hMonitor.activeWorkspace.id : -1
    readonly property bool fullscreenActive: {
        if (!win.screen)
            return false;
        const monitorData = HyprlandData.monitors.find(m => m.name === win.screen.name);
        const specialWsName = monitorData?.specialWorkspace?.name;
        const workspaces = Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === win.screen.name);
        return workspaces.some(workspace => {
            const isWorkspaceActive = workspace.active || (specialWsName && specialWsName !== "" && (workspace.name === specialWsName || workspace.name === "special:" + specialWsName || (specialWsName === "special:special" && workspace.name === "special") || (specialWsName === "special" && workspace.name === "special:special")));
            return isWorkspaceActive && workspace.toplevels.values.some(toplevel => toplevel.wayland && toplevel.wayland.fullscreen);
        });
    }

    // State bindings
    readonly property bool searchActive: GlobalStates.overviewOpen && GlobalStates.searchConnectActive && (win.screen ? win.screen.name === GlobalStates.activeSearchMonitor : false)
    readonly property bool osdActive: GlobalStates.osdVolumeOpen
    readonly property bool notificationActive: Notifications.popupList.length > 0
    readonly property bool recordingActive: (Persistent.states.screenRecord && Persistent.states.screenRecord.active) || false
    readonly property bool pomodoroActive: TimerService.pomodoroRunning
    readonly property bool stopwatchActive: TimerService.stopwatchRunning
    readonly property bool mediaActive: {
        if (MprisController.activePlayer === null)
            return false;
        const t = (MprisController.activeTrack && MprisController.activeTrack.title) ? MprisController.activeTrack.title : "";
        const a = (MprisController.activeTrack && MprisController.activeTrack.artist) ? MprisController.activeTrack.artist : "";
        // Block browser noise: no title + unknown artist combo
        if ((t === "" || t === "No title") && (a === "" || a === "Unknown Artist"))
            return false;
        return true;
    }

    readonly property bool isOverviewVisible: root.searchActive && LauncherSearch.query === "" && !GlobalStates.searchOnlyMode && !Config.options.search.alwaysListApps && (Config && Config.options && Config.options.overview && Config.options.overview.enable !== undefined ? Config.options.overview.enable : true)
    readonly property bool isScrollingLayout: Persistent.states.hyprland.layout === "scrolling"
    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3 && !(Config.options.bar.cornerStyle === 3 && !Config.options.bar.vertical) && (!Config.options.bar.onlyShowOnSingleMonitor || hasBarOnThisMonitor)
    readonly property bool hasBarOnThisMonitor: GlobalStates.isScreenAllowedForBar(win.screen)
    readonly property bool hasTopBar: GlobalStates.barOpen && !Config.options.bar.vertical && !Config.options.bar.bottom && hasBarOnThisMonitor

    BarThemes {
        id: barThemes
    }
    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    property var searchWidgetRef: null
    property var workspaceWidgetRef: null
    property var btDevice: null
    property string prevLayout: ""
    property bool keyboardNotifActive: false
    property bool workspaceNotifActive: false
    property int prevWsId: activeWsId
    property bool clipboardNotifActive: false
    property string lastClipboardItem: ""
    property bool isDragOverNotch: false
    property bool rightClickHidden: false
    // Reference to the currently loaded FloatingNotchLocalSend widget
    // (or null).  Used to push the drop-side choice into the widget so
    // the expanded picker opens on the right service tab.
    property var _localSendWidget: null
    property int _lsServiceChoice: 0
    property var _lsQueueFiles: []
    readonly property var _cliphistRef: Cliphist

    Component.onCompleted: {
        root.prevLayout = HyprlandXkb.currentLayoutName;
    }

    // Bluetooth temporary notification status
    property bool btNotifActive: false
    property string btDeviceName: ""
    property string btAction: "connected"

    Connections {
        target: BluetoothStatus
        function onDeviceConnected(device) {
            root.btDevice = device;
            root.btDeviceName = device.name || device.alias || "Device";
            root.btAction = "connected";
            root.btNotifActive = true;
            GlobalStates.floatingNotchBtDevice = device;
            GlobalStates.floatingNotchBtAction = "connected";
            GlobalStates.floatingNotchBtNotifActive = true;
            btTimer.restart();
        }
        function onDeviceDisconnected(device) {
            root.btDevice = device;
            root.btDeviceName = device.name || device.alias || "Device";
            root.btAction = "disconnected";
            root.btNotifActive = true;
            GlobalStates.floatingNotchBtDevice = device;
            GlobalStates.floatingNotchBtAction = "disconnected";
            GlobalStates.floatingNotchBtNotifActive = true;
            btTimer.restart();
        }
    }

    property Timer btTimer: Timer {
        id: btTimer
        interval: 3000
        onTriggered: {
            if (root.isHoverExpanded) {
                btTimer.interval = 1000;
                btTimer.restart();
            } else {
                root.btNotifActive = false;
                GlobalStates.floatingNotchBtDevice = null;
                GlobalStates.floatingNotchBtAction = "connected";
                GlobalStates.floatingNotchBtNotifActive = false;
                btTimer.interval = 3000;
            }
        }
    }

    // Wifi temporary notification status
    property bool wifiNotifActive: false
    property string wifiSsid: ""

    Connections {
        target: Network
        function onWifiStatusChanged() {
            if (Network.wifiStatus === "connected" && Network.networkName !== "") {
                root.wifiSsid = Network.networkName;
                root.wifiNotifActive = true;
                wifiTimer.restart();
            }
        }
    }

    property Timer wifiTimer: Timer {
        id: wifiTimer
        interval: 3000
        onTriggered: {
            if (root.isHoverExpanded) {
                wifiTimer.interval = 1000;
                wifiTimer.restart();
            } else {
                root.wifiNotifActive = false;
                wifiTimer.interval = 3000;
            }
        }
    }

    property Timer clipboardNotifTimer: Timer {
        id: clipboardNotifTimer
        interval: 2500
        onTriggered: root.clipboardNotifActive = false
    }

    property bool isStartup: true
    Timer {
        running: true
        interval: 2000
        onTriggered: root.isStartup = false
    }

    // Clear LocalSend service choice when files are removed
    Connections {
        target: LocalSend
        function onDroppedFilesChanged() {
            if (LocalSend.droppedFiles.length === 0 && root._lsServiceChoice === 1) {
                root._lsServiceChoice = 0;
                root._lsQueueFiles = [];
            }
        }
    }

    Connections {
        target: root._cliphistRef
        function onClipboardUpdated() {
            let topItem = root._cliphistRef.entries[0] || "";
            let cleanTop = StringUtils.cleanCliphistEntry(topItem);

            if (root.isStartup) {
                if (cleanTop !== "") {
                    root.lastClipboardItem = cleanTop;
                }
                return;
            }

            if (cleanTop !== "" && cleanTop !== root.lastClipboardItem) {
                root.lastClipboardItem = cleanTop;
                console.log("[DynamicIsland] Cliphist clipboard updated! Top item: ", cleanTop);
                if (Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableClipboard) {
                    root.clipboardNotifActive = true;
                    clipboardNotifTimer.restart();
                }
            }
        }
    }

    // Keyboard layout transition notification status
    Connections {
        target: HyprlandXkb
        function onCurrentLayoutNameChanged() {
            if (Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableKeyboard && root.prevLayout !== "" && root.prevLayout !== HyprlandXkb.currentLayoutName && HyprlandXkb.layoutCodes.length > 1) {
                root.keyboardNotifActive = true;
                keyboardTimer.restart();
            }
            root.prevLayout = HyprlandXkb.currentLayoutName;
        }
    }

    property Timer keyboardTimer: Timer {
        id: keyboardTimer
        interval: 1500
        onTriggered: root.keyboardNotifActive = false
    }

    // Workspaces transition notification status
    onActiveWsIdChanged: {
        if (prevWsId !== -1 && activeWsId !== -1 && prevWsId !== activeWsId && Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableWorkspaces) {
            root.workspaceNotifActive = true;
            workspaceTimer.restart();
        }
        prevWsId = activeWsId;
    }

    property Timer workspaceTimer: Timer {
        id: workspaceTimer
        interval: 2000
        onTriggered: root.workspaceNotifActive = false
    }

    function getWidgetDetails(type) {
        if (type === "search") {
            return {
                type: "search",
                source: "",
                contractedH: 54,
                expandedH: searchWidgetRef ? Math.min(win.screen.height * 0.7, searchWidgetRef.implicitHeight) : 54,
                contractedW: searchWidgetRef ? searchWidgetRef.implicitWidth : 420,
                expandedW: searchWidgetRef ? searchWidgetRef.implicitWidth : 420
            };
        }
        if (type === "osd") {
            return {
                type: "osd",
                source: "",
                contractedH: 72,
                expandedH: 72,
                contractedW: 380,
                expandedW: 380
            };
        }
        if (type === "notification") {
            return {
                type: "notification",
                source: "widgets/FloatingNotchNotification.qml",
                contractedH: Config.options.bar.floatingNotch.heightNotification,
                expandedH: 140,
                contractedW: 380,
                expandedW: 460
            };
        }
        if (type === "localsend") {
            return {
                type: "localsend",
                source: "widgets/FloatingNotchLocalSend.qml",
                contractedH: root.isDragOverNotch ? 140 : Config.options.bar.floatingNotch.heightLocalSend,
                expandedH: 160,
                contractedW: root.isDragOverNotch ? 360 : ((LocalSend.droppedFiles.length > 0 || root._lsServiceChoice === 2) ? 220 : 180),
                expandedW: 340
            };
        }
        if (type === "clipboard") {
            return {
                type: "clipboard",
                source: "widgets/FloatingNotchClipboard.qml",
                contractedH: Config.options.bar.floatingNotch.heightClipboard,
                expandedH: 140,
                contractedW: 180,
                expandedW: 360
            };
        }
        if (type === "workspaces") {
            return {
                type: "workspaces",
                source: "widgets/FloatingNotchWorkspaces.qml",
                contractedH: Config.options.bar.floatingNotch.heightWorkspaces,
                expandedH: 140,
                contractedW: workspaceWidgetRef ? workspaceWidgetRef.implicitWidth : (Config.options.bar.workspaces.shown * 26 + 20),
                expandedW: workspaceWidgetRef ? workspaceWidgetRef.implicitWidth : ((Config.options.bar.workspaces.shown * 26 * 1.15) + 20)
            };
        }
        if (type === "keyboard") {
            return {
                type: "keyboard",
                source: "widgets/FloatingNotchKeyboard.qml",
                contractedH: Config.options.bar.floatingNotch.heightKeyboard,
                expandedH: 140,
                contractedW: 44 + 16 + (70 * HyprlandXkb.layoutCodes.length) + (4 * (HyprlandXkb.layoutCodes.length - 1)) + 24,
                expandedW: 44 + 16 + (70 * HyprlandXkb.layoutCodes.length) + (4 * (HyprlandXkb.layoutCodes.length - 1)) + 24
            };
        }
        if (type === "wifi") {
            return {
                type: "wifi",
                source: "widgets/FloatingNotchWifi.qml",
                contractedH: Config.options.bar.floatingNotch.heightWifi,
                expandedH: 140,
                contractedW: 250,
                expandedW: 250
            };
        }
        if (type === "bluetooth") {
            return {
                type: "bluetooth",
                source: "widgets/FloatingNotchBluetooth.qml",
                contractedH: Config.options.bar.floatingNotch.heightBluetooth,
                expandedH: 160,
                contractedW: 320,
                expandedW: 360
            };
        }
        if (type === "pomodoro" || type === "stopwatch") {
            return {
                type: type,
                source: "widgets/FloatingNotchTimer.qml",
                contractedH: Config.options.bar.floatingNotch.heightTimer,
                expandedH: 140,
                contractedW: 170,
                expandedW: 240
            };
        }
        if (type === "recording") {
            return {
                type: "recording",
                source: "widgets/FloatingNotchRecording.qml",
                contractedH: Config.options.bar.floatingNotch.heightRecording,
                expandedH: 140,
                contractedW: 125,
                expandedW: 240
            };
        }
        if (type === "media") {
            return {
                type: "media",
                source: "widgets/FloatingNotchMedia.qml",
                contractedH: Config.options.bar.floatingNotch.heightMedia,
                expandedH: 140,
                contractedW: 320,
                expandedW: 420
            };
        }
        if (type === "checklist") {
            return {
                type: "checklist",
                source: "widgets/FloatingNotchChecklist.qml",
                contractedH: Config.options.bar.floatingNotch.heightChecklist ?? 36,
                expandedH: 140,
                contractedW: 100,
                expandedW: 300
            };
        }
        if (type === "calendar") {
            return {
                type: "calendar",
                source: "widgets/FloatingNotchCalendar.qml",
                contractedH: Config.options.bar.floatingNotch.heightCalendar ?? 48,
                expandedH: 140,
                contractedW: 260,
                expandedW: 340
            };
        }
        if (type === "audio") {
            return {
                type: "audio",
                source: "widgets/FloatingNotchAudio.qml",
                contractedH: Config.options.bar.floatingNotch.heightAudio ?? 36,
                expandedH: 140,
                contractedW: 100,
                expandedW: 340
            };
        }
        if (type === "progress") {
            return {
                type: "progress",
                source: "widgets/FloatingNotchProgress.qml",
                contractedH: Config.options.bar.floatingNotch.heightProgress ?? 56,
                expandedH: ProgressService.jobs.length > 2 ? 160 : 140,
                contractedW: 220,
                expandedW: 360
            };
        }
        return {
            type: "home",
            source: "",
            contractedH: Config.options.bar.floatingNotch.heightHome,
            expandedH: Config.options.bar.floatingNotch.heightHome,
            contractedW: 180,
            expandedW: 180
        };
    }

    // ── Search-persistent widgets ──────────────────────────────────────────
    // These widgets remain visible at the bottom of the DI when search is open.
    // Add/remove types here to control persistence.
    readonly property var searchPersistentWidgets: {
        if (!root.searchActive)
            return [];
        let list = [];
        if (notificationActive && !Config.options.bar.floatingNotch.disableNotification)
            list.push(getWidgetDetails("notification"));
        if (GlobalStates.floatingNotchBtNotifActive && !Config.options.bar.floatingNotch.disableBluetooth)
            list.push(getWidgetDetails("bluetooth"));
        if (recordingActive && !Config.options.bar.floatingNotch.disableRecording)
            list.push(getWidgetDetails("recording"));
        if ((pomodoroActive || stopwatchActive) && !Config.options.bar.floatingNotch.disableTimer)
            list.push(getWidgetDetails(pomodoroActive ? "pomodoro" : "stopwatch"));
        return list;
    }

    // Height of the persistent strip (contracted height + vertical padding), 0 when empty
    readonly property real searchPersistentStripHeight: searchPersistentWidgets.length > 0 ? 52 : 0

    readonly property var activeWidgetsList: {
        if (searchActive)
            return [getWidgetDetails("search")];
        if (osdActive && !Config.options.bar.floatingNotch.disableOsd)
            return [getWidgetDetails("osd")];

        let list = [];
        let showChecklist = !Config.options.bar.floatingNotch.disableChecklist && (Config.options.bar.floatingNotch.checklistAlwaysVisible || (root.isHoverExpanded && Config.options.bar.floatingNotch.checklistOnlyExpanded));
        let showCalendar = !Config.options.bar.floatingNotch.disableCalendar;
        let showAudio = !Config.options.bar.floatingNotch.disableAudio && root.isHoverExpanded;

        if (notificationActive && !Config.options.bar.floatingNotch.disableNotification)
            list.push(getWidgetDetails("notification"));
        if ((LocalSend.currentTransfer !== null || LocalSend.droppedFiles.length > 0 || LocalSend.sending || root.isDragOverNotch || root._lsServiceChoice !== 0) && !Config.options.bar.floatingNotch.disableLocalSend)
            list.push(getWidgetDetails("localsend"));
        if (ProgressService.hasActiveJobs && !Config.options.bar.floatingNotch.disableProgress)
            list.push(getWidgetDetails("progress"));
        if (clipboardNotifActive && !Config.options.bar.floatingNotch.disableClipboard)
            list.push(getWidgetDetails("clipboard"));
        if (workspaceNotifActive && !Config.options.bar.floatingNotch.disableWorkspaces)
            list.push(getWidgetDetails("workspaces"));
        if (keyboardNotifActive && !Config.options.bar.floatingNotch.disableKeyboard)
            list.push(getWidgetDetails("keyboard"));
        if (wifiNotifActive && !Config.options.bar.floatingNotch.disableWifi)
            list.push(getWidgetDetails("wifi"));
        if (GlobalStates.floatingNotchBtNotifActive && !Config.options.bar.floatingNotch.disableBluetooth)
            list.push(getWidgetDetails("bluetooth"));
        if ((pomodoroActive || stopwatchActive) && !Config.options.bar.floatingNotch.disableTimer) {
            list.push(getWidgetDetails(pomodoroActive ? "pomodoro" : "stopwatch"));
        }
        if (recordingActive && !Config.options.bar.floatingNotch.disableRecording)
            list.push(getWidgetDetails("recording"));
        if (mediaActive && !Config.options.bar.floatingNotch.disableMedia)
            list.push(getWidgetDetails("media"));

        if (showChecklist) {
            if (root.isHoverExpanded) {
                // In expanded mode, put checklist at the very beginning (left side)
                list.unshift(getWidgetDetails("checklist"));
            } else {
                // In contracted mode, put checklist at the end (lowest priority)
                list.push(getWidgetDetails("checklist"));
            }
        }

        if (showAudio) {
            list.push(getWidgetDetails("audio"));
        }

        if (showCalendar && root.isHoverExpanded) {
            list.push(getWidgetDetails("calendar"));
        }

        if (list.length === 0) {
            if (showCalendar) {
                return [getWidgetDetails("calendar")];
            }
            return [getWidgetDetails("home")];
        }
        return list;
    }

    readonly property string mode: {
        if (searchActive)
            return "search";
        if (osdActive && !Config.options.bar.floatingNotch.disableOsd)
            return "osd";

        let activeList = root.activeWidgetsList;
        if (activeList.length > 0 && activeList[0].type !== "home") {
            return activeList[0].type;
        }
        return "home";
    }

    readonly property bool hasExpandedVersion: {
        if (mode === "search" || mode === "osd" || mode === "home")
            return false;
        return true;
    }

    // Hover state for general expanding on hover
    property bool hoverActive: hoverHandler.hovered
    // Expanded when hovering OR when localsend/KDE ready state is active
    property bool isHoverExpanded: false

    onHoverActiveChanged: {
        if (hoverActive) {
            hoverCollapseTimer.stop();
            if (root._lsServiceChoice !== 0) {
                lsReadyCollapseTimer.restart();
            }
            isHoverExpanded = true;
        } else {
            if (root._lsServiceChoice !== 0) {
                lsReadyCollapseTimer.restart();
            } else {
                hoverCollapseTimer.restart();
            }
        }
    }

    // Auto-expand when a service is chosen; auto-collapse after delay
    on_LsServiceChoiceChanged: {
        if (root._lsServiceChoice !== 0) {
            lsReadyCollapseTimer.restart();
            isHoverExpanded = true;
        } else {
            lsReadyCollapseTimer.stop();
            if (!hoverActive) {
                hoverCollapseTimer.restart();
            }
        }
    }

    property Timer hoverCollapseTimer: Timer {
        id: hoverCollapseTimer
        interval: 1500
        onTriggered: isHoverExpanded = false
    }

    property Timer lsReadyCollapseTimer: Timer {
        id: lsReadyCollapseTimer
        interval: 3000
        running: false
        onTriggered: {
            const lsWidget = root._localSendWidget;
            if (!hoverActive && !(lsWidget && lsWidget.kdeSent)) {
                isHoverExpanded = false;
            }
        }
    }

    // Trigger state for autohide top screen hover sensor
    property bool screenTopHovered: topSensorHandler.hovered
    property bool showOnTopHover: false

    onScreenTopHoveredChanged: {
        if (screenTopHovered) {
            topHoverCollapseTimer.stop();
            showOnTopHover = true;
            rightClickHidden = false;
        } else {
            topHoverCollapseTimer.restart();
        }
    }

    property Timer topHoverCollapseTimer: Timer {
        id: topHoverCollapseTimer
        interval: 2000
        onTriggered: showOnTopHover = false
    }

    // Check if the notch is currently showing the fallback home or contracted calendar display
    readonly property bool isIdle: mode === "home"

    // Determine if the island should be physically hidden (slid up out of bounds)
    readonly property bool idleHidden: {
        if (searchActive)
            return false;
        if (fullscreenActive)
            return true;
        if (rightClickHidden)
            return true;

        // Never hide while a file drag is hovering the drop area — the user
        // needs to see the drop target to complete the transfer. Without this
        // the container stays off-screen when dragging from a file manager
        // (HoverHandler doesn't fire during DnD, so showOnTopHover stays false).
        if (root.isDragOverNotch)
            return false;

        // Hide if we are idle and the user is not hovering either the top trigger or the container itself
        if (isIdle) {
            return !showOnTopHover && !hoverActive;
        }

        // Hide if auto-hide is enabled AND user is not hovering either the top trigger or the container itself
        if (Config.options.bar.floatingNotch.autoHide) {
            return !showOnTopHover && !hoverActive;
        }

        return false;
    }

    // Layout configuration
    // Layout configuration
    readonly property real targetW: {
        if (mode === "search")
            return searchWidgetRef ? searchWidgetRef.implicitWidth : 420;
        if (mode === "osd")
            return 380;
        if (mode === "home")
            return 180;

        if (isHoverExpanded) {
            let list = activeWidgetsList;
            if (list.length > 1) {
                let sum = 0;
                for (let i = 0; i < list.length; i++) {
                    sum += list[i].expandedW + 24;
                }
                return sum;
            } else if (list.length === 1) {
                return list[0].expandedW;
            }
        } else {
            return activeWidgetsList[0].contractedW;
        }
        return 180;
    }

    // Focus grabber for Search Mode keyboard input
    HyprlandFocusGrab {
        id: keyboardGrab
        windows: [win]
        active: root.searchActive
        onCleared: () => {
            if (!active)
                GlobalStates.overviewOpen = false;
        }
    }

    readonly property real targetH: {
        if (mode === "search")
            return searchWidgetRef ? Math.min(win.screen.height * 0.7, searchWidgetRef.implicitHeight) + root.searchPersistentStripHeight : 54 + root.searchPersistentStripHeight;
        if (mode === "osd")
            return 72;
        if (mode === "home")
            return Config.options.bar.floatingNotch.heightHome;

        if (isHoverExpanded) {
            let list = activeWidgetsList;
            if (list.length > 0) {
                let maxH = 0;
                for (let i = 0; i < list.length; i++) {
                    maxH = Math.max(maxH, list[i].expandedH);
                }
                return maxH;
            }
            return 140;
        } else {
            let list = activeWidgetsList;
            if (list.length > 0) {
                let maxH = 0;
                for (let i = 0; i < list.length; i++) {
                    maxH = Math.max(maxH, list[i].contractedH);
                }
                return maxH;
            }
            return 88;
        }
    }

    PanelWindow {
        id: win
        screen: {
            if (Config.options.bar.floatingNotch.onlyShowOnSingleMonitor) {
                var targetName = Config.options.bar.floatingNotch.singleMonitorName;
                var foundTarget = Quickshell.screens.find(s => s.name === targetName);
                if (foundTarget)
                    return foundTarget;
            }
            var name = (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "");
            var found = Quickshell.screens.find(s => s.name === name);
            if (found)
                return found;
            return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
        }
        visible: !GlobalStates.screenLocked
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:floatingNotch"
        WlrLayershell.keyboardFocus: root.searchActive ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            left: true
            right: true
        }

        implicitHeight: (searchActive || isOverviewVisible) ? (win.screen ? win.screen.height : 1080) : 240

        // Dynamic click/hover mask to prevent blocking the screen
        mask: Region {
            item: root.idleHidden ? topSensor : (root.isOverviewVisible ? fullWindowItem : maskTarget)
        }

        // Helper item that fills the entire window content to serve as a valid mask item for overlay
        Item {
            id: fullWindowItem
            anchors.fill: parent
        }

        // Invisible item serving as window mask, aligning with the container shape
        Item {
            id: maskTarget
            anchors.horizontalCenter: container.horizontalCenter
            anchors.top: container.top
            width: root.isDragOverNotch ? Math.max(container.width, root.targetW + 60) : container.width
            height: container.height
        }

        // Auto-position container below any top frame thickness if needed
        Item {
            id: container
            anchors.horizontalCenter: parent.horizontalCenter
            width: targetW + (2 * notchBackground.topRadius)
            height: targetH

            DropArea {
                id: notchDropArea
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.isDragOverNotch ? Math.max(parent.width, root.targetW + 60) : parent.width
                keys: ["text/uri-list"]
                enabled: Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableLocalSend && LocalSend.available
                onEntered: drag => {
                    drag.accept(Qt.CopyAction);
                }
                onPositionChanged: drag => {
                    const lsWidget = root._localSendWidget;
                    if (!lsWidget)
                        return;
                    const dropW = root.isDragOverNotch ? Math.max(container.width, root.targetW + 60) : container.width;
                    const kdeReady = !Config.options.bar.floatingNotch.disableKdeConnectInLocalSend && typeof KdeConnectService !== "undefined" && KdeConnectService.available && KdeConnectService.activeReachable && KdeConnectService.activeDevice;
                    if (kdeReady) {
                        lsWidget.rightHover = drag.x >= dropW / 2;
                        lsWidget.leftHover = drag.x < dropW / 2;
                    } else {
                        lsWidget.leftHover = true;
                        lsWidget.rightHover = false;
                    }
                }
                onExited: {
                    const lsWidget = root._localSendWidget;
                    if (lsWidget) {
                        lsWidget.leftHover = false;
                        lsWidget.rightHover = false;
                    }
                }
                onDropped: drop => {
                    if (!drop.hasUrls)
                        return;
                    const lsWidget = root._localSendWidget;
                    const dropW = root.isDragOverNotch ? Math.max(container.width, root.targetW + 60) : container.width;
                    const useKde = !Config.options.bar.floatingNotch.disableKdeConnectInLocalSend && typeof KdeConnectService !== "undefined" && KdeConnectService.available && KdeConnectService.activeReachable && KdeConnectService.activeDevice && drop.x >= dropW / 2;
                    const cleanPaths = drop.urls.map(function (u) {
                        return u.toString().replace(/^file:\/\//, "");
                    });
                    // Set panel-level mirror first (drives widget visibility + auto-expand)
                    root._lsServiceChoice = useKde ? 2 : 1;
                    root._lsQueueFiles = cleanPaths;
                    if (lsWidget) {
                        lsWidget.serviceChoice = useKde ? 2 : 1;
                        lsWidget.queueFiles = cleanPaths;
                        lsWidget.leftHover = false;
                        lsWidget.rightHover = false;
                    }
                    if (!useKde) {
                        for (let i = 0; i < drop.urls.length; i++) {
                            LocalSend.addDroppedFile(drop.urls[i]);
                        }
                        if (LocalSend.available)
                            LocalSend.startScanning();
                    }
                    drop.accept(Qt.CopyAction);
                }
            }

            Binding {
                target: root
                property: "isDragOverNotch"
                value: notchDropArea.containsDrag
            }

            Behavior on width {
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.9
                }
            }

            Behavior on height {
                NumberAnimation {
                    duration: 500
                    easing.type: Easing.OutBack
                    easing.overshoot: 0.5
                }
            }

            // Slide vertically out of screen when idleHidden is true
            y: {
                if (idleHidden)
                    return -targetH - 10;
                if (root.hasTopBar)
                    return Appearance.sizes.barHeight;
                if (root.usingWrappedFrame)
                    return Config.options.appearance.wrappedFrameThickness;
                return 0;
            }

            // Bounce with reduced overshoot when appearing to prevent top gap
            // Disappearing uses full overshoot (goes off-screen, invisible)
            Behavior on y {
                NumberAnimation {
                    duration: 330
                    easing.type: Easing.OutBack
                    easing.overshoot: root.idleHidden ? 0.9 : 0.3
                }
            }

            // --- Drop Shadow ---
            // --- Main Notch shape ---
            Notch {
                id: notchBackground
                anchors.fill: parent
                bodyWidth: parent.width
                bodyHeight: parent.height
                topRadius: ((root.isHoverExpanded && root.hasExpandedVersion) || root.mode === "search") ? 32 : 24 // Increased concave corners
                bottomRadius: root.mode === "search" ? Appearance.rounding.windowRounding : ((root.isHoverExpanded && root.hasExpandedVersion) ? 28 : 20)
                fillColor: Config.options.bar.expressiveColors ? root.activeTheme.barBackground : Appearance.colors.colLayer0
                disableBehaviors: true

                layer.enabled: Config.options.bar.floatingNotch.dropShadow && !idleHidden
                layer.samples: 8
                layer.smooth: true
                antialiasing: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.rgba(0, 0, 0, root.isHoverExpanded ? 0.65 : 0.45)
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    shadowBlur: root.isHoverExpanded ? 2.4 : 1.8
                }
            }

            // Hover Handler for expanding the Notch
            HoverHandler {
                id: hoverHandler
            }

            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: {
                    root.rightClickHidden = true;
                }
            }

            // Main Content Layout
            Item {
                id: contentClip
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width - (2 * notchBackground.topRadius)
                clip: true

                // Search Widget Loader
                Loader {
                    id: searchWidgetLoader
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.searchPersistentStripHeight
                    width: root.mode === "search" && searchWidgetLoader.item ? searchWidgetLoader.item.implicitWidth : parent.width
                    readonly property bool shown: root.mode === "search"
                    active: Config.ready
                    visible: opacity > 0.01
                    opacity: shown ? 1.0 : 0.0
                    scale: shown ? 1.0 : 0.95
                    Behavior on width {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutBack
                            easing.overshoot: 0.5
                        }
                    }
                    Behavior on opacity {
                        enabled: !root.searchActive
                        NumberAnimation {
                            duration: 280
                            easing.type: Easing.InOutQuad
                        }
                    }
                    Behavior on scale {
                        enabled: !root.searchActive
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.OutBack
                            easing.overshoot: 0.5
                        }
                    }

                Connections {
                    target: root
                    function onModeChanged() {
                        if (root.mode !== "search" && searchWidgetLoader.item) {
                            searchWidgetLoader.item.cancelSearch();
                        }
                    }
                }

                onVisibleChanged: {
                    if (visible && item) {
                        if (GlobalStates.activeSearchQuery) {
                            item.setSearchingText(GlobalStates.activeSearchQuery);
                            GlobalStates.activeSearchQuery = "";
                        } else {
                            item.cancelSearch();
                        }
                        Qt.callLater(() => item.focusSearchInput());
                    }
                }

                    sourceComponent: Component {
                        SearchWidget {
                            id: searchWidget
                            inNotchMode: true
                            Component.onCompleted: {
                                root.searchWidgetRef = searchWidget;
                            }
                            Component.onDestruction: {
                                if (root.searchWidgetRef === searchWidget)
                                    root.searchWidgetRef = null;
                            }
                        }
                    }
                }

                // ── Search Persistent Widgets Strip ──────────────────────────
                // Widgets that remain visible at the bottom of the DI when search
                // is open. Controlled by root.searchPersistentWidgets.
                Item {
                    id: searchPersistentStrip
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: root.searchPersistentStripHeight
                    visible: root.searchActive && root.searchPersistentWidgets.length > 0
                    opacity: visible ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.InOutQuad
                        }
                    }

                    // Separator line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        height: 1
                        opacity: 0.15
                        color: Appearance.colors.colOnLayer0
                    }

                    // Contracted widgets row
                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Repeater {
                            model: root.searchPersistentWidgets
                            delegate: Item {
                                required property var modelData
                                width: modelData.contractedW
                                height: modelData.contractedH

                                Loader {
                                    id: persistentWidgetLoader
                                    anchors.centerIn: parent
                                    width: modelData.contractedW
                                    height: modelData.contractedH
                                    active: root.searchActive
                                    source: modelData.source

                                    // Contracted mode bindings
                                    Binding {
                                        target: persistentWidgetLoader.item && persistentWidgetLoader.item.hasOwnProperty("isExpanded") ? persistentWidgetLoader.item : null
                                        property: "isExpanded"
                                        value: false
                                    }
                                    Binding {
                                        target: persistentWidgetLoader.item && persistentWidgetLoader.item.hasOwnProperty("panelWidgetsCount") ? persistentWidgetLoader.item : null
                                        property: "panelWidgetsCount"
                                        value: root.searchPersistentWidgets.length
                                    }

                                    // Entry animation
                                    opacity: 0.0
                                    scale: 0.9
                                    Component.onCompleted: {
                                        opacity = 1.0;
                                        scale = 1.0;
                                    }
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 250
                                            easing.type: Easing.OutQuad
                                        }
                                    }
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 350
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 0.5
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Loader {
                    id: osdWidgetLoader
                    anchors.fill: parent
                    readonly property bool shown: root.mode === "osd"
                    active: shown || opacity > 0.01
                    visible: opacity > 0.01
                    opacity: shown ? 1.0 : 0.0
                    scale: shown ? 1.0 : 0.95
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutQuad
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.OutBack
                            easing.overshoot: 0.5
                        }
                    }

                    sourceComponent: Component {
                        Item {
                            anchors.fill: parent
                            Loader {
                                id: osdIndicatorLoader
                                anchors.fill: parent
                                source: {
                                    const item = [
                                        {
                                            id: "volume",
                                            sourceUrl: "indicators/VolumeIndicator.qml"
                                        },
                                        {
                                            id: "brightness",
                                            sourceUrl: "indicators/BrightnessIndicator.qml"
                                        },
                                        {
                                            id: "playerVolume",
                                            sourceUrl: "indicators/PlayerVolumeIndicator.qml"
                                        },
                                        {
                                            id: "gamma",
                                            sourceUrl: "indicators/GammaIndicator.qml"
                                        },
                                        {
                                            id: "keyboardBrightness",
                                            sourceUrl: "indicators/KeyboardBrightnessIndicator.qml"
                                        }
                                    ].find(i => i.id === GlobalStates.osdCurrentIndicator);
                                    if (!item)
                                        return "";
                                    return Quickshell.shellPath("modules/ii/topLayer/osd/" + item.sourceUrl);
                                }
                            }
                        }
                    }
                }

                // Dynamic side-by-side loaders for active widgets/notifications
                Row {
                    id: activeWidgetsRow
                    anchors.centerIn: parent
                    spacing: 0
                    visible: root.mode !== "search" && root.mode !== "osd" && root.mode !== "home"

                    Repeater {
                        model: root.mode !== "search" && root.mode !== "osd" && root.mode !== "home" ? (root.isHoverExpanded ? root.activeWidgetsList : [root.activeWidgetsList[0]]) : []
                        delegate: Item {
                            width: root.isHoverExpanded ? (root.activeWidgetsList.length > 1 ? modelData.expandedW + 24 : modelData.expandedW) : root.targetW
                            height: root.targetH

                            Rectangle {
                                id: widgetBg
                                anchors.fill: parent
                                anchors.margins: root.isHoverExpanded && root.activeWidgetsList.length > 1 ? 2 : 2
                                radius: Appearance.rounding.windowRounding
                                // Suppress background when widget provides its own (LocalSend drag/expanded
                                // uses per-service tinted columns).  Stacking the panel's card on top of those
                                // causes the "rectangles duplos" issue.
                                readonly property bool widgetOwnsBackground: (modelData.type === "localsend" && (root.isDragOverNotch || (root.isHoverExpanded && modelData.hasExpandedVersion !== false))) || modelData.type === "notification"
                                color: {
                                    if (widgetOwnsBackground)
                                        return "transparent";
                                    if (root.isHoverExpanded && root.activeWidgetsList.length > 1)
                                        return Appearance.colors.colSurfaceContainerLow;
                                    return "transparent";
                                }
                                visible: color !== "transparent"

                                Loader {
                                    id: widgetLoader
                                    anchors.centerIn: parent
                                    width: root.isHoverExpanded ? modelData.expandedW : parent.width
                                    height: root.isHoverExpanded ? modelData.expandedH : parent.height
                                    active: true
                                    source: modelData.source !== "" ? modelData.source : ""

                                    // Enter/Exit scale/fade transition
                                    opacity: 0.0
                                    scale: 0.95
                                    Component.onCompleted: {
                                        opacity = 1.0;
                                        scale = 1.0;
                                    }

                                    // Track the loaded LocalSend widget so the
                                    // DropArea can push serviceChoice/queueFiles.
                                    onLoaded: {
                                        if (modelData.type === "localsend") {
                                            root._localSendWidget = item;
                                            if (root._lsServiceChoice !== 0) {
                                                item.serviceChoice = root._lsServiceChoice;
                                                item.queueFiles = root._lsQueueFiles;
                                            }
                                        }
                                    }
                                    onItemChanged: {
                                        if (modelData.type === "localsend") {
                                            if (!item) {
                                                root._localSendWidget = null;
                                            } else if (root._lsServiceChoice !== 0) {
                                                item.serviceChoice = root._lsServiceChoice;
                                                item.queueFiles = root._lsQueueFiles;
                                            }
                                        }
                                    }
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 250
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                    Behavior on scale {
                                        NumberAnimation {
                                            duration: 450
                                            easing.type: Easing.OutBack
                                            easing.overshoot: 0.6
                                        }
                                    }

                                    // Bind isExpanded property
                                    Binding {
                                        target: widgetLoader.item && widgetLoader.item.hasOwnProperty("isExpanded") ? widgetLoader.item : null
                                        property: "isExpanded"
                                        value: root.isHoverExpanded
                                    }

                                    // Bind isDragOverNotch (panel-level state)
                                    Binding {
                                        target: widgetLoader.item && widgetLoader.item.hasOwnProperty("isDragOverNotch") ? widgetLoader.item : null
                                        property: "isDragOverNotch"
                                        value: root.isDragOverNotch
                                    }

                                    // Bind activeWidgetsList (panel-level state)
                                    Binding {
                                        target: widgetLoader.item && widgetLoader.item.hasOwnProperty("panelWidgetsCount") ? widgetLoader.item : null
                                        property: "panelWidgetsCount"
                                        value: root.activeWidgetsList.length
                                    }

                                    Connections {
                                        target: widgetLoader.item && modelData.type === "localsend" ? widgetLoader.item : null
                                        enabled: target !== null
                                        function onServiceChoiceChanged() {
                                            if (target && target.serviceChoice === 0) {
                                                root._lsServiceChoice = 0;
                                                root._lsQueueFiles = [];
                                                root._localSendWidget = target;
                                                target.queueFiles = [];
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Idle home display
                Item {
                    id: homeWidget
                    anchors.fill: parent
                    readonly property bool shown: root.mode === "home"
                    visible: opacity > 0.01
                    opacity: shown ? 1.0 : 0.0
                    scale: shown ? 1.0 : 0.95
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.InOutQuad
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: 350
                            easing.type: Easing.OutBack
                            easing.overshoot: 0.5
                        }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "water_drop"
                            iconSize: 14
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            text: "ii"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: true
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }
        }

        // AutoHide top edge sensor (small transparent sensor at the very top of the screen)
        Rectangle {
            id: topSensor
            width: 160
            height: 4
            color: "transparent"
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            visible: (Config.options.bar.floatingNotch.autoHide || root.rightClickHidden) && root.idleHidden

            HoverHandler {
                id: topSensorHandler
            }
        }

        // Top-edge drop zone: reveals the hidden container during file drag-and-drop.
        // HoverHandler in topSensor doesn't fire during DnD, so this DropArea bridges the gap.
        DropArea {
            id: topDropZone
            width: 320
            height: 40
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            keys: ["text/uri-list"]
            enabled: root.idleHidden
                && Config.options.bar.floatingNotch.enable
                && !Config.options.bar.floatingNotch.disableLocalSend
                && LocalSend.available
            onEntered: drag => {
                drag.accept(Qt.CopyAction);
                topHoverCollapseTimer.stop();
                root.showOnTopHover = true;
                root.rightClickHidden = false;
            }
            onExited: {
                topHoverCollapseTimer.restart();
            }
            onDropped: drop => {
                if (!drop.hasUrls)
                    return;
                const kdeReady = !Config.options.bar.floatingNotch.disableKdeConnectInLocalSend
                    && typeof KdeConnectService !== "undefined"
                    && KdeConnectService.available
                    && KdeConnectService.activeReachable
                    && KdeConnectService.activeDevice;
                const useKde = kdeReady && drop.x >= width / 2;
                const cleanPaths = drop.urls.map(function (u) {
                    return u.toString().replace(/^file:\/\//, "");
                });
                root._lsServiceChoice = useKde ? 2 : 1;
                root._lsQueueFiles = cleanPaths;
                const lsWidget = root._localSendWidget;
                if (lsWidget) {
                    lsWidget.serviceChoice = useKde ? 2 : 1;
                    lsWidget.queueFiles = cleanPaths;
                    lsWidget.leftHover = false;
                    lsWidget.rightHover = false;
                }
                if (!useKde) {
                    for (let i = 0; i < drop.urls.length; i++) {
                        LocalSend.addDroppedFile(drop.urls[i]);
                    }
                    if (LocalSend.available)
                        LocalSend.startScanning();
                }
                drop.accept(Qt.CopyAction);
                topHoverCollapseTimer.restart();
            }
        }

        Loader { // Classic overview
            id: overviewLoader
            anchors.top: container.bottom
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            active: root.searchActive && !root.isScrollingLayout
            visible: opacity > 0.01

            opacity: root.isOverviewVisible ? 1.0 : 0.0
            transform: Translate {
                y: root.isOverviewVisible ? 0 : 30
                Behavior on y {
                    NumberAnimation {
                        duration: root.isOverviewVisible ? 450 : 280
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.isOverviewVisible ? 450 : 60
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

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
            active: root.searchActive && root.isScrollingLayout
            visible: opacity > 0.01

            opacity: root.isOverviewVisible ? 1.0 : 0.0
            transform: Translate {
                y: root.isOverviewVisible ? 0 : 30
                Behavior on y {
                    NumberAnimation {
                        duration: root.isOverviewVisible ? 450 : 280
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: root.isOverviewVisible ? 450 : 120
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                }
            }

            sourceComponent: ScrollingOverviewWidget {
                anchors.fill: parent
                panelWindow: win
                monitorIndex: Quickshell.screens.indexOf(win.screen)
            }
        }
    }
}
