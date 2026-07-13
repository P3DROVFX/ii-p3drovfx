import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.shared
import qs.modules.ii.wrappedFrame

Scope {
    id: bar

    Variants {
        id: barVariant
        // For each monitor
        readonly property var variantModel: GlobalStates.allowedScreens
        model: variantModel
        LazyLoader {
            id: barLoader
            required property ShellScreen modelData
            property var monitorIndex: barVariant.variantModel.indexOf(barLoader.modelData)

            active: GlobalStates.barOpen && !GlobalStates.screenLocked && !GlobalStates.connectModeActive
            component: Scope {
                id: barScope

                property HyprlandMonitor hyprMonitor: Hyprland.monitorFor(barLoader.modelData)

                PanelWindow {
                    id: barSpaceReserver
                    screen: barLoader.modelData
                    anchors {
                        left: !Config.options.bar.bottom
                        right: Config.options.bar.bottom
                        top: true
                        bottom: true
                    }
                    exclusionMode: ExclusionMode.Normal

                    property real targetZone: Appearance.sizes.baseVerticalBarWidth + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
                    property real minZone: Config.options.appearance.fakeScreenRounding === 3 ? Config.options.appearance.wrappedFrameThickness : 0

                    exclusiveZone: (Config?.options.bar.autoHide.enable && !Config?.options.bar.autoHide.pushWindows) ? minZone : Math.max(minZone, targetZone - (barRoot ? barRoot.hiddenAmount : 0))

                    implicitWidth: Appearance.sizes.verticalBarWindowWidth + Appearance.rounding.screenRounding
                    color: "transparent"
                    mask: Region {}
                }

                PanelWindow { // Bar window (Full screen)
                    id: barRoot
                    screen: barLoader.modelData
                    // Fullscreen windows naturally cover the bar via the Wayland compositor
                    // (Hyprland places fullscreen windows above WlrLayer.Top). No QML
                    // visibility toggling needed — that approach caused SIGSEGV crashes.

                    property var brightnessMonitor: Brightness.getMonitorForScreen(barLoader.modelData)

                    property int monitorIndex: barLoader.monitorIndex
                    property bool hasActiveWindows: false
                    property bool showBarBackground: barRoot.hasActiveWindows && Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 1 || Config.options.bar.barBackgroundStyle === 3

                    BarThemes {
                        id: barThemes
                    }
                    property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

                    Connections {
                        enabled: Config.options.bar.barBackgroundStyle === 2 || Config.options.bar.barBackgroundStyle === 3
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
                    property bool superShow: false
                    property bool mustShow: hoverRegion.containsMouse || superShow || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen
                    property real hiddenAmount: (Config?.options.bar.autoHide.enable && !mustShow) ? Appearance.sizes.verticalBarWindowWidth : 0
                    Behavior on hiddenAmount {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barRoot)
                    }

                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    WlrLayershell.namespace: "quickshell:verticalBar"
                    // WlrLayershell.layer: WlrLayer.Overlay // TODO: enable this when bar can reliably hide when fullscreen without crashing

                    mask: Region {
                        item: hoverMaskRegion
                    }
                    color: "transparent"

                    // Positioning FULL SCREEN
                    anchors {
                        left: true
                        right: true
                        top: true
                        bottom: true
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
                        sourceComponent: Component {
                            Item {
                                anchors.fill: parent
                                WrappedFrameVisuals {
                                    showBarBackground: barRoot.showBarBackground
                                    hBarHiddenAmount: 0
                                    vBarHiddenAmount: barRoot.hiddenAmount
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: hoverRegion
                        hoverEnabled: true
                        anchors.fill: parent

                        Item {
                            id: hoverMaskRegion
                            readonly property real shadowExtend: Config.options.bar.dropShadow ? 24 : 0
                            readonly property real sideMaskExtend: Config.options.bar.autoHide.enable ? Math.max(Config.options.bar.autoHide.hoverRegionWidth, shadowExtend) : shadowExtend
                            anchors {
                                fill: barContent
                                leftMargin: -sideMaskExtend
                                rightMargin: -sideMaskExtend
                            }
                        }

                        VerticalBarContent {
                            id: barContent
                            monitorIndex: barRoot.monitorIndex
                            implicitWidth: Appearance.sizes.verticalBarWindowWidth
                            anchors {
                                top: parent.top
                                bottom: parent.bottom
                                left: parent.left
                                right: undefined
                                leftMargin: -barRoot.hiddenAmount
                                rightMargin: 0
                            }
                            Behavior on anchors.leftMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            Behavior on anchors.rightMargin {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            states: State {
                                name: "right"
                                when: Config.options.bar.bottom
                                AnchorChanges {
                                    target: barContent
                                    anchors {
                                        top: parent.top
                                        bottom: parent.bottom
                                        left: undefined
                                        right: parent.right
                                    }
                                }
                                PropertyChanges {
                                    target: barContent
                                    anchors.leftMargin: 0
                                    anchors.rightMargin: -barRoot.hiddenAmount
                                }
                            }
                        }

                        // Round decorators
                        Loader {
                            id: roundDecorators
                            anchors {
                                top: parent.top
                                bottom: parent.bottom
                                left: barContent.right
                                right: undefined
                            }
                            width: Appearance.rounding.screenRounding
                            active: barRoot.showBarBackground && Config.options.bar.cornerStyle === 0 && Config.options.bar.barBackgroundStyle !== 3 && Config.options.appearance.fakeScreenRounding != 3 // Hug

                            states: State {
                                name: "right"
                                when: Config.options.bar.bottom
                                AnchorChanges {
                                    target: roundDecorators
                                    anchors {
                                        top: parent.top
                                        bottom: parent.bottom
                                        left: undefined
                                        right: barContent.left
                                    }
                                }
                            }

                            sourceComponent: Item {
                                implicitHeight: Appearance.rounding.screenRounding
                                RoundCorner {
                                    id: topCorner
                                    anchors {
                                        left: parent.left
                                        right: parent.right
                                        top: parent.top
                                    }

                                    implicitSize: Appearance.rounding.screenRounding
                                    color: barRoot.showBarBackground ? (Config.options.bar.expressiveColors ? barRoot.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

                                    corner: RoundCorner.CornerEnum.TopLeft
                                    states: State {
                                        name: "bottom"
                                        when: Config.options.bar.bottom
                                        PropertyChanges {
                                            topCorner.corner: RoundCorner.CornerEnum.TopRight
                                        }
                                    }
                                }
                                RoundCorner {
                                    id: bottomCorner
                                    anchors {
                                        bottom: parent.bottom
                                        left: !Config.options.bar.bottom ? parent.left : undefined
                                        right: Config.options.bar.bottom ? parent.right : undefined
                                    }
                                    implicitSize: Appearance.rounding.screenRounding
                                    color: barRoot.showBarBackground ? (Config.options.bar.expressiveColors ? barRoot.activeTheme.barBackground : Appearance.colors.colLayer0) : "transparent"

                                    corner: RoundCorner.CornerEnum.BottomLeft
                                    states: State {
                                        name: "bottom"
                                        when: Config.options.bar.bottom
                                        PropertyChanges {
                                            bottomCorner.corner: RoundCorner.CornerEnum.BottomRight
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
