import QtQuick
import Quickshell
import qs
import qs.services

import qs.modules.common
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.bluetoothConnectionPopup
import qs.modules.ii.bluetoothPairing
import qs.modules.ii.cheatsheet
import qs.modules.ii.dock
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenDisplay.minimalist
import qs.modules.ii.onScreenKeyboard
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

Scope {
    id: root

    property Component horizontalBarComponent: defaultHorizontalBarComponent
    property Component overviewComponent: defaultOverviewComponent
    property Component sidebarDashboardComponent: defaultSidebarDashboardComponent
    property Component screenCornersComponent: defaultScreenCornersComponent

    Component {
        id: defaultHorizontalBarComponent
        Bar {}
    }

    Component {
        id: defaultOverviewComponent
        Overview {}
    }

    Component {
        id: defaultSidebarDashboardComponent
        SidebarDashboard {}
    }

    Component {
        id: defaultScreenCornersComponent
        ScreenCorners {}
    }

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
        // BarLayout already resolves the family override, so this is just "is the bar horizontal".
        extraCondition: !BarPlacement.vertical && root.barExtraCondition && !GlobalStates.connectModeActive
        component: root.horizontalBarComponent
    }
    PanelLoader {
        extraCondition: Config.options.background.enable
        component: Background {}
    }
    PanelLoader { component: Cheatsheet {} }
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
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
            && !Config.options.bar.floatingNotch.centerInBar
        component: ModeFlashPopup {}
    }
    PanelLoader {
        extraCondition: Config.options.dock.enable
        component: Dock {}
    }
    PanelLoader { component: Lock {} }
    PanelLoader { component: MediaControls {} }
    PanelLoader {
        // Keep the Scope alive so the device-connected trigger can open the popup.
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
        component: BluetoothConnectionPopup {}
    }
    PanelLoader {
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
        component: KeyboardLayoutTransitionPopup {}
    }
    PanelLoader {
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable && GlobalStates.localSendPopupOpen
        component: LocalSendPopup {}
    }
    PanelLoader {
        extraCondition: !(Config.ready && (Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar) && !Config.options.bar.floatingNotch.disableNotification)
        component: NotificationPopup {}
    }
    PanelLoader {
        extraCondition: !(Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material"))
        component: OnScreenDisplay {}
    }
    PanelLoader {
        extraCondition: Config.ready && (Config.options.osd.style === "minimalist" || Config.options.osd.style === "material")
        component: MinimalistOsd {}
    }
    PanelLoader {
        // Kept loaded rather than gated on the service: the windows are empty
        // and invisible until a recording or the quick toggle asks for them.
        extraCondition: Config.ready
        component: KeypressDisplay {}
    }
    PanelLoader { component: OnScreenKeyboard {} }
    PanelLoader { component: OledSaver {} }
    PanelLoader { component: Overlay {} }
    PanelLoader { component: root.overviewComponent }

    // GNOME-like window scale-out during overview. This controller remains shared
    // because it follows GlobalStates and does not own the overview UI itself.
    OverviewWindowTransition {}

    PanelLoader { component: Polkit {} }
    // Kept loaded rather than gated: the Scope decides on its own whether BlueZ
    // is asking anything, and nothing is built until it is.
    PanelLoader { component: BluetoothPairing {} }
    PanelLoader { component: RegionSelector {} }
    PanelLoader {
        extraCondition: root.screenCornersComponent !== null
        component: root.screenCornersComponent
    }
    PanelLoader { component: ScreenTranslator {} }
    PanelLoader { component: ColorPickerPopup {} }
    PanelLoader { component: SessionScreen {} }
    PanelLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        component: SidebarPolicies {}
    }
    PanelLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        component: root.sidebarDashboardComponent
    }
    PanelLoader {
        extraCondition: BarPlacement.vertical && root.barExtraCondition && !GlobalStates.connectModeActive
        component: VerticalBar {}
    }
    PanelLoader { component: WallpaperSelector {} }
    PanelLoader { component: WrappedFrame {} }
    PanelLoader {
        extraCondition: GlobalStates.videoEditorPopupOpen
        component: VideoEditorPopup {}
    }
    PanelLoader {
        extraCondition: GlobalStates.videoEditorOpen
        component: VideoEditor {}
    }
    PanelLoader { component: ScratchpadOverlay {} }
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
        extraCondition: Config.ready && (Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar)
        component: DynamicIsland {}
    }

    readonly property var _touchGestureService: TouchGestureService

    PanelLoader {
        extraCondition: Config.ready && Boolean(Config.options && Config.options.interactions && Config.options.interactions.touchGestures && Config.options.interactions.touchGestures.enable)
        component: TouchGestures {}
    }
}
