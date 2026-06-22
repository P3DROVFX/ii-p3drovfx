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

Scope {
    id: screenCorners
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel
    property var actionForCorner: ({
            [RoundCorner.CornerEnum.TopLeft]: () => GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen,
            [RoundCorner.CornerEnum.BottomLeft]: () => GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen,
            [RoundCorner.CornerEnum.TopRight]: () => GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen,
            [RoundCorner.CornerEnum.BottomRight]: () => GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
        })
    property var openActionForCorner: ({
            [RoundCorner.CornerEnum.TopLeft]: () => GlobalStates.sidebarLeftOpen = true,
            [RoundCorner.CornerEnum.BottomLeft]: () => GlobalStates.sidebarLeftOpen = true,
            [RoundCorner.CornerEnum.TopRight]: () => GlobalStates.sidebarRightOpen = true,
            [RoundCorner.CornerEnum.BottomRight]: () => GlobalStates.sidebarRightOpen = true
        })

    component CornerPanelWindow: PanelWindow {
        id: cornerPanelWindow
        property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
        property bool fullscreen
        visible: (Config.options.appearance.fakeScreenRounding === 1 || Config.options.appearance.fakeScreenRounding === 2) || Config.options.sidebar.cornerOpen.enable
        property var corner

        readonly property bool isTopLeft: corner === RoundCorner.CornerEnum.TopLeft
        readonly property bool isBottomLeft: corner === RoundCorner.CornerEnum.BottomLeft
        readonly property bool isTopRight: corner === RoundCorner.CornerEnum.TopRight
        readonly property bool isBottomRight: corner === RoundCorner.CornerEnum.BottomRight
        readonly property bool isTop: isTopLeft || isTopRight
        readonly property bool isBottom: isBottomLeft || isBottomRight
        readonly property bool isLeft: isTopLeft || isBottomLeft
        readonly property bool isRight: isTopRight || isBottomRight

        readonly property bool isCornerOpenActive: Config.options.sidebar.cornerOpen.enable && (Config.options.sidebar.cornerOpen.bottom == cornerPanelWindow.isBottom)

        exclusionMode: ExclusionMode.Ignore
        Component.onCompleted: {
            console.info("[ScreenCorners] CornerPanelWindow completed. Corner:", corner, "Visible:", visible, "Enable option:", Config.options.sidebar.cornerOpen.enable, "Fake rounding:", Config.options.appearance.fakeScreenRounding);
        }
        mask: Region {
            item: cornerPanelWindow.isCornerOpenActive ? sidebarCornerOpenInteractionLoader : null
        }
        WlrLayershell.namespace: "quickshell:screenCorners"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"

        anchors {
            top: cornerPanelWindow.isTop
            left: cornerPanelWindow.isLeft
            bottom: cornerPanelWindow.isBottom
            right: cornerPanelWindow.isRight
        }
        margins {
            right: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * -1
            bottom: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * -1
        }

        implicitWidth: isCornerOpenActive ? Math.max(Appearance.rounding.screenRounding, Config.options.sidebar.cornerOpen.cornerRegionWidth) : Appearance.rounding.screenRounding
        implicitHeight: isCornerOpenActive ? Math.max(Appearance.rounding.screenRounding, Config.options.sidebar.cornerOpen.cornerRegionHeight) : Appearance.rounding.screenRounding

        RoundCorner {
            id: cornerWidget
            visible: true
            opacity: (Config.options.appearance.fakeScreenRounding === 1 || (Config.options.appearance.fakeScreenRounding === 2 && !cornerPanelWindow.fullscreen)) ? 1.0 : 0.0
            corner: cornerPanelWindow.corner
            rightVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.right) * 1
            bottomVisualMargin: (Config.options.interactions.deadPixelWorkaround.enable && cornerPanelWindow.anchors.bottom) * 1

            implicitSize: Appearance.rounding.screenRounding
            anchors {
                top: cornerPanelWindow.isTop ? parent.top : undefined
                bottom: cornerPanelWindow.isBottom ? parent.bottom : undefined
                left: cornerPanelWindow.isLeft ? parent.left : undefined
                right: cornerPanelWindow.isRight ? parent.right : undefined
            }
        }

        Loader {
            id: sidebarCornerOpenInteractionLoader
            active: cornerPanelWindow.isCornerOpenActive
            visible: !cornerPanelWindow.fullscreen
            width: active ? Config.options.sidebar.cornerOpen.cornerRegionWidth : 0
            height: active ? Config.options.sidebar.cornerOpen.cornerRegionHeight : 0
            anchors {
                top: cornerPanelWindow.isTop ? parent.top : undefined
                bottom: cornerPanelWindow.isBottom ? parent.bottom : undefined
                left: cornerPanelWindow.isLeft ? parent.left : undefined
                right: cornerPanelWindow.isRight ? parent.right : undefined
            }

            sourceComponent: FocusedScrollMouseArea {
                id: mouseArea
                enabled: !cornerPanelWindow.fullscreen
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: {
                    if (Config.options.sidebar.cornerOpen.clickless || !Config.options.sidebar.cornerOpen.clicklessCornerEnd)
                        return;
                    const verticalOffset = Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset;
                    const correctX = (cornerPanelWindow.isRight && mouseArea.mouseX >= mouseArea.width - 2) || (cornerPanelWindow.isLeft && mouseArea.mouseX <= 2);
                    const correctY = (cornerPanelWindow.isTop && mouseArea.mouseY > verticalOffset || cornerPanelWindow.isBottom && mouseArea.mouseY < mouseArea.height - verticalOffset);
                    if (correctX && correctY)
                        screenCorners.openActionForCorner[cornerPanelWindow.corner]();
                }
                onEntered: {
                    console.info("[ScreenCorners] Mouse entered corner:", cornerPanelWindow.corner, "clickless:", Config.options.sidebar.cornerOpen.clickless);
                    if (Config.options.sidebar.cornerOpen.clickless)
                        screenCorners.openActionForCorner[cornerPanelWindow.corner]();
                }
                onPressed: {
                    console.info("[ScreenCorners] Mouse pressed corner:", cornerPanelWindow.corner);
                    screenCorners.actionForCorner[cornerPanelWindow.corner]();
                }
                onScrollDown: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerPanelWindow.isLeft)
                        Brightness.decreaseBrightness();
                    else {
                        const currentVolume = Audio.value;
                        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
                        Audio.sink.audio.volume -= step;
                    }
                }
                onScrollUp: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerPanelWindow.isLeft)
                        Brightness.increaseBrightness();
                    else {
                        const currentVolume = Audio.value;
                        const step = currentVolume < 0.1 ? 0.01 : 0.02 || 0.2;
                        Audio.sink.audio.volume = Math.min(1, Audio.sink.audio.volume + step);
                    }
                }
                onMovedAway: {
                    if (!Config.options.sidebar.cornerOpen.valueScroll)
                        return;
                    if (cornerPanelWindow.isLeft)
                        GlobalStates.osdBrightnessOpen = false;
                    else
                        GlobalStates.osdVolumeOpen = false;
                }

                Loader {
                    active: Config.options.sidebar.cornerOpen.visualize
                    anchors.fill: parent
                    sourceComponent: Rectangle {
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: monitorScope
            required property var modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

            // Hide when fullscreen
            property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor.name)
            property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
            property bool fullscreen: activeWorkspaceWithFullscreen != undefined
            // Deferred to avoid Wayland dispatch reentrancy crash in PanelWindow visibility
            property bool deferredFullscreen: false
            Timer {
                id: fullscreenDeferTimer
                interval: 50
                repeat: false
                onTriggered: monitorScope.deferredFullscreen = monitorScope.fullscreen
            }
            onFullscreenChanged: fullscreenDeferTimer.restart()

            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.TopLeft
                fullscreen: monitorScope.deferredFullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.TopRight
                fullscreen: monitorScope.deferredFullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.BottomLeft
                fullscreen: monitorScope.deferredFullscreen
            }
            CornerPanelWindow {
                screen: modelData
                corner: RoundCorner.CornerEnum.BottomRight
                fullscreen: monitorScope.deferredFullscreen
            }
        }
    }
}
