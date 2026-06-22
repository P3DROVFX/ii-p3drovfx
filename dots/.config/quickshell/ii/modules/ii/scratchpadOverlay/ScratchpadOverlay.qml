import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

Scope {
    id: root

    // Reactive properties bound directly to HyprlandData
    readonly property bool isSpecialActive: {
        if (!HyprlandData.monitors) return false;
        return HyprlandData.monitors.some(mon => mon.specialWorkspace && mon.specialWorkspace.name !== "");
    }
    
    readonly property string specialWorkspaceName: {
        if (!HyprlandData.monitors) return "";
        const activeMon = HyprlandData.monitors.find(mon => mon.specialWorkspace && mon.specialWorkspace.name !== "");
        return activeMon ? activeMon.specialWorkspace.name : "";
    }

    readonly property bool isSpecialEmpty: {
        if (!root.isSpecialActive || !HyprlandData.windowList) return false;
        
        // Check if there are no windows inside the active special workspace.
        const specialWindows = HyprlandData.windowList.filter(win => {
            if (!win.workspace || !win.workspace.name) return false;
            return win.workspace.name === root.specialWorkspaceName || 
                   win.workspace.name === "special:" + root.specialWorkspaceName ||
                   (root.specialWorkspaceName === "special:special" && win.workspace.name === "special") ||
                   (root.specialWorkspaceName === "special" && win.workspace.name === "special:special");
        });
        
        return specialWindows.length === 0;
    }

    Loader {
        id: overlayLoader
        // Show only when the special workspace is active AND has no windows inside it
        active: root.isSpecialActive && root.isSpecialEmpty
        
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
                // Highly premium slightly transparent scrim overlay with a subtle blur effect
                color: ColorUtils.transparentize(Appearance.m3colors.darkmode ? Appearance.m3colors.m3scrim : Appearance.m3colors.m3background, 0.25)

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                    }
                }

                // Close button at the top right - matching the screenTranslator ToolbarPairedFab design
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
                        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.workspace.toggle_special('special')"]);
                    }
                    StyledToolTip {
                        text: Translation.tr("Close")
                    }
                }

                // Centered message layout matching the ScreenTranslator no-API-key design
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16

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
}
