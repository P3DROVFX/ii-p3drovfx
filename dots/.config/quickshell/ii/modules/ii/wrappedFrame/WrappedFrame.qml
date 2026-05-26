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

    Bar.BarThemes { id: barThemes }
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

                // INVISIBLE SPACE RESERVERS: Push windows by frameThickness
                component FrameSpaceReserver: PanelWindow {
                    color: "transparent"
                    mask: Region {}
                    exclusionMode: ExclusionMode.Exclusive
                    visible: !monitorScope.fullscreen
                }

                Loader {
                    active: !(!barVertical && !barBottom) // topFrame is visible
                    sourceComponent: FrameSpaceReserver {
                        screen: monitorScope.modelData
                        anchors { top: true; left: true; right: true }
                        implicitHeight: frameThickness
                        exclusiveZone: frameThickness
                    }
                }
                Loader {
                    active: !(!barVertical && barBottom) // bottomFrame is visible
                    sourceComponent: FrameSpaceReserver {
                        screen: monitorScope.modelData
                        anchors { bottom: true; left: true; right: true }
                        implicitHeight: frameThickness
                        exclusiveZone: frameThickness
                    }
                }
                Loader {
                    active: !(barVertical && !barBottom) // leftFrame is visible
                    sourceComponent: FrameSpaceReserver {
                        screen: monitorScope.modelData
                        anchors { left: true; top: true; bottom: true }
                        implicitWidth: frameThickness
                        exclusiveZone: frameThickness
                    }
                }
                Loader {
                    active: !(barVertical && barBottom) // rightFrame is visible
                    sourceComponent: FrameSpaceReserver {
                        screen: monitorScope.modelData
                        anchors { right: true; top: true; bottom: true }
                        implicitWidth: frameThickness
                        exclusiveZone: frameThickness
                    }
                }

                // VISUAL FRAME
                PanelWindow {
                    id: combinedFrameWindow
                    screen: monitorScope.modelData
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }
                    color: "transparent"
                    visible: !monitorScope.fullscreen
                    
                    WlrLayershell.namespace: "quickshell:bar"
                    WlrLayershell.layer: WlrLayer.Overlay
                    exclusionMode: ExclusionMode.Ignore
                    mask: Region {} // Ignore pointer events so normal windows are clickable

                    property color baseColor: monitorScope.showBarBackground ? (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"
                    Behavior on baseColor { 
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(combinedFrameWindow) 
                    }

                    Item {
                        anchors.fill: parent

                        // HORIZONTAL FRAMES
                        Rectangle {
                            id: topFrame
                            visible: !(!barVertical && !barBottom)
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                            }
                            height: frameThickness
                            color: combinedFrameWindow.baseColor
                        }

                        Rectangle {
                            id: bottomFrame
                            visible: !(!barVertical && barBottom)
                            anchors {
                                bottom: parent.bottom
                                left: parent.left
                                right: parent.right
                            }
                            height: frameThickness
                            color: combinedFrameWindow.baseColor
                        }

                        // VERTICAL FRAMES
                        Rectangle {
                            id: leftFrame
                            visible: !(barVertical && !barBottom)
                            anchors {
                                top: topFrame.visible ? topFrame.bottom : parent.top
                                bottom: bottomFrame.visible ? bottomFrame.top : parent.bottom
                                left: parent.left
                            }
                            width: frameThickness
                            color: combinedFrameWindow.baseColor
                        }

                        Rectangle {
                            id: rightFrame
                            visible: !(barVertical && barBottom)
                            anchors {
                                top: topFrame.visible ? topFrame.bottom : parent.top
                                bottom: bottomFrame.visible ? bottomFrame.top : parent.bottom
                                right: parent.right
                            }
                            width: frameThickness
                            color: combinedFrameWindow.baseColor
                        }

                        // CORNERS (Inner radius connecting frames/bar)
                        RoundCorner {
                            id: bottomLeftCorner
                            anchors {
                                bottom: bottomFrame.visible ? bottomFrame.top : parent.bottom
                                left: leftFrame.visible ? leftFrame.right : parent.left
                                bottomMargin: !bottomFrame.visible ? Appearance.sizes.barHeight : 0
                                leftMargin: !leftFrame.visible ? Appearance.sizes.verticalBarWidth : 0
                            }
                            implicitSize: Appearance.rounding.screenRounding
                            color: combinedFrameWindow.baseColor
                            corner: RoundCorner.CornerEnum.BottomLeft
                        }

                        RoundCorner {
                            id: topLeftCorner
                            anchors {
                                top: topFrame.visible ? topFrame.bottom : parent.top
                                left: leftFrame.visible ? leftFrame.right : parent.left
                                topMargin: !topFrame.visible ? Appearance.sizes.barHeight : 0
                                leftMargin: !leftFrame.visible ? Appearance.sizes.verticalBarWidth : 0
                            }
                            implicitSize: Appearance.rounding.screenRounding
                            color: combinedFrameWindow.baseColor
                            corner: RoundCorner.CornerEnum.TopLeft
                        }

                        RoundCorner {
                            id: topRightCorner
                            anchors {
                                top: topFrame.visible ? topFrame.bottom : parent.top
                                right: rightFrame.visible ? rightFrame.left : parent.right
                                topMargin: !topFrame.visible ? Appearance.sizes.barHeight : 0
                                rightMargin: !rightFrame.visible ? Appearance.sizes.verticalBarWidth : 0
                            }
                            implicitSize: Appearance.rounding.screenRounding
                            color: combinedFrameWindow.baseColor
                            corner: RoundCorner.CornerEnum.TopRight
                        }

                        RoundCorner {
                            id: bottomRightCorner
                            anchors {
                                bottom: bottomFrame.visible ? bottomFrame.top : parent.bottom
                                right: rightFrame.visible ? rightFrame.left : parent.right
                                bottomMargin: !bottomFrame.visible ? Appearance.sizes.barHeight : 0
                                rightMargin: !rightFrame.visible ? Appearance.sizes.verticalBarWidth : 0
                            }
                            implicitSize: Appearance.rounding.screenRounding
                            color: combinedFrameWindow.baseColor
                            corner: RoundCorner.CornerEnum.BottomRight
                        }
                    }
                }
            }
        }
    }
}
