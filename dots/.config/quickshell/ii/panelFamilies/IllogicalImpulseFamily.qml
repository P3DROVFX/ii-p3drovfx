import QtQuick
import Quickshell
import qs
import qs.services

// Panels load by URL (PanelUrlLoader), so most of these imports name no type here.
// Keep them: they are how the QmlScanner reaches each panel's module.
import qs.modules.common
import qs.modules.common.panels.shellSwitcher
import qs.modules.common.panels.windowSwitcher
import qs.modules.ii.background
import qs.modules.ii.background.desktopMenu
import qs.modules.ii.bar
import qs.modules.ii.bluetoothConnectionPopup
import qs.modules.ii.bluetoothPairing
import qs.modules.ii.cheatsheet
import qs.modules.ii.notes
import qs.modules.ii.clock
import qs.modules.ii.dock
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenDisplay.minimalist
import qs.modules.common.onScreenKeyboard
import qs.modules.ii.oledSaver
import qs.modules.ii.overview
import qs.modules.ii.polkit
import qs.modules.ii.regionSelector
import qs.modules.ii.screenCorners
import qs.modules.ii.screenTranslator
import qs.modules.ii.sessionScreen
import qs.modules.ii.sidebarPolicies
import qs.modules.ii.sidebarDashboard
import qs.modules.ii.overlay
import qs.modules.ii.verticalBar
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.wrappedFrame
import qs.modules.ii.colorPickerPopup
import qs.modules.ii.videoEditor
import qs.modules.ii.localSendPopup
import qs.modules.ii.scratchpadOverlay
import qs.modules.ii.keyboardLayoutTransitionPopup
import qs.modules.ii.keypressDisplay
import qs.modules.ii.topLayer
import qs.modules.ii.tilingAssistant
import qs.modules.ii.usage
import qs.modules.ii.modes
import qs.modules.ii.modeFlashPopup
import qs.modules.ii.alarmRingingPopup
import qs.modules.ii.screenTimeOverlay
import qs.modules.ii.screenshotOverlay
import qs.modules.ii.dynamicIsland
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.touchGestures
import qs.modules.ii.editMode
import qs.modules.tablet.appDrawer
import qs.modules.ii.phoneControls
import qs.modules.ii.recordingToolbar

Scope {
    property bool barExtraCondition: true
    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3
    readonly property bool barBot: BarPlacement.bottom
    readonly property bool barVert: BarPlacement.vertical

    Component.onCompleted: Qt.callLater(() => updateBarExtraCondition())
    onUsingWrappedFrameChanged: updateBarExtraCondition()
    onBarBotChanged: updateBarExtraCondition()
    onBarVertChanged: updateBarExtraCondition()

    function updateBarExtraCondition() {
        if (!usingWrappedFrame)
            return;
        barExtraCondition = false;
        Qt.callLater(() => barExtraCondition = true);
    }

    PanelUrlLoader {
        extraCondition: !BarPlacement.vertical && barExtraCondition && !GlobalStates.connectModeActive
        panelUrl: Qt.resolvedUrl("../modules/ii/bar/Bar.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.background.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/background/Background.qml")
    }
    PanelUrlLoader {
        // The desktop layout editor's chrome; nothing to edit without the background.
        extraCondition: Config.options.background.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/editMode/EditModeChrome.qml")
    }
    PanelUrlLoader {
        // The desktop's right-click menu; asked for by the background's surfaces.
        extraCondition: Config.options.background.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/background/desktopMenu/DesktopMenu.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/cheatsheet/Cheatsheet.qml")
    }
    PanelUrlLoader {
        // The Scope stays loaded so the keybind and the IPC target exist; the window
        // itself is built by the loader inside, when somebody asks for it.
        extraCondition: Config.options.notes.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/notes/NotesApp.qml")
    }
    PanelUrlLoader {
        // Same shape as the notes app: the Scope holds the keybind and IPC target, the
        // window is built only while the clock app is open.
        extraCondition: Config.options.clockApp?.enable ?? true
        panelUrl: Qt.resolvedUrl("../modules/ii/clock/ClockApp.qml")
    }
    PanelUrlLoader {
        // Always loaded: its keybinds and IPC switch presets even with the app off; the
        // window inside is gated on the app setting and built only while it is open.
        panelUrl: Qt.resolvedUrl("../modules/ii/easyEffects/EasyEffectsApp.qml")
    }
    PanelUrlLoader {
        // Same shape as the clock app; `overlayEnabled` predates the window and now
        // loads the app.
        extraCondition: Config.options.appStats.overlayEnabled
        panelUrl: Qt.resolvedUrl("../modules/ii/usage/UsageApp.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.modes.overlayEnabled
        panelUrl: Qt.resolvedUrl("../modules/ii/modes/ModesApp.qml")
    }
    // The mode start/end banner; the dynamic island draws it when a notch is on.
    PanelUrlLoader {
        extraCondition: (Config.options?.modes?.enable ?? true) && !IslandPolicy.ownsModeFlash
        panelUrl: Qt.resolvedUrl("../modules/ii/modeFlashPopup/ModeFlashPopup.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.dock.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/dock/Dock.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/lock/Lock.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/mediaControls/MediaControls.qml")
    }
    PanelUrlLoader {
        // The Scope must stay loaded so the onDeviceConnected trigger inside
        // BluetoothConnectionPopup.qml is alive; the inner LazyLoader gates the
        // actual PanelWindow on GlobalStates.bluetoothConnectionPopupOpen.
        // (df1e26966 gated this PanelLoader on the same flag, creating a
        // chicken-and-egg that prevented the popup from ever appearing.)
        extraCondition: !IslandPolicy.ownsBluetoothPopup
        panelUrl: Qt.resolvedUrl("../modules/ii/bluetoothConnectionPopup/BluetoothConnectionPopup.qml")
    }
    PanelUrlLoader {
        extraCondition: !IslandPolicy.ownsKeyboardPopup
        panelUrl: Qt.resolvedUrl("../modules/ii/keyboardLayoutTransitionPopup/KeyboardLayoutTransitionPopup.qml")
    }
    PanelUrlLoader {
        extraCondition: !IslandPolicy.ownsLocalSendPopup && GlobalStates.localSendPopupOpen
        panelUrl: Qt.resolvedUrl("../modules/ii/localSendPopup/LocalSendPopup.qml")
    }
    PanelUrlLoader {
        extraCondition: !IslandPolicy.ownsNotifications
        panelUrl: Qt.resolvedUrl("../modules/ii/notificationPopup/NotificationPopup.qml")
    }
    PanelUrlLoader {
        extraCondition: !(Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material"))
        panelUrl: Qt.resolvedUrl("../modules/ii/onScreenDisplay/OnScreenDisplay.qml")
    }
    PanelUrlLoader {
        extraCondition: (Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material"))
        panelUrl: Qt.resolvedUrl("../modules/ii/onScreenDisplay/minimalist/MinimalistOsd.qml")
    }
    PanelUrlLoader {
        // Kept loaded rather than gated on the service: the windows are empty
        // and invisible until a recording or the quick toggle asks for them.
        extraCondition: Config.ready
        panelUrl: Qt.resolvedUrl("../modules/ii/keypressDisplay/KeypressDisplay.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/common/onScreenKeyboard/OnScreenKeyboard.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/oledSaver/OledSaver.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/overlay/Overlay.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/overview/Overview.qml")
    }
    // Optional primary surface for the ii family. This is the Tablet Family's
    // actual drawer, not a fork: only the tablet-native app/home actions are
    // disabled, while the shared Search panels are injected as usual.
    PanelLoader {
        extraCondition: Config.options.overview.useAppDrawer
        component: TabletAppDrawer {
            toolHostComponent: appDrawerToolHost
            showTabletSystemApps: false
            allowHomeScreenPlacement: false
            allowDragToLaunch: false
        }
    }
    Component {
        id: appDrawerToolHost
        SearchPanelHost {}
    }
    // GNOME-like window scale-out during overview. Keep the scope out of the
    // object graph when the feature is disabled; its startup hook otherwise
    // still creates a per-screen transition tree and runs cleanup commands.
    Loader {
        active: !GlobalStates.overviewUsesAppDrawer
            && (Config.options?.background?.zoomOutEnabled ?? false)
            && (Config.options?.background?.windowZoomOnOverview ?? false)
        sourceComponent: OverviewWindowTransition {}
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/polkit/Polkit.qml")
    }
    // Kept loaded rather than gated: the Scope decides on its own whether BlueZ
    // is asking anything, and nothing is built until it is.
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/bluetoothPairing/BluetoothPairing.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/regionSelector/RegionSelector.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/recordingToolbar/RecordingToolbar.qml")
    }
    PanelUrlLoader {
        // Four corner windows and their Shape layers are only needed for fake
        // screen rounding or the corner-open hit zones. When both features
        // are off, unload the whole scope instead of keeping four hidden
        // PanelWindows alive.
        extraCondition: Config.options.appearance.fakeScreenRounding !== 0
            || Config.options.sidebar.cornerOpen.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/screenCorners/ScreenCorners.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/screenTranslator/ScreenTranslator.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/colorPickerPopup/ColorPickerPopup.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/sessionScreen/SessionScreen.qml")
    }
    // Every family loads the chooser: a family that did not offer it would be one the
    // user could switch into and never find the way out of.
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/common/panels/shellSwitcher/ShellSwitcher.qml")
    }
    // Alt+Tab. Always loaded (not gated on its setting): it is what takes the switcher's
    // binds away again when the setting goes off. Drawn on the island when that owns it.
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/common/panels/windowSwitcher/WindowSwitcherPanel.qml")
    }
    // Its peek, which both faces share (island and panel alike).
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/common/panels/windowSwitcher/WindowSwitcherPeek.qml")
    }
    PanelUrlLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        panelUrl: Qt.resolvedUrl("../modules/ii/sidebarPolicies/SidebarPolicies.qml")
    }
    PanelUrlLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        panelUrl: Qt.resolvedUrl("../modules/ii/sidebarDashboard/SidebarDashboard.qml")
    }
    PanelUrlLoader {
        extraCondition: BarPlacement.vertical && barExtraCondition && !GlobalStates.connectModeActive
        panelUrl: Qt.resolvedUrl("../modules/ii/verticalBar/VerticalBar.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/wallpaperSelector/WallpaperSelector.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/wrappedFrame/WrappedFrame.qml")
    }
    PanelUrlLoader {
        extraCondition: GlobalStates.videoEditorPopupOpen
        panelUrl: Qt.resolvedUrl("../modules/ii/videoEditor/VideoEditorPopup.qml")
    }
    PanelUrlLoader {
        extraCondition: GlobalStates.videoEditorOpen
        panelUrl: Qt.resolvedUrl("../modules/ii/videoEditor/VideoEditor.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/scratchpadOverlay/ScratchpadOverlay.qml")
    }
    PanelUrlLoader {
        extraCondition: AlarmService.ringingAlarmIndex !== -1 && Config.options.time.alarms.useFullscreenPopup
        panelUrl: Qt.resolvedUrl("../modules/ii/alarmRingingPopup/AlarmRingingPopup.qml")
    }
    PanelUrlLoader {
        // A Medium or Strong reminder taking the screen; built only while one does.
        extraCondition: RemindersService.ringingId.length > 0 && !GlobalStates.islandOwnsReminder
        panelUrl: Qt.resolvedUrl("../modules/ii/reminderAlertPopup/ReminderAlertPopup.qml")
    }
    PanelUrlLoader {
        // The daily-limits block screen; the service names what it covers.
        extraCondition: (Config.options.screenTime?.enable ?? true) && ScreenTimeLimits.activeBlock !== null
        panelUrl: Qt.resolvedUrl("../modules/ii/screenTimeOverlay/ScreenTimeOverlay.qml")
    }
    PanelUrlLoader {
        extraCondition: GlobalStates.screenshotOverlayOpen
        panelUrl: Qt.resolvedUrl("../modules/ii/screenshotOverlay/ScreenshotOverlay.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.tiling.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/tilingAssistant/TilingOverlay.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.tiling.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/tilingAssistant/LayoutHint.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.tiling.enable && Config.options.tiling.overlay.stackIndicator
        panelUrl: Qt.resolvedUrl("../modules/ii/tilingAssistant/TilingStackBadges.qml")
    }
    PanelUrlLoader {
        extraCondition: GlobalStates.connectModeActive
        panelUrl: Qt.resolvedUrl("../modules/ii/topLayer/TopLayer.qml")
    }
    PanelUrlLoader {
        extraCondition: IslandPolicy.enabled
        panelUrl: Qt.resolvedUrl("../modules/ii/dynamicIsland/DynamicIsland.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.ready && Boolean(Config.options && Config.options.interactions && Config.options.interactions.touchGestures && Config.options.interactions.touchGestures.enable)
        panelUrl: Qt.resolvedUrl("../modules/ii/touchGestures/TouchGestures.qml")
    }
    PanelUrlLoader {
        extraCondition: PhoneScrcpyService.mirrorRunning || PhoneScrcpyService.mirrorLaunching || KdeConnectService.scrcpyRunning
        panelUrl: Qt.resolvedUrl("../modules/ii/phoneControls/PhoneFloatingWindowControls.qml")
    }
}
