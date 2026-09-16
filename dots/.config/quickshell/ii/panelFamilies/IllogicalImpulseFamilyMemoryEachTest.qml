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
import qs.modules.ii.touchGestures
import qs.modules.ii.editMode
import qs.modules.tablet.appDrawer

Scope {
    id: memScope
    readonly property string selectedItem: Quickshell.env("II_MEMORY_ITEM") || "none"
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
        extraCondition: memScope.selectedItem === "Bar"
        component: Bar {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "Background"
        component: Background {}
    }
    PanelLoader {
        // The desktop layout editor's chrome; nothing to edit without the background.
        extraCondition: memScope.selectedItem === "EditModeChrome"
        component: EditModeChrome {}
    }
    PanelLoader {
        // The desktop's right-click menu; asked for by the background's surfaces.
        extraCondition: memScope.selectedItem === "DesktopMenu"
        component: DesktopMenu {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "Cheatsheet"
        component: Cheatsheet {}
    }
    PanelLoader {
        // The Scope stays loaded so the keybind and the IPC target exist; the window
        // itself is built by the loader inside, when somebody asks for it.
        extraCondition: memScope.selectedItem === "NotesApp"
        component: NotesApp {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "Usage"
        component: Usage {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "ModesOverlay"
        component: ModesOverlay {}
    }
    // The mode start/end banner; the dynamic island draws it when a notch is on.
    PanelLoader {
        extraCondition: memScope.selectedItem === "ModeFlashPopup"
            && Config.ready && !Config.options.bar.floatingNotch.enable
            && !Config.options.bar.floatingNotch.centerInBar
        component: ModeFlashPopup {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "Dock"
        component: Dock {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "Lock"
        component: Lock {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "MediaControls"
        component: MediaControls {}
    }
    PanelLoader {
        // The Scope must stay loaded so the onDeviceConnected trigger inside
        // BluetoothConnectionPopup.qml is alive; the inner LazyLoader gates the
        // actual PanelWindow on GlobalStates.bluetoothConnectionPopupOpen.
        // (df1e26966 gated this PanelLoader on the same flag, creating a
        // chicken-and-egg that prevented the popup from ever appearing.)
        extraCondition: memScope.selectedItem === "BluetoothConnectionPopup"
        component: BluetoothConnectionPopup {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "KeyboardLayoutTransitionPopup"
        component: KeyboardLayoutTransitionPopup {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "LocalSendPopup"
        component: LocalSendPopup {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "NotificationPopup"
        component: NotificationPopup {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "OnScreenDisplay"
        component: OnScreenDisplay {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "MinimalistOsd"
        component: MinimalistOsd {}
    }
    PanelLoader {
        // Kept loaded rather than gated on the service: the windows are empty
        // and invisible until a recording or the quick toggle asks for them.
        extraCondition: memScope.selectedItem === "KeypressDisplay"
        component: KeypressDisplay {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "OnScreenKeyboard"
        component: OnScreenKeyboard {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "OledSaver"
        component: OledSaver {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "Overlay"
        component: Overlay {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "Overview"
        component: Overview {}
    }
    // Optional primary surface for the ii family. This is the Tablet Family's
    // actual drawer, not a fork: only the tablet-native app/home actions are
    // disabled, while the shared Search panels are injected as usual.
    PanelLoader {
        extraCondition: memScope.selectedItem === "TabletAppDrawer"
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
        active: memScope.selectedItem === "OverviewWindowTransition"
        sourceComponent: OverviewWindowTransition {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "Polkit"
        component: Polkit {}
    }
    // Kept loaded rather than gated: the Scope decides on its own whether BlueZ
    // is asking anything, and nothing is built until it is.
    PanelLoader {
        extraCondition: memScope.selectedItem === "BluetoothPairing"
        component: BluetoothPairing {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "RegionSelector"
        component: RegionSelector {}
    }
    PanelLoader {
        // Four corner windows and their Shape layers are only needed for fake
        // screen rounding or the corner-open hit zones. When both features
        // are off, unload the whole scope instead of keeping four hidden
        // PanelWindows alive.
        extraCondition: memScope.selectedItem === "ScreenCorners"
            || Config.options.sidebar.cornerOpen.enable
        component: ScreenCorners {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "ScreenTranslator"
        component: ScreenTranslator {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "ColorPickerPopup"
        component: ColorPickerPopup {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "SessionScreen"
        component: SessionScreen {}
    }
    // Every family loads the chooser: a family that did not offer it would be one the
    // user could switch into and never find the way out of.
    PanelLoader {
        extraCondition: memScope.selectedItem === "ShellSwitcher"
        component: ShellSwitcher {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "SidebarPolicies"
        component: SidebarPolicies {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "SidebarDashboard"
        component: SidebarDashboard {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "VerticalBar"
        component: VerticalBar {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "WallpaperSelector"
        component: WallpaperSelector {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "WrappedFrame"
        component: WrappedFrame {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "VideoEditorPopup"
        component: VideoEditorPopup {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "VideoEditor"
        component: VideoEditor {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "ScratchpadOverlay"
        component: ScratchpadOverlay {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "AlarmRingingPopup"
        component: AlarmRingingPopup {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "ScreenshotOverlay"
        component: ScreenshotOverlay {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "TilingOverlay"
        component: TilingOverlay {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "LayoutHint"
        component: LayoutHint {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "TilingStackBadges"
        component: TilingStackBadges {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "TopLayer"
        component: TopLayer {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "DynamicIsland"
        Component.onCompleted: {
            console.log("[IllogicalImpulseFamily] DynamicIsland PanelLoader - Config.ready:", Config.ready, "floatingNotch.enable:", Config.options.bar.floatingNotch.enable, "centerInBar:", Config.options.bar.floatingNotch.centerInBar);
        }
        component: DynamicIsland {}
    }
    PanelLoader {
        extraCondition: memScope.selectedItem === "TouchGestures"
        component: TouchGestures {}
    }

    // Memory-attribution probes (harness only).
    Loader {
        active: memScope.selectedItem.startsWith("probe")
        sourceComponent: QtObject {
            Component.onCompleted: {
                const item = memScope.selectedItem;
                if (item === "probeLauncherSearch")
                    LauncherSearch.query;
                else if (item === "probeAi")
                    Ai.enabled;
                else if (item === "probeTypeToSearch")
                    TypeToSearch.armed;
                else if (item === "probeQuickToggleRegistry")
                    QuickToggleRegistry.revision;
                else if (item === "probeBrowserSites")
                    BrowserSites.revision;
                else if (item === "probeQuery") {
                    // Functional probe: a real query runs the whole lazy path —
                    // watchSettingsIndex latch, results compute, quick-toggle
                    // registry latch, SearchPanelRegistry enumeration.
                    LauncherSearch.query = "settings";
                    Qt.callLater(() => {
                        LauncherSearch.query = "";
                    });
                }
            }
        }
    }
}
