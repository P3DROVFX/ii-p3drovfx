import QtQuick
import Quickshell
import qs
import qs.services

import qs.modules.common
import qs.modules.common.panels.shellSwitcher
import qs.modules.ii.background
import qs.modules.ii.background.desktopMenu
import qs.modules.ii.bar
import qs.modules.ii.bluetoothConnectionPopup
import qs.modules.ii.bluetoothPairing
import qs.modules.ii.cheatsheet
import qs.modules.ii.notes
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
import qs.modules.ii.screenshotOverlay
import qs.modules.ii.dynamicIsland
import qs.modules.ii.dynamicIsland.core
import qs.modules.ii.touchGestures
import qs.modules.ii.editMode
import qs.modules.tablet.appDrawer
import qs.modules.ii.phoneControls

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

    PanelLoader {
        extraCondition: !BarPlacement.vertical && barExtraCondition && !GlobalStates.connectModeActive
        component: Bar {}
    }
    PanelLoader {
        extraCondition: Config.options.background.enable
        component: Background {}
    }
    PanelLoader {
        // The desktop layout editor's chrome; nothing to edit without the background.
        extraCondition: Config.options.background.enable
        component: EditModeChrome {}
    }
    PanelLoader {
        // The desktop's right-click menu; asked for by the background's surfaces.
        extraCondition: Config.options.background.enable
        component: DesktopMenu {}
    }
    PanelLoader {
        component: Cheatsheet {}
    }
    PanelLoader {
        // The Scope stays loaded so the keybind and the IPC target exist; the window
        // itself is built by the loader inside, when somebody asks for it.
        extraCondition: Config.options.notes.enable
        component: NotesApp {}
    }
    PanelLoader {
        extraCondition: Config.options.appStats.overlayEnabled
        component: Usage {}
    }
    PanelLoader {
        extraCondition: Config.options.modes.overlayEnabled
        component: ModesOverlay {}
    }
    // The mode start/end banner; the dynamic island draws it when a notch is on.
    PanelLoader {
        extraCondition: (Config.options?.modes?.enable ?? true) && !IslandPolicy.ownsModeFlash
        component: ModeFlashPopup {}
    }
    PanelLoader {
        extraCondition: Config.options.dock.enable
        component: Dock {}
    }
    PanelLoader {
        component: Lock {}
    }
    PanelLoader {
        component: MediaControls {}
    }
    PanelLoader {
        // The Scope must stay loaded so the onDeviceConnected trigger inside
        // BluetoothConnectionPopup.qml is alive; the inner LazyLoader gates the
        // actual PanelWindow on GlobalStates.bluetoothConnectionPopupOpen.
        // (df1e26966 gated this PanelLoader on the same flag, creating a
        // chicken-and-egg that prevented the popup from ever appearing.)
        extraCondition: !IslandPolicy.ownsBluetoothPopup
        component: BluetoothConnectionPopup {}
    }
    PanelLoader {
        extraCondition: !IslandPolicy.ownsKeyboardPopup
        component: KeyboardLayoutTransitionPopup {}
    }
    PanelLoader {
        extraCondition: !IslandPolicy.ownsLocalSendPopup && GlobalStates.localSendPopupOpen
        component: LocalSendPopup {}
    }
    PanelLoader {
        extraCondition: !IslandPolicy.ownsNotifications
        component: NotificationPopup {}
    }
    PanelLoader {
        extraCondition: !(Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material"))
        component: OnScreenDisplay {}
    }
    PanelLoader {
        extraCondition: (Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material"))
        component: MinimalistOsd {}
    }
    PanelLoader {
        // Kept loaded rather than gated on the service: the windows are empty
        // and invisible until a recording or the quick toggle asks for them.
        extraCondition: Config.ready
        component: KeypressDisplay {}
    }
    PanelLoader {
        component: OnScreenKeyboard {}
    }
    PanelLoader {
        component: OledSaver {}
    }
    PanelLoader {
        component: Overlay {}
    }
    PanelLoader {
        component: Overview {}
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
    PanelLoader {
        component: Polkit {}
    }
    // Kept loaded rather than gated: the Scope decides on its own whether BlueZ
    // is asking anything, and nothing is built until it is.
    PanelLoader {
        component: BluetoothPairing {}
    }
    PanelLoader {
        component: RegionSelector {}
    }
    PanelLoader {
        // Four corner windows and their Shape layers are only needed for fake
        // screen rounding or the corner-open hit zones. When both features
        // are off, unload the whole scope instead of keeping four hidden
        // PanelWindows alive.
        extraCondition: Config.options.appearance.fakeScreenRounding !== 0
            || Config.options.sidebar.cornerOpen.enable
        component: ScreenCorners {}
    }
    PanelLoader {
        component: ScreenTranslator {}
    }
    PanelLoader {
        component: ColorPickerPopup {}
    }
    PanelLoader {
        component: SessionScreen {}
    }
    // Every family loads the chooser: a family that did not offer it would be one the
    // user could switch into and never find the way out of.
    PanelLoader {
        component: ShellSwitcher {}
    }
    PanelLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        component: SidebarPolicies {}
    }
    PanelLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        component: SidebarDashboard {}
    }
    PanelLoader {
        extraCondition: BarPlacement.vertical && barExtraCondition && !GlobalStates.connectModeActive
        component: VerticalBar {}
    }
    PanelLoader {
        component: WallpaperSelector {}
    }
    PanelLoader {
        component: WrappedFrame {}
    }
    PanelLoader {
        extraCondition: GlobalStates.videoEditorPopupOpen
        component: VideoEditorPopup {}
    }
    PanelLoader {
        extraCondition: GlobalStates.videoEditorOpen
        component: VideoEditor {}
    }
    PanelLoader {
        component: ScratchpadOverlay {}
    }
    PanelLoader {
        extraCondition: AlarmService.ringingAlarmIndex !== -1 && Config.options.time.alarms.useFullscreenPopup
        component: AlarmRingingPopup {}
    }
    PanelLoader {
        extraCondition: GlobalStates.screenshotOverlayOpen
        component: ScreenshotOverlay {}
    }
    PanelLoader {
        extraCondition: Config.options.tiling.enable
        component: TilingOverlay {}
    }
    PanelLoader {
        extraCondition: Config.options.tiling.enable
        component: LayoutHint {}
    }
    PanelLoader {
        extraCondition: Config.options.tiling.enable && Config.options.tiling.overlay.stackIndicator
        component: TilingStackBadges {}
    }
    PanelLoader {
        extraCondition: GlobalStates.connectModeActive
        component: TopLayer {}
    }
    PanelLoader {
        extraCondition: IslandPolicy.enabled
        component: DynamicIsland {}
    }
    PanelLoader {
        extraCondition: Config.ready && Boolean(Config.options && Config.options.interactions && Config.options.interactions.touchGestures && Config.options.interactions.touchGestures.enable)
        component: TouchGestures {}
    }
    PanelLoader {
        extraCondition: PhoneScrcpyService.mirrorRunning || PhoneScrcpyService.mirrorLaunching || KdeConnectService.scrcpyRunning
        component: PhoneFloatingWindowControls {}
    }
}
