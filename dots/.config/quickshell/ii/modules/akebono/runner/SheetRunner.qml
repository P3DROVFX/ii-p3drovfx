pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.akebono
import qs.modules.lunae.overview
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    readonly property string activeScreen: Hyprland.focusedMonitor?.name ?? Quickshell.primaryScreen?.name ?? ""
    readonly property int surfaceWidth: Config.options.akebono.runner.sheetWidth
    readonly property int surfaceHeight: Config.options.akebono.runner.sheetHeight
    readonly property bool shown: GlobalStates.desktopRunnerOpen && Config.options.akebono.runner.style === "sheet"

    onShownChanged: {
        if (!root.shown)
            exitTimer.restart();
    }

    Timer {
        id: exitTimer
        interval: Appearance.animation.elementMoveFast.duration
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData

            Loader {
                active: (root.shown || exitTimer.running) && root.activeScreen === screenScope.modelData.name

                sourceComponent: PanelWindow {
                    id: sheetWindow
                    screen: screenScope.modelData
                    visible: !GlobalStates.screenLocked
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.namespace: "quickshell:akebonoSheetRunner"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Appearance.colors.colScrim
                        opacity: (Config.options.akebono.runner.dim && root.shown) ? 1 : 0

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: GlobalStates.desktopRunnerOpen = false
                    }

                    Squircle {
                        id: surface
                        anchors.centerIn: parent
                        implicitWidth: root.surfaceWidth
                        implicitHeight: root.surfaceHeight
                        color: Appearance.colors.colLayer0
                        radius: Appearance.rounding.large
                        smoothing: AkebonoAppearance.squircleSmoothing

                        property bool revealed: false
                        opacity: surface.revealed && root.shown ? 1 : 0
                        layer.enabled: surface.opacity < 1
                        layer.smooth: true

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }

                        Component.onCompleted: {
                            surface.revealed = true;
                            sheetPanel.focusSearch();
                        }
                        Component.onDestruction: sheetPanel.resetQuery()

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.AllButtons
                        }

                        SheetPanel {
                            id: sheetPanel
                            anchors.fill: parent

                            onRequestClose: GlobalStates.desktopRunnerOpen = false
                            onRightClicked: (entry, sceneX, sceneY) => {
                                const local = sheetMenu.mapFromItem(null, sceneX, sceneY);
                                sheetMenu.show(entry, local.x, local.y);
                            }
                        }
                    }

                    AppContextMenu {
                        id: sheetMenu
                        anchors.fill: parent
                        boundsWidth: sheetWindow.width
                        boundsHeight: sheetWindow.height
                    }
                }
            }
        }
    }
}
