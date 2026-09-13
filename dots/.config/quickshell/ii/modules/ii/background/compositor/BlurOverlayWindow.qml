import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common

PanelWindow {
    id: blurOverlayWindow

    required property var modelData
    screen: modelData
    readonly property var overviewController: GlobalStates.overviewBackgroundControllerFor(blurOverlayWindow.screen ? blurOverlayWindow.screen.name : "")

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:workspaceBlurOverlay"
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    mask: Region {
        item: overlayDimRect
    }

    readonly property bool isActive: overviewController
        && overviewController.useCompositorBlur
        && overviewController.progress > 0.001

    // This layer is matched by a Hyprland rule with compositor blur enabled.
    // It must be unmapped for every preset that does not request scene blur;
    // a non-zero dim amount alone must never turn Gnome Like into full-screen
    // blur.
    visible: isActive

    Rectangle {
        id: overlayDimRect
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: blurOverlayWindow.isActive && blurOverlayWindow.overviewController
            ? blurOverlayWindow.overviewController.dimAmount
            : 0.0
        radius: 0

    }
}
