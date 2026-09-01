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
                // Keep the reserver mapped while the shared lock transition
                // runs so the compositor does not rebuild layer geometry.
                active: !BarPlacement.vertical && GlobalStates.barOpen && GlobalStates.isScreenAllowedForBar(monitorScope.modelData)
                sourceComponent: PanelWindow {
                    id: hBarSpaceReserver
                    screen: monitorScope.modelData
                    anchors {
                        top: !BarPlacement.bottom
                        bottom: BarPlacement.bottom
                        left: true
                        right: true
                    }
                    exclusionMode: ExclusionMode.Normal
                    
                    // We read the hiddenAmount from the visual panel to smoothly animate the exclusive zone
                    property real hiddenAmount: visualPanel.hBarHiddenAmount
                    property real targetZone: Appearance.sizes.baseBarHeight + (BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
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
                active: BarPlacement.vertical && GlobalStates.barOpen && GlobalStates.isScreenAllowedForBar(monitorScope.modelData)
                sourceComponent: PanelWindow {
                    id: vBarSpaceReserver
                    screen: monitorScope.modelData
                    anchors {
                        left: !BarPlacement.bottom
                        right: BarPlacement.bottom
                        top: true
                        bottom: true
                    }
                    exclusionMode: ExclusionMode.Normal
                    
                    property real hiddenAmount: visualPanel.vBarHiddenAmount
                    property real targetZone: Appearance.sizes.baseVerticalBarWidth + (BarInteraction.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
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
