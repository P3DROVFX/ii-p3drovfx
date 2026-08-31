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
    property bool barExtraCondition: true
    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3
    readonly property bool barBot: Config.options.bar.bottom
    readonly property bool barVert: Config.options.bar.vertical

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
        extraCondition: !Config.options.bar.vertical && barExtraCondition && !GlobalStates.connectModeActive
        component: Bar {}
    }
    PanelLoader {
        extraCondition: Config.options.background.enable
        component: Background {}
    }
    PanelLoader {
        component: Cheatsheet {}
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
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
            && !Config.options.bar.floatingNotch.centerInBar
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
    // GNOME-like window scale-out during overview (OverviewWindowTransition).
    // Scope com Variants/PanelWindows próprios — instancia direto.
    // featureEnabled interno (zoomOutEnabled + windowZoomOnOverview + zoomOutStyle===0)
    // controla auto-disable. TopLayerPanel em WlrLayer.Overlay sempre fica acima
    // deste (WlrLayer.Top) — sem conflito de z-order em qualquer modo.
    OverviewWindowTransition {}
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
    PanelLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        component: SidebarPolicies {}
    }
    PanelLoader {
        extraCondition: !GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate
        component: SidebarDashboard {}
    }
    PanelLoader {
        extraCondition: Config.options.bar.vertical && barExtraCondition && !GlobalStates.connectModeActive
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
        extraCondition: Config.ready && (Config.options.bar.floatingNotch.enable || Config.options.bar.floatingNotch.centerInBar)
        Component.onCompleted: {
            console.log("[IllogicalImpulseFamily] DynamicIsland PanelLoader - Config.ready:", Config.ready, "floatingNotch.enable:", Config.options.bar.floatingNotch.enable, "centerInBar:", Config.options.bar.floatingNotch.centerInBar);
        }
        component: DynamicIsland {}
    }
    readonly property var _touchGestureService: TouchGestureService

    PanelLoader {
        extraCondition: Config.ready && Boolean(Config.options && Config.options.interactions && Config.options.interactions.touchGestures && Config.options.interactions.touchGestures.enable)
        component: TouchGestures {}
    }
}
