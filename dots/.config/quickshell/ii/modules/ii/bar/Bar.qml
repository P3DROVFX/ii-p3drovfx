pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.wrappedFrame

Scope {
    id: bar

    Variants {
        // For each monitor
        id: barVariant

        readonly property var variantModel: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        model: variantModel
        LazyLoader {
            id: barLoader
            required property ShellScreen modelData
            property int monitorIndex: barVariant.variantModel.indexOf(modelData)

            active: GlobalStates.barOpen && !GlobalStates.screenLocked && !GlobalStates.connectModeActive
            component: Scope {
                id: barScope

                property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(barLoader.modelData)

                PanelWindow {
                    id: barSpaceReserver
                    screen: barLoader.modelData
                    anchors {
                        top: !Config.options.bar.bottom
                        bottom: Config.options.bar.bottom
                        left: true
                        right: true
                    }
                    exclusionMode: ExclusionMode.Normal

                    property real targetZone: Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                    property real minZone: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0

                    exclusiveZone: {
                        if (barRoot && barRoot.hasFullscreenWindowOnMonitor) return 0;
                        return (Config?.options.bar.autoHide.enable && !Config?.options.bar.autoHide.pushWindows) ? minZone : Math.max(minZone, targetZone - (barRoot ? barRoot.hiddenAmount : 0));
                    }

                    implicitHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding
                    color: "transparent"
                    mask: Region {}
                }

                PanelWindow { // Bar window (Full screen)
                    id: barRoot
                    screen: barLoader.modelData
                    // Fullscreen windows naturally cover the bar via the Wayland compositor
                    // (Hyprland places fullscreen windows above WlrLayer.Top). No QML
                    // visibility toggling needed — that approach caused SIGSEGV crashes.

                    property int monitorIndex: barLoader.monitorIndex
                    property bool hasActiveWindows: false
                    property bool showBarBackground: barRoot.hasActiveWindows && Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 1

                    BarThemes {
                        id: barThemes
                    }
                    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

                    Connections {
                        enabled: Config.options.bar.barBackgroundStyle === 2
                        target: HyprlandData
                        function onWindowListChanged() {
                            const monitor = HyprlandData.monitors.find(m => m.name === barRoot.screen.name);
                            const wsId = monitor?.activeWorkspace?.id;

                            const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;

                            barRoot.hasActiveWindows = hasWindow;
                        }
                    }

                    Timer {
                        id: showBarTimer
                        interval: (Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                        repeat: false
                        onTriggered: {
                            barRoot.superShow = true;
                        }
                    }
                    Connections {
                        target: GlobalStates
                        function onSuperDownChanged() {
                            if (!Config?.options.bar.autoHide.showWhenPressingSuper.enable)
                                return;
                            if (GlobalStates.superDown)
                                showBarTimer.restart();
                            else {
                                showBarTimer.stop();
                                barRoot.superShow = false;
                            }
                        }
                    }
                    readonly property bool hasFullscreenWindowOnMonitor: {
                        const monitorData = HyprlandData.monitors.find(m => m.name === barRoot.screen.name);
                        const specialWsName = monitorData?.specialWorkspace?.name;
                        const workspaces = Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === barRoot.screen.name);
                        return workspaces.some(workspace => {
                            const isWorkspaceActive = workspace.active || 
                                (specialWsName && specialWsName !== "" && 
                                 (workspace.name === specialWsName || 
                                  workspace.name === "special:" + specialWsName ||
                                  (specialWsName === "special:special" && workspace.name === "special") ||
                                  (specialWsName === "special" && workspace.name === "special:special")));
                            
                            return isWorkspaceActive && 
                                workspace.toplevels.values.some(toplevel => toplevel.wayland && toplevel.wayland.fullscreen);
                        });
                    }
                    property bool superShow: false
                    property bool mustShow: !hasFullscreenWindowOnMonitor && (hoverRegion.containsMouse || superShow || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen)
                    property real hiddenAmount: (hasFullscreenWindowOnMonitor || (Config?.options.bar.autoHide.enable && !mustShow)) ? Appearance.sizes.barHeight : 0
                    Behavior on hiddenAmount {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barRoot)
                    }

                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    WlrLayershell.namespace: "quickshell:bar"
                    // WlrLayershell.layer: WlrLayer.Overlay // TODO: enable this when bar can reliably hide when fullscreen without crashing

                    mask: Region {
                        item: hoverMaskRegion
                    }
                    color: "transparent"

                    // Positioning FULL SCREEN
                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }

                    // Include in focus grab
                    Component.onCompleted: {
                        GlobalFocusGrab.addPersistent(barRoot);
                    }
                    Component.onDestruction: {
                        GlobalFocusGrab.removePersistent(barRoot);
                    }

                    // WrappedFrame Visuals merged here so blur calculates them together!
                    Loader {
                        active: Config.options.appearance.fakeScreenRounding == 3
                        anchors.fill: parent
                        opacity: barRoot.hasFullscreenWindowOnMonitor ? 0.0 : 1.0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        sourceComponent: Component {
                            Item {
                                anchors.fill: parent
                                WrappedFrameVisuals {
                                    showBarBackground: barRoot.showBarBackground
                                    hBarHiddenAmount: barRoot.hiddenAmount
                                    vBarHiddenAmount: 0
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: hoverRegion
                        hoverEnabled: true
                        opacity: barRoot.hasFullscreenWindowOnMonitor ? 0.0 : 1.0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                                easing.type: Appearance.animation.elementMoveFast.type
                                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                            }
                        }
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: !Config.options.bar.bottom ? parent.top : undefined
                            bottom: Config.options.bar.bottom ? parent.bottom : undefined
                            rightMargin: (Config.options.interactions.deadPixelWorkaround.enable) * 1
                            bottomMargin: (Config.options.interactions.deadPixelWorkaround.enable && Config.options.bar.bottom) * 1
                        }
                        height: Appearance.sizes.barHeight + Appearance.rounding.screenRounding

                        Item {
                            id: hoverMaskRegion
                            anchors {
                                fill: barContent
                                topMargin: -Config.options.bar.autoHide.hoverRegionWidth
                                bottomMargin: -Config.options.bar.autoHide.hoverRegionWidth
                            }
                        }

                        BarContent {
                            id: barContent

                            implicitHeight: Appearance.sizes.barHeight
                            anchors {
                                right: parent.right
                                left: parent.left
                                top: parent.top
                                bottom: undefined
                                topMargin: -barRoot.hiddenAmount
                                rightMargin: (Config.options.interactions.deadPixelWorkaround.enable) * -1
                            }
                            Behavior on anchors.topMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on anchors.bottomMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            states: State {
                                name: "bottom"
                                when: Config.options.bar.bottom
                                AnchorChanges {
                                    target: barContent
                                    anchors {
                                        right: parent.right
                                        left: parent.left
                                        top: undefined
                                        bottom: parent.bottom
                                    }
                                }
                                PropertyChanges {
                                    target: barContent
                                    anchors.topMargin: 0
                                    anchors.bottomMargin: -barRoot.hiddenAmount - ((Config.options.interactions.deadPixelWorkaround.enable) ? 1 : 0)
                                }
                            }
                        }

                        // Round decorators
                        Loader {
                            id: roundDecorators
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: barContent.bottom
                                bottom: undefined
                            }
                            height: Appearance.rounding.screenRounding
                            active: barRoot.showBarBackground && Config.options.bar.cornerStyle === 0 && Config.options.appearance.fakeScreenRounding != 3 // Hug

                            states: State {
                                name: "bottom"
                                when: Config.options.bar.bottom
                                AnchorChanges {
                                    target: roundDecorators
                                    anchors {
                                        right: parent.right
                                        left: parent.left
                                        top: undefined
                                        bottom: barContent.top
                                    }
                                }
                            }

                            sourceComponent: Item {
                                implicitHeight: Appearance.rounding.screenRounding
                                RoundCorner {
                                    id: leftCorner
                                    anchors {
                                        top: parent.top
                                        bottom: parent.bottom
                                        left: parent.left
                                    }

                                    implicitSize: Appearance.rounding.screenRounding
                                    color: barRoot.showBarBackground ? (Config.options.bar.expressiveColors ? barRoot.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

                                    corner: RoundCorner.CornerEnum.TopLeft
                                    states: State {
                                        name: "bottom"
                                        when: Config.options.bar.bottom
                                        PropertyChanges {
                                            leftCorner.corner: RoundCorner.CornerEnum.BottomLeft
                                        }
                                    }
                                }
                                RoundCorner {
                                    id: rightCorner
                                    anchors {
                                        right: parent.right
                                        top: !Config.options.bar.bottom ? parent.top : undefined
                                        bottom: Config.options.bar.bottom ? parent.bottom : undefined
                                    }
                                    implicitSize: Appearance.rounding.screenRounding
                                    color: barRoot.showBarBackground ? (Config.options.bar.expressiveColors ? barRoot.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

                                    corner: RoundCorner.CornerEnum.TopRight
                                    states: State {
                                        name: "bottom"
                                        when: Config.options.bar.bottom
                                        PropertyChanges {
                                            rightCorner.corner: RoundCorner.CornerEnum.BottomRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }

        function close(): void {
            GlobalStates.barOpen = false;
        }

        function open(): void {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"

        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"

        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"

        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
