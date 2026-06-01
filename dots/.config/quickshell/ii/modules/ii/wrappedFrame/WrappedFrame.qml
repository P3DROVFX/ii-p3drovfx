import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.modules.ii.bar as Bar

Item {
    id: wrappedFrame

    property int frameThickness: Config.options.appearance.wrappedFrameThickness
    property bool barVertical: Config.options.bar.vertical
    property bool barBottom: Config.options.bar.bottom

    Bar.BarThemes {
        id: barThemes
    }
    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    Loader {
        active: Config.options.appearance.fakeScreenRounding == 3 && !GlobalStates.screenLocked
        sourceComponent: Variants {
            id: wrappedFrameVariant
            property var variantModel: Quickshell.screens
            model: variantModel

            Scope {
                id: monitorScope
                required property var modelData

                property int index: wrappedFrameVariant.variantModel.indexOf(monitorScope.modelData)
                property bool hasActiveWindows: false
                property bool showBarBackground: monitorScope.hasActiveWindows && Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 1

                property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
                property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
                property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
                property bool fullscreen: activeWorkspaceWithFullscreen != undefined

                Connections {
                    enabled: Config.options.bar.barBackgroundStyle === 2
                    target: HyprlandData
                    function onWindowListChanged() {
                        const monitor = HyprlandData.monitors.find(m => m.id === monitorScope.index);
                        const wsId = monitor?.activeWorkspace?.id;

                        const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;

                        monitorScope.hasActiveWindows = hasWindow;
                    }
                }

                Loader {
                    active: !(!barVertical && !barBottom) // topFrame is visible
                    sourceComponent: FrameSpaceReserver {
                        screen: monitorScope.modelData
                        anchors {
                            top: true
                            left: true
                            right: true
                        }
                        implicitHeight: frameThickness
                        exclusiveZone: frameThickness
                    }
                }
                Loader {
                    active: !(!barVertical && barBottom) // bottomFrame is visible
                    sourceComponent: FrameSpaceReserver {
                        screen: monitorScope.modelData
                        anchors {
                            bottom: true
                            left: true
                            right: true
                        }
                        implicitHeight: frameThickness
                        exclusiveZone: frameThickness
                    }
                }
                Loader {
                    active: !(barVertical && !barBottom) // leftFrame is visible
                    sourceComponent: FrameSpaceReserver {
                        screen: monitorScope.modelData
                        anchors {
                            left: true
                            top: true
                            bottom: true
                        }
                        implicitWidth: frameThickness
                        exclusiveZone: frameThickness
                    }
                }
                Loader {
                    active: !(barVertical && barBottom) // rightFrame is visible
                    sourceComponent: FrameSpaceReserver {
                        screen: monitorScope.modelData
                        anchors {
                            right: true
                            top: true
                            bottom: true
                        }
                        implicitWidth: frameThickness
                        exclusiveZone: frameThickness
                    }
                }

                // VISUAL FRAME MOVED TO BAR AND VERTICALBAR TO FIX BLUR CLAMPING AND TRANSPARENCY
                // See Bar.qml and VerticalBar.qml
            }
        }
    }

    // INVISIBLE SPACE RESERVERS: Push windows by frameThickness
    component FrameSpaceReserver: PanelWindow {
        color: "transparent"
        mask: Region {}
        exclusionMode: ExclusionMode.Exclusive
        visible: !monitorScope.fullscreen
    }
}
