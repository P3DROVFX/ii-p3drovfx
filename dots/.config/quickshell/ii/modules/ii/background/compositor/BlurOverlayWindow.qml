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

    readonly property bool barVertical: Config.options.bar.vertical
    readonly property bool barBottom: Config.options.bar.bottom
    readonly property int barSize: barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight
    readonly property int gap: Appearance.gapsOut
    readonly property bool barEffective: GlobalStates.barOpen && !GlobalStates.screenLocked

    readonly property int baseMargin: (Config.options.appearance.fakeScreenRounding === 3) ? Config.options.appearance.wrappedFrameThickness : gap
    readonly property real leftSidebarOffset: (GlobalStates.policiesPinned && !GlobalStates.policiesDetached && GlobalStates.animatedLeftSidebarWidth > 0 && screen && screen.name === GlobalStates.activeLeftSidebarMonitor) ? GlobalStates.animatedLeftSidebarWidth : 0
    readonly property real rightSidebarOffset: 0

    // Shrink margins when closing to prevent compositor layer order race conditions from blurring top panels
    readonly property int marginLeft: isActive ? 0 : Math.max(baseMargin, (barEffective && barVertical && !barBottom) ? barSize : 0, leftSidebarOffset)
    readonly property int marginRight: isActive ? 0 : Math.max(baseMargin, (barEffective && barVertical && barBottom) ? barSize : 0, rightSidebarOffset)
    readonly property int marginTop: isActive ? 0 : Math.max(baseMargin, (barEffective && !barVertical && !barBottom) ? barSize : 0)
    readonly property int marginBottom: isActive ? 0 : Math.max(baseMargin, (barEffective && !barVertical && barBottom) ? barSize : 0)

    mask: Region {
        item: overlayDimRect
    }

    readonly property bool animEnabled: Config.options.background.zoomOutEnabled
    readonly property bool isMirroredStyle: Config.options.background.zoomOutStyle === 1
    readonly property bool isActive: animEnabled && isMirroredStyle && (GlobalStates.cheatsheetOpen || GlobalStates.overviewOpen) && ((Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") == (Hyprland.monitorFor(modelData) ? Hyprland.monitorFor(modelData).name : ""))

    visible: isActive || overlayDimRect.opacity > 0.01

    Rectangle {
        id: overlayDimRect
        x: blurOverlayWindow.marginLeft
        y: blurOverlayWindow.marginTop
        width: parent.width - blurOverlayWindow.marginLeft - blurOverlayWindow.marginRight
        height: parent.height - blurOverlayWindow.marginTop - blurOverlayWindow.marginBottom
        color: Qt.rgba(0, 0, 0, 0.25)
        opacity: blurOverlayWindow.isActive ? 1.0 : 0.0
        radius: {
            if (Config.options.appearance.fakeScreenRounding > 0)
                return Appearance.rounding.screenRounding;
            return 0;
        }

        Behavior on opacity {
            NumberAnimation {
                duration: blurOverlayWindow.isActive ? Appearance.animation.elementMoveEnter.duration : Appearance.animation.elementMoveExit.duration
                easing.type: blurOverlayWindow.isActive ? Appearance.animation.elementMoveEnter.type : Appearance.animation.elementMoveExit.type
                easing.bezierCurve: blurOverlayWindow.isActive ? Appearance.animation.elementMoveEnter.bezierCurve : Appearance.animation.elementMoveExit.bezierCurve
            }
        }
    }
}
