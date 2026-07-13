import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common

Scope {
    id: root

    Variants {
        id: screensVariant
        model: Quickshell.screens
        delegate: Scope {
            id: monitorScope
            required property var modelData

            TopLayerPanel {
                id: visualPanel
                screen: monitorScope.modelData
            }

            // Horizontal Bar Space Reserver Loader
            Loader {
                active: !Config.options.bar.vertical && GlobalStates.barOpen && !GlobalStates.screenLocked && GlobalStates.isScreenAllowedForBar(monitorScope.modelData)
                sourceComponent: PanelWindow {
                    id: hBarSpaceReserver
                    screen: monitorScope.modelData
                    anchors {
                        top: !Config.options.bar.bottom
                        bottom: Config.options.bar.bottom
                        left: true
                        right: true
                    }
                    exclusionMode: ExclusionMode.Normal
                    
                    // We read the hiddenAmount from the visual panel to smoothly animate the exclusive zone
                    property real hiddenAmount: visualPanel.hBarHiddenAmount
                    property real targetZone: Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                    property real minZone: visualPanel.usingWrappedFrame ? Config.options.appearance.wrappedFrameThickness : 0
                    
                    exclusiveZone: (Config?.options.bar.autoHide.enable && !Config?.options.bar.autoHide.pushWindows) 
                        ? minZone 
                        : Math.max(minZone, targetZone - hiddenAmount)

                    implicitHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding
                    color: "transparent"
                    mask: Region {}
                }
            }

            // Vertical Bar Space Reserver Loader
            Loader {
                active: Config.options.bar.vertical && GlobalStates.barOpen && !GlobalStates.screenLocked && GlobalStates.isScreenAllowedForBar(monitorScope.modelData)
                sourceComponent: PanelWindow {
                    id: vBarSpaceReserver
                    screen: monitorScope.modelData
                    anchors {
                        left: !Config.options.bar.bottom
                        right: Config.options.bar.bottom
                        top: true
                        bottom: true
                    }
                    exclusionMode: ExclusionMode.Normal
                    
                    property real hiddenAmount: visualPanel.vBarHiddenAmount
                    property real targetZone: Appearance.sizes.baseVerticalBarWidth + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                    property real minZone: visualPanel.usingWrappedFrame ? Config.options.appearance.wrappedFrameThickness : 0
                    
                    exclusiveZone: (Config?.options.bar.autoHide.enable && !Config?.options.bar.autoHide.pushWindows) 
                        ? minZone 
                        : Math.max(minZone, targetZone - hiddenAmount)

                    implicitWidth: Appearance.sizes.verticalBarWidth + Appearance.rounding.screenRounding
                    color: "transparent"
                    mask: Region {}
                }
            }
        }
    }
}
