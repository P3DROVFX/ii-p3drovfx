import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.services

Scope {
    id: root

    // Reactive properties bound directly to HyprlandData
    readonly property bool isSpecialActive: {
        if (!HyprlandData.monitors) return false;
        return HyprlandData.monitors.some(mon => mon.specialWorkspace && mon.specialWorkspace.name !== "" && mon.specialWorkspace.id !== 0);
    }

    readonly property var activeSpecialWorkspace: {
        if (!HyprlandData.monitors) return null;
        const activeMon = HyprlandData.monitors.find(mon => mon.specialWorkspace && mon.specialWorkspace.name !== "" && mon.specialWorkspace.id !== 0);
        return activeMon ? activeMon.specialWorkspace : null;
    }
    
    readonly property string specialWorkspaceName: {
        return root.activeSpecialWorkspace ? root.activeSpecialWorkspace.name : "";
    }

    readonly property bool isSpecialEmpty: {
        if (!root.isSpecialActive || !root.activeSpecialWorkspace || !HyprlandData.windowListLoaded || !HyprlandData.windowList) return false;
        
        const specId = root.activeSpecialWorkspace.id;
        const specName = root.activeSpecialWorkspace.name;

        // Check if there are no windows inside the active special workspace matching by id or name.
        const specialWindows = HyprlandData.windowList.filter(win => {
            if (!win.workspace) return false;
            if (specId !== undefined && specId !== 0 && win.workspace.id === specId) return true;
            if (win.workspace.name) {
                if (win.workspace.name === specName) return true;
                if (win.workspace.name === "special:" + specName) return true;
                if (specName.startsWith("special:") && win.workspace.name === specName.replace(/^special:/, "")) return true;
            }
            return false;
        });
        
        return specialWindows.length === 0;
    }

    property bool shouldShowOverlay: false

    onShouldShowOverlayChanged: {
        GlobalStates.scratchpadEmptyOverlayActive = root.shouldShowOverlay;
    }

    Timer {
        id: emptyDebounceTimer
        interval: 150
        repeat: false
        onTriggered: {
            root.shouldShowOverlay = !GlobalStates.screenLocked && root.isSpecialActive && root.isSpecialEmpty;
        }
    }

    onIsSpecialActiveChanged: {
        if (!root.isSpecialActive || GlobalStates.screenLocked) {
            emptyDebounceTimer.stop();
            root.shouldShowOverlay = false;
        } else if (root.isSpecialEmpty) {
            emptyDebounceTimer.restart();
        }
    }

    onIsSpecialEmptyChanged: {
        if (!root.isSpecialEmpty || !root.isSpecialActive || GlobalStates.screenLocked) {
            emptyDebounceTimer.stop();
            root.shouldShowOverlay = false;
        } else {
            emptyDebounceTimer.restart();
        }
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                emptyDebounceTimer.stop();
                root.shouldShowOverlay = false;
            }
        }
    }

    Loader {
        id: overlayLoader
        // Show only when debounced overlay should show
        active: root.shouldShowOverlay
        
        sourceComponent: PanelWindow {
            id: overlayWindow
            screen: {
                if (!HyprlandData.monitors) return null;
                const activeMon = HyprlandData.monitors.find(mon => mon.specialWorkspace && mon.specialWorkspace.name !== "");
                if (!activeMon) return null;
                return Quickshell.screens.find(s => s.name === activeMon.name) ?? null;
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:scratchpad_empty_overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            visible: true
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Rectangle {
                anchors.fill: parent
                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
                opacity: 0.0

                Component.onCompleted: dimEntrance.start()

                NumberAnimation on opacity {
                    id: dimEntrance
                    from: 0.0
                    to: 1.0
                    duration: Math.round(350 * Appearance.animMultiplier)
                    easing.type: Easing.OutCubic
                }
            }

            ToolbarPairedFab {
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 24
                    rightMargin: 24
                    verticalCenter: undefined
                }
                iconText: "close"
                onClicked: {
                    var specName = root.specialWorkspaceName || "special";
                    if (specName.startsWith("special:")) {
                        specName = specName.substring(8);
                    }
                    Hyprland.dispatch(`hl.dsp.workspace.toggle_special("${specName}")`);
                }
                StyledToolTip {
                    text: Translation.tr("Close")
                }
            }

            ColumnLayout {
                anchors.centerIn: parent

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "layers_clear"
                    iconSize: 64
                    padding: 28
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                    shape: MaterialShape.Shape.Sunny
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    width: Math.min(overlayWindow.screen.width / 2, 800)
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.MarkdownText
                    wrapMode: Text.Wrap
                    text: `**${Translation.tr("Scratchpad")}**\n\n${Translation.tr("The scratchpad workspace is currently empty.")}\n\n${Translation.tr("Send windows here using SUPER + ALT + S.")}`
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                    palette.text: color
                    palette.windowText: color
                }
            }
        }
    }
}
