import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * "Work mode on" banner for machines without a dynamic island: a small
 * top-centre pill that slides in for the engine's flash window and takes
 * no focus. Built only while something is showing or sliding out.
 */
Scope {
    id: root

    readonly property bool isOpen: GlobalStates.modeFlashActive && GlobalStates.modeFlashPayload !== null

    LazyLoader {
        active: root.isOpen
            || (typeof popupContent !== "undefined" && popupContent ? popupContent.isExitAnimRunning : false)

        component: PanelWindow {
            id: popupWindow
            color: "transparent"
            visible: Quickshell.screens.length > 0
                && (root.isOpen
                    || (typeof popupContent !== "undefined" && popupContent ? popupContent.isExitAnimRunning : false))
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

            WlrLayershell.namespace: "quickshell:modeFlashPopup"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0

            anchors {
                top: true
                bottom: false
                left: false
                right: false
            }

            // Below a top bar, else a sleek margin from the edge.
            readonly property int topMarginValue: {
                if (!Config.options.bar.vertical && !Config.options.bar.bottom)
                    return Appearance.sizes.barHeight + 12;
                return 24;
            }

            implicitWidth: popupContent.implicitWidth
            implicitHeight: popupContent.implicitHeight + topMarginValue

            mask: Region {
                item: popupContent.staticMaskTarget
            }

            ModeFlashPopupContent {
                id: popupContent
                isOpen: root.isOpen
                payload: GlobalStates.modeFlashPayload
                topMarginValue: popupWindow.topMarginValue
            }
        }
    }
}
