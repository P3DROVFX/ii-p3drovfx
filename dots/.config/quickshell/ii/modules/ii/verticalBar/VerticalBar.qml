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

    readonly property bool lockUsesFade: Config.options.appearance.fakeScreenRounding === 3
    readonly property real lockTransitionProgress: GlobalStates.lockBarTransitionProgress
    readonly property bool lockTransitionActive: lockTransitionProgress > 0.01
    readonly property real lockSlideDistance: Appearance.sizes.verticalBarWindowWidth + Appearance.rounding.screenRounding
    readonly property real lockSlideOffsetX: Config.options.bar.bottom ? lockSlideDistance : -lockSlideDistance

    Variants {
        id: barVariant
        // For each monitor
        readonly property var variantModel: GlobalStates.allowedScreens
        model: variantModel
        LazyLoader {
            id: barLoader
            required property ShellScreen modelData
            property var monitorIndex: barVariant.variantModel.indexOf(barLoader.modelData)

            // Preserve the mapped PanelWindow through lock entry so the
            // compositor does not reflow the screen while WlSessionLock appears.
            active: GlobalStates.barOpen && !GlobalStates.connectModeActive && !GlobalStates.isMediaModeActiveForScreen(barLoader.modelData ? barLoader.modelData.name : "")
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

                    exclusiveZone: (Config.options.bar.autoHide.enable && !Config.options.bar.autoHide.pushWindows) ? minZone : Math.max(minZone, targetZone - (barRoot ? barRoot.hiddenAmount : 0))

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
                            const wsId = monitor ? (monitor.activeWorkspace ? monitor.activeWorkspace.id : undefined) : undefined;

                            const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;

                            barRoot.hasActiveWindows = hasWindow;
                        }
                    }

                    Timer {
                        id: showBarTimer
                        interval: (Config.options.bar.autoHide.showWhenPressingSuper.delay ?? 100)
                        repeat: false
                        onTriggered: {
                            barRoot.superShow = true;
                        }
                    }
                    Connections {
                        target: GlobalStates
                        function onSuperDownChanged() {
                            if (!Config.options.bar.autoHide.showWhenPressingSuper.enable)
                                return;
                            if (GlobalStates.superDown)
                                showBarTimer.restart();
                            else {
                                showBarTimer.stop();
                                barRoot.superShow = false;
                            }
                        }
                    }
                    // ── Shell edge slide ─────────────────────────────────
                    // Only the placement swap moves this bar off screen; a
                    // fullscreen window is handled by the compositor stacking
                    // (see the note on barRoot above). The direction comes from
                    // the live config, so the bar exits through the edge it is
                    // on and the horizontal bar takes over from the other side.
                    readonly property real shellHide: GlobalStates.barPlacementSwapProgress
                    readonly property real shellSlideX: (Config.options.bar.bottom ? 1 : -1)
                        * shellHide * (Appearance.sizes.verticalBarWindowWidth + Appearance.rounding.screenRounding)
                    readonly property bool shellSeated: shellHide < 0.999

                    // ── Hover delay trigger ───────────────────────────────────────
                    property bool hoverTriggered: false
                    readonly property int hoverDelay: Config.options.bar.autoHide.hoverDelay ?? 0

                    Timer {
                        id: hoverOpenTimer
                        interval: barRoot.hoverDelay
                        repeat: false
                        onTriggered: barRoot.hoverTriggered = true
                    }

                    Connections {
                        target: hoverRegion
                        function onContainsMouseChanged() {
                            if (hoverRegion.containsMouse) {
                                if (barRoot.hoverDelay <= 0 || barRoot.hiddenAmount < 1 || barRoot.superShow || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen) {
                                    barRoot.hoverTriggered = true;
                                } else {
                                    hoverOpenTimer.restart();
                                }
                            } else {
                                hoverOpenTimer.stop();
                                barRoot.hoverTriggered = false;
                            }
                        }
                    }

                    property bool superShow: false
                    property bool mustShow: hoverTriggered || superShow || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen
                    property real hiddenAmount: (Config.options.bar.autoHide.enable && !mustShow) ? Appearance.sizes.verticalBarWindowWidth : 0
                    Behavior on hiddenAmount {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barRoot)
                    }

                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    WlrLayershell.namespace: "quickshell:verticalBar"
                    // WlrLayershell.layer: WlrLayer.Overlay // TODO: enable this when bar can reliably hide when fullscreen without crashing

                    mask: Region {
                        item: bar.lockTransitionActive ? null : hoverMaskRegion
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
                        visible: barRoot.shellSeated
                        opacity: bar.lockUsesFade ? 1.0 - bar.lockTransitionProgress : 1.0
                        sourceComponent: Component {
                            Item {
                                anchors.fill: parent
                                WrappedFrameVisuals {
                                    showBarBackground: barRoot.showBarBackground
                                    hBarHiddenAmount: 0
                                    vBarHiddenAmount: barRoot.hiddenAmount
                                    hideProgress: barRoot.shellHide
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: hoverRegion
                        hoverEnabled: true
                        anchors.fill: parent
                        visible: barRoot.shellSeated
                        opacity: bar.lockUsesFade ? 1.0 - bar.lockTransitionProgress : 1.0
                        transform: Translate {
                            x: (bar.lockUsesFade ? 0 : bar.lockSlideOffsetX * bar.lockTransitionProgress) + barRoot.shellSlideX
                        }

                        Item {
                            id: hoverMaskRegion
                            readonly property real shadowExtend: 0
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

        function toggle() {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }

        function close() {
            GlobalStates.barOpen = false;
        }

        function open() {
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
