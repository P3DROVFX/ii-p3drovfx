import QtQuick
import Quickshell
import qs

import qs.modules.common
import qs.modules.ii.background
import qs.modules.ii.bar
import qs.modules.ii.bluetoothConnectionPopup
import qs.modules.ii.cheatsheet
import qs.modules.ii.dock
import qs.modules.ii.lock
import qs.modules.ii.mediaControls
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay
import qs.modules.ii.onScreenKeyboard
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
import qs.modules.ii.topLayer
import qs.modules.ii.alarmRingingPopup
import qs.modules.ii.dynamicIsland

Scope {
    property bool barExtraCondition: true
    readonly property bool usingWrappedFrame: Config.options.appearance.fakeScreenRounding === 3 && !(Config.options.bar.cornerStyle === 3 && !Config.options.bar.vertical)
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
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
        component: BluetoothConnectionPopup {}
    }
    PanelLoader {
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
        component: KeyboardLayoutTransitionPopup {}
    }
    PanelLoader {
        extraCondition: Config.ready && !Config.options.bar.floatingNotch.enable
        component: LocalSendPopup {}
    }
    PanelLoader {
        extraCondition: !(Config.ready && Config.options.bar.floatingNotch.enable && !Config.options.bar.floatingNotch.disableNotification)
        component: NotificationPopup {}
    }
    PanelLoader {
        component: OnScreenDisplay {}
    }
    PanelLoader {
        component: OnScreenKeyboard {}
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
        component: VideoEditorPopup {}
    }
    PanelLoader {
        component: VideoEditor {}
    }
    PanelLoader {
        component: ScratchpadOverlay {}
    }
    PanelLoader {
        component: AlarmRingingPopup {}
    }
    PanelLoader {
        extraCondition: GlobalStates.connectModeActive
        component: TopLayer {}
    }
    PanelLoader {
        extraCondition: Config.ready && Config.options.bar.floatingNotch.enable
        Component.onCompleted: {
            console.log("[IllogicalImpulseFamily] DynamicIsland PanelLoader - Config.ready:", Config.ready, "floatingNotch.enable:", Config.options.bar.floatingNotch.enable, "extraCondition:", Config.ready && Config.options.bar.floatingNotch.enable);
        }
        component: DynamicIsland {}
    }
}
