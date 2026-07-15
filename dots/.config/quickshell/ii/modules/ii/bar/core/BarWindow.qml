pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.wrappedFrame
import qs.modules.ii.bar.shared
import qs.modules.ii.bar

// Encapsulates the two PanelWindows (space-reserver + main bar)
// and all autohide / fullscreen detection logic.
// Bar.qml instantiates this once per monitor via Variants + LazyLoader.
Scope {
    id: root

    required property ShellScreen screen
    required property int monitorIndex

    // ── Space reserver (reserves space so windows don't overlap bar) ──────────
    PanelWindow {
        id: barSpaceReserver
        screen: root.screen
        anchors {
            top: !Config.options.bar.bottom
            bottom: Config.options.bar.bottom
            left: true
            right: true
        }
        exclusionMode: (Config.ready && Config.options.bar.dynamicIsland.notchMode.enable && Config.options.bar.dynamicIsland.notchMode.overlapApps) ? ExclusionMode.Ignore : ExclusionMode.Normal

        property real targetZone: Appearance.sizes.baseBarHeight + (Config.options.bar.cornerStyle === 1 ? Appearance.sizes.hyprlandGapsOut : 0)
        property real minZone: (Config.options.appearance.fakeScreenRounding === 3 && Config.options.bar.cornerStyle !== 3) ? Config.options.appearance.wrappedFrameThickness : 0

        exclusiveZone: {
            if (barRoot.hasFullscreenWindowOnMonitor)
                return 0;
            if (Config.ready && Config.options.bar.dynamicIsland.notchMode.enable && Config.options.bar.dynamicIsland.notchMode.overlapApps) {
                return 0;
            }
            return (Config?.options.bar.autoHide.enable && !Config?.options.bar.autoHide.pushWindows) ? minZone : Math.max(minZone, targetZone - barRoot.hiddenAmount);
        }

        implicitHeight: Appearance.sizes.barHeight + Appearance.rounding.screenRounding
        color: "transparent"
        mask: Region {}
    }

    // ── Main bar window ───────────────────────────────────────────────────────
    PanelWindow {
        id: barRoot
        screen: root.screen

        property int monitorIndex: root.monitorIndex
        property bool hasActiveWindows: false
        readonly property bool isSearchActiveHere: {
            return GlobalStates.overviewOpen && (barRoot.screen ? GlobalStates.activeSearchMonitor === barRoot.screen.name : false) && (Config.ready && Config.options.bar.dynamicIsland.notchMode.enable);
        }
        property bool showBarBackground: (hasActiveWindows && Config.options.bar.barBackgroundStyle === 2) || Config.options.bar.barBackgroundStyle === 1 || Config.options.bar.barBackgroundStyle === 3

        BarThemes {
            id: barThemes
        }
        property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

        // ── Window tracking (for showBarBackground) ──────────────────────────
        Connections {
            enabled: Config.options.bar.barBackgroundStyle === 2 || (Config.options.bar.barBackgroundStyle === 3 && (Config.options.bar.cornerStyle === 0 || Config.options.bar.cornerStyle === 1))
            target: HyprlandData
            function onWindowListChanged() {
                const monitor = HyprlandData.monitors.find(m => m.name === barRoot.screen.name);
                const wsId = monitor?.activeWorkspace?.id;
                const hasWindow = wsId ? HyprlandData.windowList.some(w => w.workspace.id === wsId && !w.floating) : false;
                barRoot.hasActiveWindows = hasWindow;
            }
        }

        // ── Super-key autohide trigger ────────────────────────────────────────
        Timer {
            id: showBarTimer
            interval: Config?.options.bar.autoHide.showWhenPressingSuper.delay ?? 100
            repeat: false
            onTriggered: barRoot.superShow = true
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

        // ── Fullscreen detection ──────────────────────────────────────────────
        readonly property bool hasFullscreenWindowOnMonitor: {
            const monitorData = HyprlandData.monitors.find(m => m.name === barRoot.screen.name);
            const specialWsName = monitorData?.specialWorkspace?.name;
            const workspaces = Hyprland.workspaces.values.filter(w => w.monitor && w.monitor.name === barRoot.screen.name);
            return workspaces.some(workspace => {
                const isWorkspaceActive = workspace.active || (specialWsName && specialWsName !== "" && (workspace.name === specialWsName || workspace.name === "special:" + specialWsName || (specialWsName === "special:special" && workspace.name === "special") || (specialWsName === "special" && workspace.name === "special:special")));
                return isWorkspaceActive && workspace.toplevels.values.some(toplevel => toplevel.wayland && toplevel.wayland.fullscreen);
            });
        }

        property bool superShow: false
        property bool mustShow: hoverRegion.containsMouse || superShow || GlobalStates.sidebarLeftOpen || GlobalStates.sidebarRightOpen
        property real hiddenAmount: (Config?.options.bar.autoHide.enable && !mustShow) ? Appearance.sizes.barHeight : 0
        Behavior on hiddenAmount {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(barRoot)
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:bar"
        WlrLayershell.keyboardFocus: isSearchActiveHere ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Mask extends only over bar content (plus autoHide hover region).
        // Shadow from MultiEffect is visual-only and outside the mask.
        // In fullscreen, mask becomes empty to allow clicks through.
        mask: Region {
            item: barRoot.hasFullscreenWindowOnMonitor ? null : hoverMaskRegion
        }
        color: "transparent"
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Component.onCompleted: GlobalFocusGrab.addPersistent(barRoot)
        Component.onDestruction: GlobalFocusGrab.removePersistent(barRoot)

        // ── WrappedFrame visuals (fake screen rounding) ───────────────────────
        Loader {
            active: Config.options.appearance.fakeScreenRounding == 3 && Config.options.bar.cornerStyle !== 3
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

        // ── Hover region + BarContent ─────────────────────────────────────────
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
                readonly property real shadowExtend: 0
                readonly property real bottomMaskExtend: Config.options.bar.autoHide.enable ? Math.max(Config.options.bar.autoHide.hoverRegionWidth, shadowExtend) : shadowExtend
                readonly property real topMaskExtend: Config.options.bar.autoHide.enable ? Math.max(Config.options.bar.autoHide.hoverRegionWidth, shadowExtend) : shadowExtend
                anchors {
                    fill: barContent
                    topMargin: -topMaskExtend - (barContent.verticalTopOffset ?? 0)
                    bottomMargin: -bottomMaskExtend - (barContent.verticalBottomOffset ?? 0)
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

            // ── Round decorators (Hug style bottom corners) ───────────────────
            Loader {
                id: roundDecorators
                anchors {
                    left: parent.left
                    right: parent.right
                    top: barContent.bottom
                    bottom: undefined
                }
                height: Appearance.rounding.screenRounding
                active: barRoot.showBarBackground && Config.options.bar.cornerStyle === 0 && Config.options.bar.barBackgroundStyle !== 3 && Config.options.appearance.fakeScreenRounding != 3

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
